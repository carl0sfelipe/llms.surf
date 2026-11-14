#!/usr/bin/env python3
"""Oracfit mode YAML schema v1 loader — validate, resolve-tier, dump, promises."""

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

# The ceiling of a single throttle wait, in seconds. The runtime caps the
# wait at the same number (ORACFIT_RATE_LIMIT_MAX_S in
# bin/lib-oracfit-rate-limit.sh) - rule 12: no command without a ceiling.
RATE_LIMIT_MAX_S = 3600

REGISTRY_PATH = Path(__file__).resolve().parent.parent / "model-registry.json"
FREE_CATALOG_PATH = Path(__file__).resolve().parent.parent / "data" / "free-catalog.json"

# Status de id que reprova na porta (E5-M2): stampado por
# `bin/audit-registry-ids.sh --stamp` no model-registry.json.
DEAD_ID_STATUSES = ("FANTASMA", "NAO-ENCONTRADO", "NAO-VERIFICADO")

# E5-M3: defaults só com id que sobreviveu ao audit (id_status stampado).
# cheap NÃO tem default aqui — é rota free e resolve pelo catálogo carimbado
# (data/free-catalog.json), que reprova loud na ausência em vez de servir id
# podre (classe do incidente E5).
_DEFAULT_TIERS = {
    "mid": "deepseek-v4-pro",
    "expensive": "claude-sonnet-5",
    "vision": "gemini-3.6-flash",
}
_TIER_FALLBACKS = {
    "mid": "deepseek-v4-flash-openrouter",
    "expensive": "deepseek-v4-pro",
    "vision": None,
}


def _load_yaml(text):
    """Minimal YAML parser, used when PyYAML is not installed.

    It must agree with PyYAML on the mode files: the loader is the single
    reader of a mode, and two readers that disagree are the defect that broke
    the inline-comment ref (incident 2026-11-12-model-ref-com-comentario-inline).
    This parser handles the subset the mode files use: nested mappings, lists
    of mappings, plain scalars, quoted strings, folded blocks ('>') and inline
    comments.
    """
    raw_lines = text.split("\n")
    entries = []  # (indent, content) for every meaningful line
    for raw in raw_lines:
        if not raw.strip() or raw.strip().startswith("#"):
            continue
        stripped = raw.lstrip()
        entries.append((len(raw) - len(stripped), stripped))
    pos = 0

    def parse_node(indent):
        """Parse the block that starts at the current line, if it is deeper."""
        nonlocal pos
        if pos >= len(entries):
            return None
        cur_indent, content = entries[pos]
        if cur_indent < indent:
            return None
        if content.startswith("- "):
            return parse_list(cur_indent)
        return parse_map(cur_indent)

    def parse_map(indent):
        nonlocal pos
        out = {}
        while pos < len(entries):
            cur_indent, content = entries[pos]
            if cur_indent != indent or content.startswith("- "):
                break
            if ":" not in content:
                pos += 1
                continue
            key, val = _split_keyval(content)
            pos += 1
            if val.startswith(">") or val.startswith("|"):
                out[key] = parse_block_scalar(val, indent)
            elif val == "":
                nested = parse_node(indent + 1)
                out[key] = nested if nested is not None else ""
            else:
                out[key] = _parse_val(val)
        return out

    def parse_list(indent):
        nonlocal pos
        out = []
        while pos < len(entries):
            cur_indent, content = entries[pos]
            if cur_indent != indent or not content.startswith("- "):
                break
            item_text = _strip_inline_comment(content[2:].strip())
            pos += 1
            if ":" in item_text and not item_text.startswith(("'", '"')):
                key, val = _split_keyval(item_text)
                entry = {}
                if val.startswith(">") or val.startswith("|"):
                    entry[key] = parse_block_scalar(val, indent)
                elif val == "":
                    nested = parse_node(indent + 3)
                    entry[key] = nested if nested is not None else ""
                else:
                    entry[key] = _parse_val(val)
                # The remaining keys of this list item sit deeper than the dash.
                while pos < len(entries):
                    next_indent, next_content = entries[pos]
                    if next_indent <= indent or next_content.startswith("- "):
                        break
                    if ":" not in next_content:
                        pos += 1
                        continue
                    k2, v2 = _split_keyval(next_content)
                    pos += 1
                    if v2.startswith(">") or v2.startswith("|"):
                        entry[k2] = parse_block_scalar(v2, next_indent)
                    elif v2 == "":
                        nested = parse_node(next_indent + 1)
                        entry[k2] = nested if nested is not None else ""
                    else:
                        entry[k2] = _parse_val(v2)
                out.append(entry)
            else:
                out.append(_parse_val(item_text))
        return out

    def parse_block_scalar(marker, indent):
        """Collect the folded ('>') or literal ('|') lines under a key.

        YAML folds a line break into a space only between two lines at the
        block's own indentation. A more indented line keeps its break (and its
        extra spaces), and the line after it starts on a new line too — a shell
        command folded into one line is a different command.
        """
        nonlocal pos
        text = ""
        base = None
        prev_indent = None
        while pos < len(entries):
            cur_indent, content = entries[pos]
            if cur_indent <= indent:
                break
            if base is None:
                base = cur_indent
                text = content
            elif marker.startswith("|"):
                text += "\n" + " " * (cur_indent - base) + content
            elif prev_indent > base or cur_indent > base:
                text += "\n" + " " * max(0, cur_indent - base) + content
            else:
                text += " " + content
            prev_indent = cur_indent
            pos += 1
        return text + "\n" if text else ""

    if not entries:
        return {}
    return parse_node(entries[0][0]) or {}


