#!/usr/bin/env python3
"""Oracfit mode YAML schema v1 loader — validate, resolve-tier, dump."""

import json
import re
import sys
from pathlib import Path

ALLOWED_ROOT = {
    "id", "version", "description", "name", "max_attempts",
    "stages", "preflight", "on_fail", "gauntlet",
    "publish",                  # v3: publish config (requires: human_approval)
    "run_attempt_budget",       # v3: global budget for role=run attempts
    "global_run_attempt_budget",  # compatibility alias for the same budget
}
ALLOWED_STAGE = {
    "role", "model_ref", "oracle", "rate_limit_s", "input",
    "prompt_template", "json_schema", "artifacts", "max_attempts",
    "tools", "loop_target",          # v3: loop_target volta pro stage nomeado quando falha
    "command",                       # v3: comando literal pra stage mecânico (sem model_ref)
    "stage_oracle", "oracle_command",  # deterministic post-command stage gate
    "preflight", "preflight_command",  # deterministic pre-attempt gate
    "freshness_targets", "visual_freshness_targets",  # visual artifact targets
    "owner_question",                # S8: stage may pause for ONE owner question
}
ALLOWED_GAUNTLET = {
    "enabled", "until_approved", "safety_ceiling",
    "inject_feedback", "critic_model_ref", "loop_target",  # v3: gauntlet-level loop_target
}
# v3: roles do content_factory end-to-end (run → export → render → vision_gate)
ROLES = {"unlock", "plan", "run", "map", "reduce", "export", "render", "vision_gate"}

REGISTRY_PATH = Path(__file__).resolve().parent.parent / "model-registry.json"

_DEFAULT_TIERS = {
    "cheap": "deepseek-v4-flash-free",
    "mid": "deepseek/deepseek-v4-chat",
    "expensive": "google/gemini-2.5-pro-001",
    "vision": "meta/llama-3.2-90b-vision-instruct",
}
_TIER_FALLBACKS = {
    "cheap": "deepseek-v4-flash-free",
    "mid": "llama-3.3-70b-versatile",
    "expensive": None,
    "vision": "google/gemma-3-27b-vision-it:free",
}


def _load_yaml(text):
    """Minimal YAML parser — enough for our three fixtures."""
    lines = text.split("\n")
    result = {}
    stack = [result]
    indent_stack = [0]
    list_idx_stack = []
    current_list = None

    i = 0
    while i < len(lines):
        raw = lines[i]
        if not raw.strip() or raw.strip().startswith("#"):
            i += 1
            continue
        stripped = raw.lstrip()
        indent = len(raw) - len(stripped)

        while indent_stack and indent < indent_stack[-1]:
            stack.pop()
            indent_stack.pop()
            if list_idx_stack:
                list_idx_stack.pop()
            current_list = None

        if stripped.startswith("- "):
            item_text = stripped[2:]
            parent = stack[-1]
            if current_list is None:
                if not isinstance(parent, list):
                    parent.clear()
                current_list = parent
            if ":" in item_text:
                key, val = _split_keyval(item_text)
                entry = {key: _parse_val(val)}
                current_list.append(entry)
                stack.append(entry)
                indent_stack.append(indent + 2)
                list_idx_stack.append(len(current_list) - 1)
            else:
                current_list.append(_parse_val(item_text))
            i += 1
            continue

        if ":" in stripped:
            key, val = _split_keyval(stripped)
            target = stack[-1]
            if isinstance(target, list) and len(target) > 0:
                if list_idx_stack:
                    target = target[list_idx_stack[-1]]
            target[key] = _parse_val(val)
            if val == "" or val.startswith(">"):
                folded_lines = []
                i += 1
                while i < len(lines):
                    next_raw = lines[i]
                    next_stripped = next_raw.lstrip()
                    next_indent = len(next_raw) - len(next_stripped)
                    if next_indent > indent and next_stripped and not next_stripped.startswith("#"):
                        folded_lines.append(next_stripped)
                        i += 1
                    else:
                        break
                target[key] = " ".join(folded_lines)
                continue
            i += 1
            continue
        i += 1

    return result


