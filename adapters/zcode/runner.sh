#!/bin/bash
# runner.sh — implementação zcode do contrato core/runner-contract.md
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
#
# Traduz para: zcode --prompt "$(cat spec)" --mode yolo [--resume ID] [--json] [--cwd DIR]
# Modelo via ~/.zcode/cli/config.json (cli_hints.zcode = "providerId/modelId").
# Sintaxe: adapters/zcode/DISCOVERY.md (2026-08-04).
#
# Exit codes (RNF-04): 0=ok, 1=erro, 2=rate-limit, 3=erro de uso, 4=quota

set -uo pipefail

MODEL_ID="${1:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
SPEC_FILE="${2:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
shift 2

SESSION_ID=""
FORK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      SESSION_ID="${2:?--session requer ID}"
      shift 2
      ;;
    --fork)
      FORK=1
      shift
      ;;
    *)
      echo "runner.sh (zcode): flag desconhecida: $1" >&2
      exit 3
      ;;
  esac
done

if [ "$FORK" = "1" ]; then
  echo "runner.sh (zcode): zcode não suporta --fork no CLI (só /fork na TUI; FORK=0)" >&2
  exit 3
fi

if [ ! -f "$SPEC_FILE" ]; then
  echo "runner.sh (zcode): spec_file não encontrado: $SPEC_FILE" >&2
  exit 1
fi

ZCODE_BIN="${ZCODE_BIN:-zcode}"
if ! command -v "$ZCODE_BIN" >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin)
      ZCODE_APP="/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs"
      if [ -f "$ZCODE_APP" ]; then
        mkdir -p "$HOME/.local/bin"
        ln -sfn "$ZCODE_APP" "$HOME/.local/bin/zcode"
        ZCODE_BIN="$HOME/.local/bin/zcode"
      else
        echo "runner.sh (zcode): CLI zcode não encontrada (instale ZCode.app)" >&2
        exit 3
      fi
      ;;
    Linux)
      if [ -x "$HOME/.local/bin/zcode" ]; then
        ZCODE_BIN="$HOME/.local/bin/zcode"
      else
        echo "runner.sh (zcode): CLI zcode não encontrada (Linux: instale o wrapper/AppImage em ~/.local/bin/zcode ou exporte ZCODE_BIN)" >&2
        exit 3
      fi
      ;;
    *)
      echo "runner.sh (zcode): CLI zcode não encontrada e SO não suportado: $(uname -s)" >&2
      exit 3
      ;;
  esac
fi

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
MODEL_REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"

RESOLVED=$(MODEL_ID="$MODEL_ID" REGISTRY="$MODEL_REGISTRY" python3 -c '
import json, os, sys
mid = os.environ["MODEL_ID"]
try:
    models = json.load(open(os.environ["REGISTRY"]))["models"]
except Exception as e:
    print("registry ilegível: %s" % e, file=sys.stderr); sys.exit(3)
for m in models:
    hint = m.get("cli_hints", {}).get("zcode")
    if mid in (m["id"], hint) and hint:
        print(hint); sys.exit(0)
    if mid == m["id"]:
        print("modelo %s não tem cli_hint para zcode (ver model-registry.json)" % mid, file=sys.stderr); sys.exit(3)
print("modelo %s ausente do model-registry.json" % mid, file=sys.stderr); sys.exit(3)
') || exit 3

# D-INC3: never leave the owner's live config dirty.
# overlay = write only under <workdir>/.dispatch/zcode-home (HOME relocated).
# restore = write-then-restore under flock (default: works whether HOME relocates).
# Measurement of the real binary is adapters/zcode/measure-home-relocation.sh
# (owner machine). This cloud does not invent that result.
REAL_HOME="$HOME"
OWNER_CONFIG="${ZCODE_CLI_CONFIG:-$REAL_HOME/.zcode/cli/config.json}"
STRATEGY="${ZCODE_CONFIG_STRATEGY:-restore}"
WORKDIR="${ORACFIT_WORKDIR:-${ZCODE_WORKDIR:-$PWD}}"
ZCODE_CFG_BACKUP=""
ZCODE_CFG_HAD=0
EFFECTIVE_HOME="$REAL_HOME"

case "$STRATEGY" in
  overlay|restore) ;;
  *)
    echo "runner.sh (zcode): ZCODE_CONFIG_STRATEGY must be overlay|restore (got: $STRATEGY)" >&2
    exit 3
    ;;
