#!/usr/bin/env python3
"""oracfit-distill.py — turn a usage report or a postmortem into a gotcha draft.

The distiller reads either a usage report (`incidents/uso/`, written by
`bin/emit-usage-feedback.sh`) or a human postmortem (`incidents/*.md`) and
writes a triad frame under `core/gotchas/drafts/`. It distinguishes the two
by the file itself: a `task` field is a usage report; `id` plus `titulo`
without `task` is a postmortem.

From a usage report the symptom is the round's diff (WIP ref against HEAD,
or the working tree against the recorded sha). From a postmortem the symptom
is the `## Sintoma` section, and a fire-fixture skeleton is written next to
the draft with citations copied from backtick literals in the file. The
trigger, the prescription and the skeleton's `signals` stay empty: those
are written by hand. This program does not promote, does not decide, does
not inject, does not invent a literal, and does not call a model.

Subcommands:
  distill --incident FILE [--wip-ref REF] [--out DIR] [--force]
  list [--dir DIR]

Exit: 0 ok · 1 failed · 3 usage error
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

BIN_DIR = Path(__file__).resolve().parent
DEFAULT_OUT = "core/gotchas/drafts"
NEEDS = ["prescription", "trigger", "canary.fire_fixture"]
QUIET_FIXTURE = "tests/fixtures/gotchas/healthy.json"
SHA_RE = re.compile(r"@([0-9a-fA-F]+)")
DIRTY_RE = re.compile(r"dirty=(\S+)")
BACKTICK_RE = re.compile(r"`([^`\n]+)`")
# english-ok-begin: usage reports and postmortems keep their original headings, keys and dirty=sim/nao
CONTEXT_HEADING = "Contexto"
SINTOMA_HEADING = "Sintoma"
TITULO_KEY = "titulo"
DIRTY_YES = "sim"
DIRTY_NO = "nao"
# english-ok-end


def load_gotcha() -> Any:
    """Import bin/oracfit-gotcha.py (hyphenated name) for SECTION_LIMIT and helpers."""
    path = BIN_DIR / "oracfit-gotcha.py"
    spec = importlib.util.spec_from_file_location("oracfit_gotcha", path)
    if spec is None or spec.loader is None:
        print("oracfit-distill: cannot import bin/oracfit-gotcha.py", file=sys.stderr)
        raise SystemExit(1)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


gotcha = load_gotcha()
SECTION_LIMIT = gotcha.SECTION_LIMIT
parse_frontmatter = gotcha.parse_frontmatter
dumps = gotcha.dumps
HEADING_RE = gotcha.HEADING_RE


class DistillParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        print(f"oracfit-distill: {message}", file=sys.stderr)
        raise SystemExit(3)


def git_clean_env() -> dict[str, str]:
    """Drop GIT_DIR and friends so `git -C <workdir>` hits that repository."""
    env = os.environ.copy()
    listed = subprocess.run(
        ["git", "rev-parse", "--local-env-vars"],
        capture_output=True,
        text=True,
    )
    if listed.returncode == 0:
        for name in listed.stdout.split():
            env.pop(name, None)
    return env


def run_git(workdir: str, args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(
        ["git", "-C", workdir, *args],
        capture_output=True,
        env=git_clean_env(),
    )
    text = proc.stdout.decode("utf-8", errors="replace")
    return proc.returncode, text


def is_git_repo(workdir: str) -> bool:
    rc, out = run_git(workdir, ["rev-parse", "--is-inside-work-tree"])
    return rc == 0 and out.strip() == "true"


def git_ref_exists(workdir: str, ref: str) -> bool:
    if not ref:
        return False
    rc, _ = run_git(workdir, ["rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"])
    return rc == 0


def strip_cell(value: str) -> str:
    return value.replace("`", "").strip()


def extract_named_section(body: str, name: str) -> str | None:
    """Body after a matching level-2 heading, or None if the heading is absent."""
    headings = list(HEADING_RE.finditer(body))
    for i, match in enumerate(headings):
        if match.group(1).strip() != name:
            continue
        start = match.end()
        if start < len(body) and body[start] == "\n":
            start += 1
        end = headings[i + 1].start() if i + 1 < len(headings) else len(body)
        return body[start:end]
    return None


def parse_context_table(section: str) -> dict[str, str]:
    rows: dict[str, str] = {}
    for line in section.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) < 2:
            continue
        key = strip_cell(cells[0])
        value = strip_cell(cells[1])
        if not key or set(key) <= {"-", ":"}:
            continue
        rows[key] = value
    return rows


def parse_sha(git_field: str) -> str:
    match = SHA_RE.search(git_field)
    if not match:
        return ""
    return match.group(1)


def working_tree_state(git_field: str) -> str | None:
    """Dirty/clean only when the report itself records it. None means do not claim."""
    match = DIRTY_RE.search(git_field)
    if not match:
        return None
    value = match.group(1)
    if value == DIRTY_YES:
        return "dirty"
    if value == DIRTY_NO:
        return "clean"
    return None


def factual_symptom(result: str, exit_code: str, git_field: str) -> str:
    bits = [f"result={result}", f"exit_code={exit_code}"]
    state = working_tree_state(git_field)
    if state is not None:
        bits.append(f"working_tree={state}")
    return "The usage report records " + ", ".join(bits) + "."


def truncate(text: str) -> str:
    return text[:SECTION_LIMIT]


def is_usage_report(meta: dict[str, str]) -> bool:
    return bool(meta.get("task", "").strip())


def is_postmortem(meta: dict[str, str]) -> bool:
    if is_usage_report(meta):
        return False
    gotcha_id = meta.get("id", "").strip()
    title = meta.get(TITULO_KEY, "").strip()
    return bool(gotcha_id and title)


def repo_relative(path: str) -> str:
    """Path relative to cwd or ORACFIT_ROOT when the file lives there."""
    given = Path(path)
    try:
        resolved = given.resolve()
    except OSError:
        return given.as_posix()
    roots: list[Path] = [Path.cwd()]
    env_root = os.environ.get("ORACFIT_ROOT")
    if env_root:
        roots.append(Path(env_root))
    for root in roots:
        try:
            rel = resolved.relative_to(root.resolve())
        except (OSError, ValueError):
            continue
        return rel.as_posix()
    return given.as_posix()


def citations_from(text: str) -> dict[str, str]:
    """Map each backtick literal to itself. Values are substrings of text."""
    citations: dict[str, str] = {}
    for literal in BACKTICK_RE.findall(text):
        if literal and literal not in citations:
            citations[literal] = literal
    return citations


def build_symptom(
    workdir: str,
    git_field: str,
    wip_ref: str | None,
    result: str,
    exit_code: str,
) -> str:
    if (
        wip_ref
        and os.path.isdir(workdir)
        and is_git_repo(workdir)
        and git_ref_exists(workdir, wip_ref)
    ):
        rc, text = run_git(workdir, ["diff", "HEAD", wip_ref])
        if rc == 0:
            return truncate(text)
    sha = parse_sha(git_field)
    if (
        os.path.isdir(workdir)
        and is_git_repo(workdir)
        and sha
        and git_ref_exists(workdir, sha)
    ):
        rc, text = run_git(workdir, ["diff", sha])
        if rc == 0:
            return truncate(text)
    return truncate(factual_symptom(result, exit_code, git_field))


def fire_fixture_path(task: str) -> str:
    return f"tests/fixtures/gotchas/{task}.fire.json"


def draft_payload(
    gotcha_id: str,
    title: str,
    incident_path: str,
    symptom: str,
    fire_fixture: str,
) -> dict[str, Any]:
    return {
        "id": gotcha_id,
        "title": title,
        "source_incident": incident_path,
        "symptom": symptom,
        "prescription": "",
        "trigger": {"class": "", "clauses": []},
        "canary": {
            "fire_fixture": fire_fixture,
            "quiet_fixture": QUIET_FIXTURE,
        },
        "status": "draft",
        "needs": list(NEEDS),
    }


def usage_draft_payload(
    task: str,
    result: str,
    exit_code: str,
    incident_path: str,
    symptom: str,
) -> dict[str, Any]:
    return draft_payload(
        task,
        f"{task}: {result} (exit {exit_code})",
        incident_path,
        symptom,
        fire_fixture_path(task),
    )


def write_draft(out_dir: Path, gotcha_id: str, payload: dict[str, Any], force: bool) -> int:
    dest = out_dir / f"{gotcha_id}.json"
    if dest.exists() and not force:
        print(
            f"oracfit-distill: draft already exists: {dest} (pass --force to overwrite)",
            file=sys.stderr,
        )
        return 1
    try:
        dest.write_text(dumps(payload), encoding="utf-8")
    except OSError as exc:
        print(f"oracfit-distill: cannot write {dest}: {exc}", file=sys.stderr)
        return 1
    return 0


def distill_postmortem(
    incident: str,
    text: str,
    meta: dict[str, str],
    body: str,
    out: str,
    force: bool,
) -> int:
    gotcha_id = meta.get("id", "").strip()
    title = meta.get(TITULO_KEY, "").strip()
    section = extract_named_section(body, SINTOMA_HEADING)
    if section is None:
        print(f"oracfit-distill: no symptom section in {incident}", file=sys.stderr)
        return 1

    source = repo_relative(incident)
    symptom = truncate(section.strip())
    out_dir = Path(out)
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"oracfit-distill: cannot create {out_dir}: {exc}", file=sys.stderr)
        return 1

    skeleton_path = out_dir / f"{gotcha_id}.fire.json"
    payload = draft_payload(
        gotcha_id,
        title,
        source,
        symptom,
        skeleton_path.as_posix(),
    )
    rc = write_draft(out_dir, gotcha_id, payload, force)
    if rc != 0:
        return rc

    skeleton = {
        "citations": citations_from(text),
        "signals": {},
        "source_incident": source,
    }
    try:
        skeleton_path.write_text(dumps(skeleton), encoding="utf-8")
    except OSError as exc:
        print(f"oracfit-distill: cannot write {skeleton_path}: {exc}", file=sys.stderr)
        return 1
    return 0


def cmd_distill(
    incident: str,
    wip_ref: str | None,
    out: str,
    force: bool,
) -> int:
    path = Path(incident)
    if not path.is_file():
        print(f"oracfit-distill: not a file: {incident}", file=sys.stderr)
        return 1
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        print(f"oracfit-distill: cannot read {incident}: {exc}", file=sys.stderr)
        return 1

    meta, body = parse_frontmatter(text)
    if is_postmortem(meta):
        return distill_postmortem(incident, text, meta, body, out, force)
    task = meta.get("task", "").strip()
    result = meta.get("result", "").strip()
    if not task:
        print(f"oracfit-distill: no task in frontmatter: {incident}", file=sys.stderr)
        return 1
    if not result:
        print(f"oracfit-distill: no result in frontmatter: {incident}", file=sys.stderr)
        return 1

    section = extract_named_section(body, CONTEXT_HEADING)
    if section is None:
        print(f"oracfit-distill: no context table in {incident}", file=sys.stderr)
        return 1
    context = parse_context_table(section)
    if "workdir" not in context:
        print(f"oracfit-distill: no workdir in the context table: {incident}", file=sys.stderr)
        return 1

    workdir = context.get("workdir", "")
    git_field = context.get("git", "")
    exit_code = context.get("exit_code", "")
    symptom = build_symptom(workdir, git_field, wip_ref, result, exit_code)
    payload = usage_draft_payload(task, result, exit_code, incident, symptom)

    out_dir = Path(out)
    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"oracfit-distill: cannot create {out_dir}: {exc}", file=sys.stderr)
        return 1
    return write_draft(out_dir, task, payload, force)


def format_needs(value: Any) -> str:
    if isinstance(value, list):
        return ",".join(str(item) for item in value)
    if value is None:
        return ""
    return str(value)


def cmd_list(directory: str) -> int:
    path = Path(directory)
    if not path.is_dir():
        print(f"oracfit-distill: not a directory: {directory}", file=sys.stderr)
        return 1
    rows: list[tuple[str, str]] = []
    for file in sorted(path.glob("*.json")):
        if not file.is_file():
            continue
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            continue
        if not isinstance(data, dict):
            continue
        gotcha_id = str(data.get("id") or file.stem)
        status = str(data.get("status") or "")
        symptom = data.get("symptom")
        n = len(symptom) if isinstance(symptom, str) else 0
        needs = format_needs(data.get("needs"))
        line = f"{gotcha_id}  status={status}  symptom_chars={n}  needs={needs}"
        rows.append((gotcha_id, line))
    rows.sort(key=lambda item: item[0])
    for _, line in rows:
        print(line)
    return 0


def build_parser() -> DistillParser:
    parser = DistillParser(
        prog="oracfit-distill",
        description="Distill a usage report or a postmortem into a gotcha draft. Does not invent a trigger.",
    )
    sub = parser.add_subparsers(dest="cmd")

    distill_p = sub.add_parser(
        "distill",
        help="write a draft triad from a usage report or a postmortem",
    )
    distill_p.add_argument(
        "--incident",
        required=True,
        help="usage report or postmortem markdown",
    )
    distill_p.add_argument(
        "--wip-ref",
        dest="wip_ref",
        default=None,
        help="WIP snapshot ref (git diff HEAD <ref> when the ref exists)",
    )
    distill_p.add_argument(
        "--out",
        default=DEFAULT_OUT,
        help=f"draft directory (default: {DEFAULT_OUT})",
    )
    distill_p.add_argument(
        "--force",
        action="store_true",
        help="overwrite an existing draft",
    )

    list_p = sub.add_parser("list", help="one line per draft")
    list_p.add_argument(
        "--dir",
        default=DEFAULT_OUT,
        help=f"draft directory (default: {DEFAULT_OUT})",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.cmd:
        parser.print_usage(sys.stderr)
        print("oracfit-distill: expected a subcommand", file=sys.stderr)
        return 3
    if args.cmd == "distill":
        return cmd_distill(args.incident, args.wip_ref, args.out, args.force)
    if args.cmd == "list":
        return cmd_list(args.dir)
    parser.print_usage(sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