def _split_keyval(line):
    colon_idx = line.index(":")
    key = line[:colon_idx].strip()
    val = line[colon_idx + 1:].strip()
    return key, val


def _parse_val(val):
    if val == "":
        return ""
    if val.lower() in ("true", "yes"):
        return True
    if val.lower() in ("false", "no"):
        return False
    try:
        return int(val)
    except ValueError:
        try:
            return float(val)
        except ValueError:
            pass
    return val


def _find_unknown_keys(data, path=""):
    """Recursively find keys not in allowlists."""
    import re
    unknown = []
    if isinstance(data, dict):
        for key in data:
            current_path = f"{path}.{key}" if path else key
            if path == "":
                if key not in ALLOWED_ROOT:
                    unknown.append(current_path)
            elif path == "gauntlet":
                if key not in ALLOWED_GAUNTLET:
                    unknown.append(current_path)
            elif re.match(r"^stages\[\d+\]$", path):
                if key not in ALLOWED_STAGE:
                    unknown.append(current_path)
            else:
                # Unknown nesting (e.g. stages[0].foo.bar) — flag the key.
                if not path.startswith("gauntlet"):
                    unknown.append(current_path)
            unknown += _find_unknown_keys(data[key], current_path)
    elif isinstance(data, list):
        for idx, item in enumerate(data):
            unknown += _find_unknown_keys(item, f"{path}[{idx}]")
    return unknown


def _find_stages(data):
    """Extract the stages list from parsed YAML."""
    if isinstance(data, dict) and "stages" in data:
        stages = data["stages"]
        if isinstance(stages, list):
            return stages
    return []


def validate(path):
    p = Path(path)
    if not p.exists():
        print(f"ERROR: file not found: {p}", file=sys.stderr)
        sys.exit(3)
    try:
        text = p.read_text(encoding="utf-8")
    except (OSError, PermissionError) as e:
        print(f"ERROR: cannot read {p}: {e}", file=sys.stderr)
        sys.exit(3)

    try:
        import yaml as _yaml_lib
        data = _yaml_lib.safe_load(text)
    except ImportError:
        data = _load_yaml(text)

    if not isinstance(data, dict):
        print(f"FAIL {p}: empty or invalid yaml", file=sys.stderr)
        sys.exit(2)

    unknown = _find_unknown_keys(data)
    if unknown:
        for k in unknown:
            print(f"FAIL {p}: unknown key '{k}'", file=sys.stderr)
        sys.exit(2)

    required = ["id", "version", "stages"]
    missing = [r for r in required if r not in data]
    if missing:
        print(f"FAIL {p}: missing required root key(s): {missing}", file=sys.stderr)
        sys.exit(2)

    stages = _find_stages(data)
    if not stages:
        print(f"FAIL {p}: stages list is empty or missing", file=sys.stderr)
        sys.exit(2)

    bad_roles = []
    has_map = False
    for stage in stages:
        if not isinstance(stage, dict):
            print(f"FAIL {p}: stage entry is not a mapping", file=sys.stderr)
            sys.exit(2)
        role = stage.get("role", "")
        if role not in ROLES:
            bad_roles.append(role)
        if role == "map":
            has_map = True
            rls = stage.get("rate_limit_s")
            if rls is None or not isinstance(rls, (int, float)) or rls <= 0:
                print(f"FAIL {p}: map stage requires rate_limit_s > 0", file=sys.stderr)
                sys.exit(2)
        oracle = stage.get("oracle")
        if oracle is not None:
            if not (isinstance(oracle, bool) and oracle is True) and not (isinstance(oracle, str) and oracle):
                print(f"FAIL {p}: oracle must be bool true or non-empty string, got {type(oracle).__name__}: {oracle}", file=sys.stderr)
                sys.exit(2)

        # S8 owner_question: bool true ou string não-vazia (ex.: once)
        owner_q = stage.get("owner_question")
        if owner_q is not None:
            if not (isinstance(owner_q, bool) and owner_q is True) and not (isinstance(owner_q, str) and owner_q.strip()):
                print(f"FAIL {p}: owner_question must be bool true or non-empty string, got {type(owner_q).__name__}: {owner_q}", file=sys.stderr)
                sys.exit(2)

        for key in ("stage_oracle", "oracle_command", "preflight", "preflight_command"):
            if key in stage and (
                not isinstance(stage[key], str) or not stage[key].strip()
            ):
                print(
                    f"FAIL {p}: {key} must be a non-empty command string",
                    file=sys.stderr,
                )
                sys.exit(2)

        freshness_keys = [
            key for key in ("freshness_targets", "visual_freshness_targets")
            if key in stage
        ]
        for key in freshness_keys:
            targets = stage[key]
            if (
                not isinstance(targets, list)
                or not targets
                or any(not isinstance(target, str) or not target.strip() for target in targets)
            ):
                print(
                    f"FAIL {p}: {key} must be a non-empty list of path strings",
                    file=sys.stderr,
                )
                sys.exit(2)

    budget_keys = [
        key for key in ("run_attempt_budget", "global_run_attempt_budget")
        if key in data
    ]
    for key in budget_keys:
        budget = data[key]
        if isinstance(budget, bool) or not isinstance(budget, int) or budget <= 0:
            print(
                f"FAIL {p}: {key} must be a positive integer",
                file=sys.stderr,
            )
            sys.exit(2)
    if (
        "run_attempt_budget" in data
        and "global_run_attempt_budget" in data
        and data["run_attempt_budget"] != data["global_run_attempt_budget"]
    ):
        print(
            f"FAIL {p}: run_attempt_budget and global_run_attempt_budget disagree",
            file=sys.stderr,
        )
        sys.exit(2)

    if bad_roles:
        print(f"FAIL {p}: bad roles: {bad_roles}", file=sys.stderr)
        sys.exit(2)

    print(f"OK {p} roles={[s.get('role','') for s in stages]}")
    sys.exit(0)


