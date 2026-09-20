#!/usr/bin/env python3
"""Check numeric facts in a generated bundle against a spec.

Usage:
    check-bundle-facts.py SPEC_FILE BUNDLE_FILE_OR_DIRECTORY

Only numbers with one of these declared units are checked:
GB, TB, R$, W, fps, GHz, MHz, mm, %.
Numbers without a unit are deliberately ignored.

The source of truth is the ``## Dados verificados`` section in SPEC_FILE.
Brazilian formatting is normalized before comparison, so ``R$ 4.290,00``
matches ``R$ 4290`` and ``3,20 GHz`` matches ``3.2GHz``.

Legitimate derived values must be declared explicitly in a separate section:

    ## Números derivados permitidos
    - derived: R$ 357,50 <- R$ 4.290,00 / 12 — parcela mensal

The ``derived: TARGET <- SOURCE — REASON`` form is intentionally strict.  The
target is allowed, at most, when at least one unit-bearing source value is also
present in ``Dados verificados``; the reason is required for auditability.
Malformed whitelist lines fail closed.  The arithmetic is not inferred by an
LLM (or by this gate): the declaration is the auditable decision.

Exit status:
    0  every unit-bearing bundle value is grounded or explicitly whitelisted
    1  a bundle value is not grounded, or the spec/whitelist is unsafe
    2  invalid command-line arguments or missing paths
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path


UNIT_ORDER = ("GB", "TB", "R$", "W", "fps", "GHz", "MHz", "mm", "%")
UNIT_BY_LOWER = {unit.lower(): unit for unit in UNIT_ORDER}
NUMBER = r"[+-]?(?:\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:[.,]\d+)?)"

DATA_SECTION = re.compile(
    r"(?ims)^##[ \t]+(?:dados[ \t]+verificados|verified[ \t]+data)[^\n]*\n"
    r"(?P<body>.*?)(?=^##[ \t]|\Z)"
)
DERIVED_SECTION = re.compile(
    r"(?ims)^##[ \t]+(?:n[uú]meros[ \t]+derivados[ \t]+permitidos|"
    r"derived[ \t]+numbers[ \t]+whitelist)[^\n]*\n"
    r"(?P<body>.*?)(?=^##[ \t]|\Z)"
)
DERIVED_LINE = re.compile(
    r"(?i)^[ \t]*-[ \t]*derived:[ \t]*(?P<target>.+?)"
    r"[ \t]*<-[ \t]*(?P<source>.+?)"
    r"[ \t]+[—-][ \t]*(?P<reason>\S(?:.*\S)?)\s*$"
)

PREFIX_CURRENCY = re.compile(
    rf"(?i)(?<![\w.,])(?P<unit>R\$)[ \t]*(?P<number>{NUMBER})"
)
SUFFIX_UNITS = re.compile(
    rf"(?i)(?<![\w.,])(?P<number>{NUMBER})[ \t]*"
    rf"(?P<unit>GB|TB|W|fps|GHz|MHz|mm|%)(?!\w)"
)
SUFFIX_CURRENCY = re.compile(
    rf"(?i)(?<![\w.,])(?P<number>{NUMBER})[ \t]*(?P<unit>R\$)(?!\w)"
)


@dataclass(frozen=True)
class Fact:
    unit: str
    value: Decimal
    raw: str
    line_no: int = 0
    line: str = ""
    source: str = ""

    @property
    def key(self) -> tuple[str, Decimal]:
        return self.unit, self.value


def normalize_number(raw: str) -> Decimal:
    """Normalize Brazilian grouping/decimal punctuation to Decimal.

    A comma is always the decimal separator in the supported Brazilian form.
    A dot-only value with groups of exactly three digits is a thousands-grouped
    integer (``4.290``); other dot-only values are decimal (``3.2``).
    """
    value = raw.strip().replace(" ", "")
    sign = ""
    if value[:1] in ("+", "-"):
        sign, value = value[0], value[1:]

    if "," in value:
        if "." in value:
            value = value.replace(".", "").replace(",", ".")
        else:
            value = value.replace(",", ".")
    elif "." in value:
        groups = value.split(".")
        if len(groups) > 1 and len(groups[0]) <= 3 and all(
            len(group) == 3 for group in groups[1:]
        ):
            value = "".join(groups)

    try:
        return Decimal(f"{sign}{value}").normalize()
    except InvalidOperation as exc:
        raise ValueError(f"invalid numeric token {raw!r}") from exc


def canonical_unit(raw: str) -> str:
    return UNIT_BY_LOWER[raw.lower()]


def _fact_from_match(match: re.Match[str], text: str) -> Fact:
    number = match.group("number")
    unit = canonical_unit(match.group("unit"))
    start, end = match.span()
    line_no = text.count("\n", 0, start) + 1
    line_start = text.rfind("\n", 0, start) + 1
    line_end = text.find("\n", end)
    if line_end == -1:
        line_end = len(text)
    return Fact(
        unit=unit,
        value=normalize_number(number),
        raw=match.group(0).strip(),
        line_no=line_no,
        line=text[line_start:line_end].strip(),
    )


def extract_facts(text: str) -> list[Fact]:
    """Extract each supported numeric-unit token, preserving source context."""
    matches: list[re.Match[str]] = []
    for pattern in (PREFIX_CURRENCY, SUFFIX_UNITS, SUFFIX_CURRENCY):
        matches.extend(pattern.finditer(text))

    # The patterns do not normally overlap, but deterministic de-duplication
    # prevents a future unit alias from reporting one token twice.
    unique: dict[tuple[int, int, str], Fact] = {}
    for match in matches:
        fact = _fact_from_match(match, text)
        unique[(match.start(), match.end(), fact.unit)] = fact
    return [
        unique[key]
        for key in sorted(unique, key=lambda item: (item[0], item[1], item[2]))
    ]


def fact_display(fact: Fact) -> str:
    rendered = format(fact.value, "f")
    if "." in rendered:
        rendered = rendered.rstrip("0").rstrip(".")
    if rendered in ("", "-0"):
        rendered = "0"
    return f"{rendered} {fact.unit}"


def section_body(pattern: re.Pattern[str], text: str) -> str | None:
    match = pattern.search(text)
    return match.group("body") if match else None


def parse_derived_whitelist(
    text: str, ground_truth: set[tuple[str, Decimal]]
) -> tuple[set[tuple[str, Decimal]], list[str]]:
    body = section_body(DERIVED_SECTION, text)
    if body is None:
        return set(), []

    allowed: set[tuple[str, Decimal]] = set()
    errors: list[str] = []
    for line_no, raw_line in enumerate(body.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = DERIVED_LINE.match(raw_line)
        if not match:
            errors.append(
                f"derived whitelist line {line_no} is invalid; expected "
                "'- derived: TARGET <- SOURCE — REASON'"
            )
            continue

        targets = extract_facts(match.group("target"))
        sources = extract_facts(match.group("source"))
        if len(targets) != 1:
            errors.append(
                f"derived whitelist line {line_no} must contain exactly one "
                "unit-bearing target"
            )
            continue
        if not sources:
            errors.append(
                f"derived whitelist line {line_no} must cite a unit-bearing "
                "ground-truth source"
            )
            continue
        if not any(source.key in ground_truth for source in sources):
            cited = ", ".join(fact_display(source) for source in sources)
            errors.append(
                f"derived whitelist line {line_no} cites no ground-truth "
                f"source ({cited})"
            )
            continue
        allowed.add(targets[0].key)
    return allowed, errors


def bundle_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    return sorted(candidate for candidate in path.rglob("*") if candidate.is_file())


def read_text_file(path: Path) -> str | None:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        print(f"ERROR: cannot read bundle file {path}: {exc}", file=sys.stderr)
        return None
    # Images and other binary artifacts are not prose bundles.  Ignoring them
    # avoids treating an incidental byte sequence as a numeric fact.
    if b"\0" in raw:
        return None
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return None


def check(spec_path: Path, bundle_path: Path) -> int:
    if not spec_path.is_file():
        print(f"ERROR: spec not found: {spec_path}", file=sys.stderr)
        return 2
    if not bundle_path.exists():
        print(f"ERROR: bundle path not found: {bundle_path}", file=sys.stderr)
        return 2
    if not (bundle_path.is_file() or bundle_path.is_dir()):
        print(f"ERROR: bundle path is not a file or directory: {bundle_path}", file=sys.stderr)
        return 2

    try:
        spec_text = spec_path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: cannot read spec {spec_path}: {exc}", file=sys.stderr)
        return 2

    data_body = section_body(DATA_SECTION, spec_text)
    if data_body is None:
        print(
            f"FAIL: spec has no ## Dados verificados section: {spec_path}",
            file=sys.stderr,
        )
        return 1

    ground_truth = {fact.key for fact in extract_facts(data_body)}
    expected_by_unit: dict[str, set[Decimal]] = {unit: set() for unit in UNIT_ORDER}
    for unit, value in ground_truth:
        expected_by_unit.setdefault(unit, set()).add(value)

    derived, whitelist_errors = parse_derived_whitelist(spec_text, ground_truth)
    if whitelist_errors:
        print("FAIL: derived-number whitelist is invalid (closed gate)", file=sys.stderr)
        for error in whitelist_errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    failures: list[tuple[Path, Fact]] = []
    for file_path in bundle_files(bundle_path):
        text = read_text_file(file_path)
        if text is None:
            continue
        for fact in extract_facts(text):
            if fact.key not in ground_truth and fact.key not in derived:
                failures.append((file_path, fact))

    if failures:
        print(
            f"FAIL: {len(failures)} bundle numeric fact(s) are not in "
            f"ground truth for {bundle_path}:",
            file=sys.stderr,
        )
        for file_path, fact in failures:
            expected = expected_by_unit.get(fact.unit, set())
            expected_text = (
                ", ".join(
                    fact_display(Fact(fact.unit, value, ""))
                    for value in sorted(expected)
                )
                if expected
                else "<empty>"
            )
            print(f"  bundle value: {fact.raw} (normalized: {fact_display(fact)})", file=sys.stderr)
            print(f"  expected ground-truth set for {fact.unit}: {{{expected_text}}}", file=sys.stderr)
            print(
                f"  source line: {file_path}:{fact.line_no}: {fact.line}",
                file=sys.stderr,
            )
        return 1

    print(
        f"OK: checked {sum(1 for path in bundle_files(bundle_path) if path.is_file())} "
        f"bundle file(s); all unit-bearing values are grounded",
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path)
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args()
    return check(args.spec, args.bundle)


if __name__ == "__main__":
    sys.exit(main())