def _strip_inline_comment(val):
    """Drop a trailing YAML comment from a scalar value.

    YAML only starts a comment at a '#' that follows a space, so 'tier:cheap' keeps
    its value and 'tier:cheap   # the cheap tier' becomes 'tier:cheap'. Without this,
    a commented ref reaches the tier resolver and resolves to no model at all.
    """
    out = []
    quote = None
    for i, ch in enumerate(val):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in ('"', "'"):
            quote = ch
            out.append(ch)
            continue
        if ch == "#" and (i == 0 or val[i - 1] in (" ", "\t")):
            break
        out.append(ch)
    return "".join(out).strip()


def _split_keyval(line):
    colon_idx = line.index(":")
    key = line[:colon_idx].strip()
    val = _strip_inline_comment(line[colon_idx + 1:].strip())
    return key, val


def _unquote(val):
    """Drop the quotes of a quoted scalar, keeping what is inside them."""
    if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
        inner = val[1:-1]
        if val[0] == '"':
            return inner.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
        return inner.replace("''", "'")
    return val


def _parse_val(val):
    # A quoted scalar stays a string: 'version: "1"' is the string "1", not the
    # number 1. PyYAML keeps that distinction and so must this parser.
    if len(val) >= 2 and val[0] == val[-1] and val[0] in ('"', "'"):
        return _unquote(val)
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
    for stage_index, stage in enumerate(stages):
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
        # rate_limit_s is a promise the runtime now keeps (the throttle between
        # two calls of the same model). A value the runtime cannot honor is a
        # promise nobody keeps: refuse it here, where the author is editing.
        # Checked on EVERY stage, not only the map one - a string, a negative
        # number or a value above the ceiling used to pass validation and then
        # meant nothing at run time.
        rls = stage.get("rate_limit_s")
        if rls is not None:
            if isinstance(rls, bool) or not isinstance(rls, (int, float)):
                print(
                    f"FAIL {p}: rate_limit_s must be a number, got "
                    f"{type(rls).__name__}: {rls!r}",
                    file=sys.stderr,
                )
                sys.exit(2)
            if rls < 0:
                print(
                    f"FAIL {p}: rate_limit_s must be >= 0, got {rls}",
                    file=sys.stderr,
                )
                sys.exit(2)
            if rls > RATE_LIMIT_MAX_S:
                print(
                    f"FAIL {p}: rate_limit_s must be <= {RATE_LIMIT_MAX_S}, got {rls}",
                    file=sys.stderr,
                )
                sys.exit(2)
        oracle = stage.get("oracle")
        if oracle is not None:
            if not (isinstance(oracle, bool) and oracle is True) and not (isinstance(oracle, str) and oracle):
                print(f"FAIL {p}: oracle must be bool true or non-empty string, got {type(oracle).__name__}: {oracle}", file=sys.stderr)
                sys.exit(2)

        # A stage is either a model call or a mechanical command, never both.
        # When both were declared the runtime called the model and dropped the
        # command without a word, so the mode did something the author did not
        # ask for. Refuse it here, where the author is still editing.
        if stage.get("model_ref") and stage.get("command"):
            print(
                f"FAIL {p}: a stage cannot have both model_ref and command "
                f"(role={role!r}): pick one",
                file=sys.stderr,
            )
            sys.exit(2)

        # input: prev_stage — the stage reads the work of the stages before it.
        # The first stage has none, so declaring it there is a dead promise:
        # refuse the file where the author is still editing.
        stage_input = stage.get("input")
        if stage_input is not None and not isinstance(stage_input, str):
            print(
                f"FAIL {p}: input must be a string, got {type(stage_input).__name__}",
                file=sys.stderr,
            )
            sys.exit(2)
        if stage_input == "prev_stage" and stage_index == 0:
            print(
                f"FAIL {p}: the first stage cannot declare 'input: prev_stage' "
                f"(role={role!r}): there is no previous stage to read",
                file=sys.stderr,
            )
            sys.exit(2)

        # prompt_template is a promise the runtime now keeps (the file is
        # read and handed to the model as the stage's prompt). The loader
        # does not know the user's workdir, so it cannot demand the file
        # exists; it only refuses a value the runtime could not honor — an
        # empty or non-string name.
        if "prompt_template" in stage:
            prompt_template = stage["prompt_template"]
            if not isinstance(prompt_template, str) or not prompt_template.strip():
                print(
                    f"FAIL {p}: prompt_template must be a non-empty string, got "
                    f"{type(prompt_template).__name__}: {prompt_template!r}",
                    file=sys.stderr,
                )
                sys.exit(2)

        # json_schema is a promise the runtime now keeps (the file is
        # read and handed to the model as the shape of the answer). The
        # loader does not know the user's workdir, so it cannot demand
        # the file exists; it only refuses a value the runtime could not
        # honor — an empty or non-string name. It does not validate the
        # model's answer against the schema.
        if "json_schema" in stage:
            json_schema = stage["json_schema"]
            if not isinstance(json_schema, str) or not json_schema.strip():
                print(
                    f"FAIL {p}: json_schema must be a non-empty string, got "
                    f"{type(json_schema).__name__}: {json_schema!r}",
                    file=sys.stderr,
                )
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

    # (6) binding tuned/: model_ref fantasma reprova antes de qualquer run
    # (S11 / E2-D2 — a proveniência mora no registry; a lint recusa fantasma)
    tuned_refs = sorted({str(s.get("model_ref", "")) for s in _find_stages(data)
                         if str(s.get("model_ref", "")).startswith("tuned/")})
    if tuned_refs:
        reg_file = root / "model-registry.json"
        if not reg_file.exists():
            failures.append(
                f"model_ref {tuned_refs[0]} exige model-registry.json e ele não "
                f"existe em {reg_file} — fantasma sem registry reprova mais alto ainda")
        else:
            try:
                known = {str(m.get("id", "")) for m in
                         json.loads(reg_file.read_text(encoding="utf-8")).get("models", [])}
            except (json.JSONDecodeError, OSError) as e:
                known = None
                failures.append(f"model-registry.json ilegível ({e}) — lint não pode "
                                f"validar {tuned_refs[0]}: fail loud, não passaquieto")
            if known is not None:
                for ref in tuned_refs:
                    if ref not in known:
                        failures.append(
                            f"model_ref '{ref}' não existe no model-registry.json "
                            f"(binding tuned/ fantasma — E2-D2: proveniência no registry)")

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