# ── lint v4: claims→mecanismos + shadow de id (regra 32 mecanizada) ──────────
#
# Incidentes-fonte:
#   - aion: yaml DECLARAVA a fragilidade do despertador e ela o matou aos 102s
#     ("limitação declarada" não é mitigação; claim sem mecanismo não registra)
#   - demiurgo: yaml alegava "hard-fails mecânicos" que não eram código
#     (mentir a classe da proteção)
#   - autarca: 9 cláusulas de hardening manuscritas — 2 letra morta, 2
#     degradadas em horas (cláusula ≠ mecanismo)
#   - colisão hefesto: dois modos distintos com o mesmo id a 4min de distância
#
# Contrato: claims na DESCRIPTION (campo de máquina) exigem declaração
# `# mecanismo(<classe>): <path>` no yaml apontando executável EXISTENTE.
# Comentário continua sendo protocolo — o lint é o mecanismo que verifica
# que a declaração aponta para código de verdade.

CLAIM_CLASSES = {
    "wake": ["perpetu", "despertador", "watchdog", "cadeia contínua",
             "cadeia continua", "auto-dirig", "anel após anel",
             "anel apos anel", "loop contínuo", "loop continuo"],
    "ring": ["ledger"],
    "visual": ["gate visual", "juízo visual", "juizo visual"],
}
GENERIC_MECH_WORDS = ["mecânic", "mecanic"]
MECH_DECL_RE = re.compile(r"^\s*#\s*mecanismo\(([a-z_]+)\):\s*(\S+)", re.MULTILINE)