esac

zcode_write_model_config() {
  # Reads SOURCE_PATH (may be absent); writes DEST_PATH only.
  MODEL_HINT="$RESOLVED" SOURCE_PATH="$1" DEST_PATH="$2" python3 -c '
import json, os, pathlib
hint = os.environ["MODEL_HINT"]
src = pathlib.Path(os.environ["SOURCE_PATH"])
dest = pathlib.Path(os.environ["DEST_PATH"])
dest.parent.mkdir(parents=True, exist_ok=True)
cfg = {}
if src.is_file():
    try:
        cfg = json.loads(src.read_text())
    except Exception:
        cfg = {}
if not isinstance(cfg, dict):
    cfg = {}
# model.main deve ser string provider/model (DISCOVERY)
if isinstance(cfg.get("model"), str):
    cfg["model"] = hint
else:
    model = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
    model["main"] = hint
    # remove chaves inválidas no bloco strict {main,lite}
    cfg["model"] = {k: model[k] for k in ("main", "lite") if k in model and model[k]}
# Garante bloco provider mínimo se ausente (kind+baseURL do hint conhecido z.ai)
prov_id, _, _model = hint.partition("/")
provider = cfg.get("provider") if isinstance(cfg.get("provider"), dict) else {}
if prov_id and prov_id not in provider:
    if prov_id.startswith("builtin:zai"):
        provider[prov_id] = {
            "kind": "anthropic",
            "options": {"baseURL": "https://api.z.ai/api/anthropic"},
        }
    elif prov_id.startswith("custom:llamacpp"):
        provider[prov_id] = {
            "kind": "openai-compatible",
            "options": {"baseURL": "http://127.0.0.1:8082/v1", "apiKey": "local"},
        }
    else:
        # provider desconhecido: não inventa baseURL — só registra kind openai-compatible
        # (runner falhará com mensagem do zcode se faltar apiKey/baseURL)
        provider[prov_id] = {"kind": "openai-compatible", "options": {}}
    cfg["provider"] = provider
elif prov_id and isinstance(provider.get(prov_id), dict):
    # preserva apiKey/options existentes; só garante kind
    entry = provider[prov_id]
    entry.setdefault("kind", "anthropic" if "zai" in prov_id else "openai-compatible")
    entry.setdefault("options", {})
    if "zai" in prov_id:
        entry["options"].setdefault("baseURL", "https://api.z.ai/api/anthropic")
    provider[prov_id] = entry
    cfg["provider"] = provider
dest.write_text(json.dumps(cfg, indent=2) + "\n")
'
}