def _load_free_catalog(catalog_path=None):
    """Catálogo free carimbado (E5-D3): arquivo LOCAL, nunca HTTP no caminho
    do dispatch. Ausente, ilegível ou com kind errado = None (reprovado loud
    pelo chamador — degradação silenciosa é a doença que o E5 fecha)."""
    cat_path = Path(catalog_path) if catalog_path else FREE_CATALOG_PATH
    if not cat_path.exists():
        return None
    try:
        data = json.loads(cat_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    if not isinstance(data, dict) or data.get("kind") != "free-catalog/1":
        return None
    return data


def _catalog_order(models):
    """Ordem de fallback: keyless primeiro (perna zero-key da promessa, R1);
    dentro do grupo, contexto maior primeiro, empate por ref lexicográfico.
    Função pura do conteúdo do arquivo — resolve-tier continua
    byte-determinístico. Limit-aware honesto (R3): RPM/RPD são limites
    PUBLICADOS (null no bootstrap), não saldo consumido — nada aqui conta
    quota; o desvio de provider estourado vem das observações reais
    (usage-hub) consumidas pela cadeia RF-08."""
    return sorted(
        (m for m in models if isinstance(m, dict) and m.get("ref")),
        key=lambda m: (
            0 if m.get("keyless") else 1,
            -(m.get("context_length") or 0),
            str(m.get("ref", "")),
        ),
    )


def _resolve_tier_cheap(registry_path=None, catalog_path=None):
    """Imprime a lista fallback de tier:cheap, um ref por linha, em ordem.

    Gate na porta (E5-M2): ref com id_status morto stampado no registry é
    pulado com WARN alto — catálogo desatualizado nunca entrega fantasma.
    Catálogo ausente/ilegível = exit 2 LOUD; zero ref vivo = exit 2 LOUD.
    """
    cat = _load_free_catalog(catalog_path)
    if cat is None:
        print(
            "ERROR: rota free sem catálogo carimbado legível "
            "(data/free-catalog.json, kind free-catalog/1). Rode "
            "bin/sync-free-catalog.sh. Recusando cair nos defaults que já "
            "serviram id morto (incidente E5)",
            file=sys.stderr,
        )
        sys.exit(2)

    statuses = {}
    for m in _load_registry(registry_path) or []:
        statuses[str(m.get("id", ""))] = str(m.get("id_status", "") or "")

    printed = 0
    for m in _catalog_order(cat.get("models", [])):
        ref = str(m.get("ref", ""))
        st = statuses.get(ref, "")
        if any(d in st for d in DEAD_ID_STATUSES):
            print(
                f"WARN: catálogo free cita '{ref}' com id_status '{st}' no "
                f"registry — pulado na porta (E5-M2)",
                file=sys.stderr,
            )
            continue
        print(ref)
        printed += 1

    if printed == 0:
        print(
            "ERROR: catálogo free não deixou nenhum ref vivo após o gate do "
            "registry (E5-M2) — sync precisa rodar antes de despachar",
            file=sys.stderr,
        )
        sys.exit(2)


def resolve_tier(tier, registry_path=None, catalog_path=None):
    tier = tier.removeprefix("tier:")

    # E5-M4: tier:cheap é a rota FREE e resolve pela lista ordenada do
    # catálogo local carimbado — nunca pelos defaults hardcodados (o default
    # antigo, deepseek-v4-flash-free, tinha hint morto e continuou sendo
    # servido como primeira opção: a classe exata do incidente E5).
    if tier == "cheap":
        _resolve_tier_cheap(registry_path, catalog_path)
        sys.exit(0)

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
                if m.get("id") == "deepseek-v4-pro":
                    print(m["id"])
                    return
            for m in models:
                if m.get("id") == "deepseek-v4-flash-openrouter":
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
                if m.get("id") == "claude-sonnet-5":
                    print(m["id"])
                    return
            for m in models:
                bf = m.get("best_for") or []
                if "melhor qualidade" in bf:
                    print(m["id"])
                    return

        elif tier == "vision":
            for m in models:
                if m.get("id") == "gemini-3.6-flash":
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


def _read_mode_yaml(path):
    """Load a mode file. Missing file exits 3; unreadable file exits 3.

    This is the reader only: it does not resolve any named file. The
    conference that keeps prompt_template and json_schema promises calls
    the runtime libs; this function just says what the YAML declared.
    """
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
    return data


def promises(path):
    """Print the prompt_template and json_schema names each stage declares.

    JSON on stdout, one object, no file lookup. A stage that does not
    name a prompt or a schema is omitted. The conference resolves.
    """
    data = _read_mode_yaml(path)
    out = []
    if isinstance(data, dict):
        for index, stage in enumerate(_find_stages(data)):
            if not isinstance(stage, dict):
                continue
            role = stage.get("role", "")
            if not isinstance(role, str):
                role = str(role) if role is not None else ""
            if "prompt_template" in stage:
                name = stage["prompt_template"]
                if isinstance(name, str) and name.strip():
                    out.append({
                        "stage": index,
                        "role": role,
                        "type": "prompt_template",
                        "name": name,
                    })
            if "json_schema" in stage:
                name = stage["json_schema"]
                if isinstance(name, str) and name.strip():
                    out.append({
                        "stage": index,
                        "role": role,
                        "type": "json_schema",
                        "name": name,
                    })
    json.dump({"promises": out}, sys.stdout, ensure_ascii=False)
    print()


def main():
    if len(sys.argv) < 2:
        print("Usage:", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py validate <path.yaml>", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py lint <path.yaml> [--root DIR] [--workdir DIR] [--strict]", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py resolve-tier <tier> [--registry path.json]", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py dump <path.yaml>", file=sys.stderr)
        print("  lib-oracfit-mode-loader.py promises <path.yaml>", file=sys.stderr)
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
            print("Usage: resolve-tier <tier> [--registry path.json] [--catalog path.json]", file=sys.stderr)
            sys.exit(2)
        tier = sys.argv[2]
        registry_path = None
        catalog_path = None
        extra = sys.argv[3:]
        i = 0
        while i < len(extra):
            if extra[i] == "--registry" and i + 1 < len(extra):
                registry_path = extra[i + 1]; i += 2
            elif extra[i] == "--catalog" and i + 1 < len(extra):
                catalog_path = extra[i + 1]; i += 2
            else:
                i += 1
        resolve_tier(tier, registry_path, catalog_path)

    elif cmd == "dump":
        if len(sys.argv) < 3:
            print("Usage: dump <path.yaml>", file=sys.stderr)
            sys.exit(2)
        dump(sys.argv[2])

    elif cmd == "promises":
        if len(sys.argv) < 3:
            print("Usage: promises <path.yaml>", file=sys.stderr)
            sys.exit(2)
        promises(sys.argv[2])

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()