def _lint(path, root=None, workdir=None, strict=False):
    import os
    p = Path(path)
    if not p.exists():
        print(f"ERROR: file not found: {p}", file=sys.stderr)
        sys.exit(3)
    text = p.read_text(encoding="utf-8")
    try:
        import yaml as _yaml_lib
        data = _yaml_lib.safe_load(text)
    except ImportError:
        data = _load_yaml(text)
    if not isinstance(data, dict):
        print(f"LINT FAIL {p}: yaml vazio ou inválido", file=sys.stderr)
        sys.exit(2)

    root = Path(root) if root else Path(__file__).resolve().parent.parent
    failures = []
    warnings = []

    # (1) id deve bater com o nome do arquivo (colisão hefesto)
    mode_id = str(data.get("id", ""))
    if mode_id and p.stem != mode_id:
        failures.append(f"id '{mode_id}' != nome do arquivo '{p.stem}' (colisão de id)")

    # (2) shadow: mesmo id em workdir E root com conteúdo diferente
    if workdir and mode_id:
        wd_file = Path(workdir) / "core" / "modes" / f"{mode_id}.yaml"
        root_file = root / "core" / "modes" / f"{mode_id}.yaml"
        if (wd_file.exists() and root_file.exists()
                and wd_file.resolve() != root_file.resolve()
                and wd_file.read_text() != root_file.read_text()):
            msg = (f"id '{mode_id}' existe em workdir E root com conteúdo "
                   f"DIFERENTE — overlay silencioso (colisão hefesto)")
            (failures if strict else warnings).append(msg)

    # (3) declarações de mecanismo: cada uma aponta executável existente
    decls = {}
    for m in MECH_DECL_RE.finditer(text):
        klass, mech_path = m.group(1), m.group(2)
        resolved = Path(mech_path) if mech_path.startswith("/") else root / mech_path
        if not resolved.exists():
            failures.append(f"mecanismo({klass}) aponta para path inexistente: {mech_path} "
                            f"(mentir classe de proteção — demiurgo)")
        elif not os.access(resolved, os.X_OK):
            failures.append(f"mecanismo({klass}): {mech_path} existe mas não é executável")
        else:
            decls[klass] = mech_path

    # (4) claims da description exigem mecanismo da classe correspondente
    description = str(data.get("description", "")).lower()
    for klass, keywords in CLAIM_CLASSES.items():
        claimed = [k for k in keywords if k in description]
        if claimed and klass not in decls:
            failures.append(
                f"description alega '{claimed[0]}' (classe {klass}) sem "
                f"`# mecanismo({klass}): <path>` — claim sem mecanismo não registra (aion)")

    # (5) "mecânico" na description exige ao menos UMA declaração válida
    if any(w in description for w in GENERIC_MECH_WORDS) and not decls:
        failures.append("description diz 'mecânico' mas o yaml não declara nenhum "
                        "`# mecanismo(...): <path>` (regra 32: mecanismo ou dívida)")

    for w in warnings:
        print(f"LINT WARN {p}: {w}", file=sys.stderr)
    if failures:
        for f in failures:
            print(f"LINT FAIL {p}: {f}", file=sys.stderr)
        sys.exit(2)
    print(f"LINT OK {p} (mecanismos declarados: {sorted(decls) or 'nenhum'})")
    sys.exit(0)


def _load_registry(registry_path=None):
    reg_path = Path(registry_path) if registry_path else REGISTRY_PATH
    if not reg_path.exists():
        return None
    try:
        data = json.loads(reg_path.read_text(encoding="utf-8"))
        return data.get("models", [])
    except (json.JSONDecodeError, OSError):
        return None