zcode_overlay_home() {
  # Symlink ~/.zcode/* into the overlay; cli/config.json is a real file.
  local owner_zcode="$REAL_HOME/.zcode"
  local overlay_zcode="$EFFECTIVE_HOME/.zcode"
  local item base
  rm -rf "$EFFECTIVE_HOME"
  mkdir -p "$overlay_zcode/cli"
  if [ -d "$owner_zcode" ]; then
    for item in "$owner_zcode"/* "$owner_zcode"/.[!.]*; do
      [ -e "$item" ] || continue
      base="$(basename "$item")"
      [ "$base" = "cli" ] && continue
      ln -sfn "$item" "$overlay_zcode/$base"
    done
    if [ -d "$owner_zcode/cli" ]; then
      for item in "$owner_zcode/cli"/* "$owner_zcode/cli"/.[!.]*; do
        [ -e "$item" ] || continue
        base="$(basename "$item")"
        [ "$base" = "config.json" ] && continue
        ln -sfn "$item" "$overlay_zcode/cli/$base"
      done
    fi
  fi
}

zcode_restore_owner_config() {
  if [ "${STRATEGY:-}" != "restore" ]; then
    return 0
  fi
  if [ "$ZCODE_CFG_HAD" = "1" ] && [ -n "$ZCODE_CFG_BACKUP" ] && [ -f "$ZCODE_CFG_BACKUP" ]; then
    cp -f "$ZCODE_CFG_BACKUP" "$OWNER_CONFIG"
  elif [ "$ZCODE_CFG_HAD" = "0" ]; then
    rm -f "$OWNER_CONFIG"
  fi
  if [ -n "$ZCODE_CFG_BACKUP" ]; then
    rm -f "$ZCODE_CFG_BACKUP"
    ZCODE_CFG_BACKUP=""
  fi
}

if [ "$STRATEGY" = "overlay" ]; then
  EFFECTIVE_HOME="$WORKDIR/.dispatch/zcode-home"
  zcode_overlay_home
  ZCODE_CLI_CONFIG="$EFFECTIVE_HOME/.zcode/cli/config.json"
  zcode_write_model_config "$OWNER_CONFIG" "$ZCODE_CLI_CONFIG" || {
    echo "runner.sh (zcode): falha ao escrever overlay $ZCODE_CLI_CONFIG" >&2
    exit 1
  }
else
  if ! command -v flock >/dev/null 2>&1; then
    echo "runner.sh (zcode): restore strategy requires flock(1)" >&2
    exit 3
  fi
  mkdir -p "$(dirname "$OWNER_CONFIG")"
  exec 9>>"${OWNER_CONFIG}.lock"
  flock 9
  if [ -f "$OWNER_CONFIG" ]; then
    ZCODE_CFG_HAD=1
    ZCODE_CFG_BACKUP="$(mktemp "${TMPDIR:-/tmp}/zcode-cli-config.XXXXXX")"
    cp -f "$OWNER_CONFIG" "$ZCODE_CFG_BACKUP"
  else
    ZCODE_CFG_HAD=0
  fi
  trap zcode_restore_owner_config EXIT INT TERM
  echo "this dispatch temporarily sets your zcode model to $RESOLVED; restored on exit" >&2
  ZCODE_CLI_CONFIG="$OWNER_CONFIG"
  zcode_write_model_config "$OWNER_CONFIG" "$ZCODE_CLI_CONFIG" || {
    echo "runner.sh (zcode): falha ao escrever $ZCODE_CLI_CONFIG" >&2
    exit 1
  }
fi

# Preflight auth: sem apiKey o zcode só imprime "Turn execution failed" (sem Cause).
PROV_ID="${RESOLVED%%/*}"
HAS_KEY=$(CONFIG_PATH="$ZCODE_CLI_CONFIG" PROV_ID="$PROV_ID" python3 -c '
import json, os
path = os.environ["CONFIG_PATH"]
prov = os.environ["PROV_ID"]
try:
    cfg = json.load(open(path))
except Exception:
    print("0"); raise SystemExit
entry = (cfg.get("provider") or {}).get(prov) or {}
opts = entry.get("options") or {}
key = (opts.get("apiKey") or os.environ.get("ZCODE_API_KEY") or "").strip()
# enc:v1: do GUI não serve no CLI
print("0" if (not key or key.startswith("enc:v1:")) else "1")
')
if [ "$HAS_KEY" != "1" ]; then
  echo "runner.sh (zcode): sem apiKey para $PROV_ID — rode \`zcode login\` ou defina provider.$PROV_ID.options.apiKey em $ZCODE_CLI_CONFIG (ou ZCODE_API_KEY)" >&2
  exit 3
fi

MODE="${ZCODE_MODE:-${DISPATCH_ZCODE_MODE:-yolo}}"

ARGS=(--prompt "$(cat "$SPEC_FILE")" --mode "$MODE" --cwd "$WORKDIR")
[ -n "$SESSION_ID" ] && ARGS+=(--resume "$SESSION_ID")
[ "${DISPATCH_RUNNER_FORMAT_JSON:-1}" = "1" ] && ARGS+=(--json)

OUTPUT=$(HOME="$EFFECTIVE_HOME" "$ZCODE_BIN" "${ARGS[@]}" 2>&1)
EXIT_CODE=$?

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qiE 'Model config is missing|missing an API key|token expired|Authentication|zcode login'; then
  echo "runner.sh (zcode): auth/config — rode \`zcode login\` ou coloque apiKey em $ZCODE_CLI_CONFIG provider.*.options" >&2
  exit 3
fi
if echo "$OUTPUT" | grep -qiE '429|rate.?limit'; then
  exit 2
fi
if echo "$OUTPUT" | grep -qiE 'quota|insufficient|out of credit|plan.?limit'; then
  exit 4
fi

[ $EXIT_CODE -ne 0 ] && exit 1
exit 0