def resolve_tier(tier, registry_path=None):
    tier = tier.removeprefix("tier:")

    models = _load_registry(registry_path)

    if models:
        if tier == "cheap":
            for m in models:
                if m.get("id") == "deepseek-v4-flash-free":
                    print(m["id"])
                    return
            for m in models:
                if m.get("id") == "deepseek-v4-flash-openrouter":
                    print(m["id"])
                    return
            for m in models:
                bf = m.get("best_for") or []
                if "mais barato" in bf or "cheap" in bf:
                    print(m["id"])
                    return

        elif tier == "mid":
            for m in models:
                if m.get("id") == "deepseek/deepseek-v4-chat":
                    print(m["id"])
                    return
            for m in models:
                if m.get("id") == "llama-3.3-70b-versatile":
                    print(m["id"])
                    return
            for m in models:
                bf = m.get("best_for") or []
                if "raciocínio médio" in bf or "código" in bf:
                    if m.get("tier") in ("paid", "free"):
                        print(m["id"])
                        return

        elif tier == "expensive":
            for m in models:
                mid = m.get("id", "")
                t = m.get("tier", "")
                if t == "paid" and ("frontier" in mid.lower() or "pro" in mid.lower()):
                    print(m["id"])
                    return
            for m in models:
                if m.get("id") == "google/gemini-2.5-pro-001":
                    print(m["id"])
                    return
            for m in models:
                bf = m.get("best_for") or []
                if "melhor qualidade" in bf:
                    print(m["id"])
                    return

        elif tier == "vision":
            for m in models:
                if m.get("id") == "meta/llama-3.2-90b-vision-instruct":
                    print(m["id"])
                    return
            for m in models:
                if m.get("id") == "google/gemma-3-27b-vision-it:free":
                    print(m["id"])
                    return
            for m in models:
                bf = m.get("best_for") or []
                if any("visão" in b or "vision" in b for b in bf):
                    print(m["id"])
                    return
                mid = m.get("id", "")
                if "vision" in mid.lower() or "visão" in mid.lower():
                    print(m["id"])
                    return

    default = _DEFAULT_TIERS.get(tier)
    fallback = _TIER_FALLBACKS.get(tier)
    if default:
        print(default)
    elif fallback:
        print(fallback)
    else:
        print(f"ERROR: no model for tier:{tier}", file=sys.stderr)
        sys.exit(2)


def dump(path):
    p = Path(path)
    if not p.exists():
        print(f"ERROR: file not found: {p}", file=sys.stderr)
        sys.exit(3)
    try:
        text = p.read_text(encoding="utf-8")
    except (OSError, PermissionError) as e:
        print(f"ERROR: cannot read {p}: {e}", file=sys.stderr)
        sys.exit(3)

    try:
        import yaml as _yaml_lib
        data = _yaml_lib.safe_load(text)
    except ImportError:
        data = _load_yaml(text)

    if not isinstance(data, dict):
        data = {}

    json.dump(data, sys.stdout, indent=2, ensure_ascii=False)
    print()


def main():
    if len(sys.argv) < 2:
        print("Usage:", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py validate <path.yaml>", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py lint <path.yaml> [--root DIR] [--workdir DIR] [--strict]", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py resolve-tier <tier> [--registry path.json]", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py dump <path.yaml>", file=sys.stderr)
        sys.exit(2)

    cmd = sys.argv[1]

    if cmd == "validate":
        if len(sys.argv) < 3:
            print("Usage: validate <path.yaml>", file=sys.stderr)
            sys.exit(2)
        validate(sys.argv[2])

    elif cmd == "lint":
        if len(sys.argv) < 3:
            print("Usage: lint <path.yaml> [--root DIR] [--workdir DIR] [--strict]", file=sys.stderr)
            sys.exit(2)
        args = sys.argv[3:]
        root = workdir = None
        strict = False
        i = 0
        while i < len(args):
            if args[i] == "--root" and i + 1 < len(args):
                root = args[i + 1]; i += 2
            elif args[i] == "--workdir" and i + 1 < len(args):
                workdir = args[i + 1]; i += 2
            elif args[i] == "--strict":
                strict = True; i += 1
            else:
                i += 1
        _lint(sys.argv[2], root=root, workdir=workdir, strict=strict)

    elif cmd == "resolve-tier":
        if len(sys.argv) < 3:
            print("Usage: resolve-tier <tier> [--registry path.json]", file=sys.stderr)
            sys.exit(2)
        tier = sys.argv[2]
        registry_path = None
        if len(sys.argv) > 3 and sys.argv[3] == "--registry" and len(sys.argv) > 4:
            registry_path = sys.argv[4]
        resolve_tier(tier, registry_path)

    elif cmd == "dump":
        if len(sys.argv) < 3:
            print("Usage: dump <path.yaml>", file=sys.stderr)
            sys.exit(2)
        dump(sys.argv[2])

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()