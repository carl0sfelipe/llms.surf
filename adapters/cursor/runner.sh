#!/bin/bash
# runner.sh — implementação cursor (cursor-agent) do contrato core/runner-contract.md
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
#
# Traduz para: cursor-agent -p --force --model <hint> [--resume ID] "$(cat <spec_file>)"
# Sintaxe verificada em adapters/cursor/DISCOVERY.md.
#
# Exit codes (RNF-04): 0=ok, 1=erro, 2=rate-limit, 3=erro de uso, 4=quota

set -uo pipefail

MODEL_ID="${1:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
SPEC_FILE="${2:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
shift 2

# ADAPTER_DIR antes do cd: BASH_SOURCE relativo quebraria depois de
# mudar para o workdir (stream-events.py mora ao lado deste runner).
ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

# Incidente 2026-08-12-runner-herda-cwd-do-lancador: o CLI edita arquivos
# relativos ao CWD do LANÇADOR — com workdir apontando pra outro lugar, o
# modelo despachado edita o repo errado. O workdir do run é o contrato:
# cd nele antes de subir o modelo. Spec canonicalizada ANTES do cd.
SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
if [ -n "${ORACFIT_WORKDIR:-}" ]; then
  cd "$ORACFIT_WORKDIR" || { echo "runner.sh (cursor): workdir inexistente: $ORACFIT_WORKDIR" >&2; exit 3; }
fi

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
      echo "runner.sh (cursor): flag desconhecida: $1" >&2
      exit 3
      ;;
  esac
done

if [ "$FORK" = "1" ]; then
  echo "runner.sh (cursor): cursor-agent não suporta --fork (capabilities.env FORK=0)" >&2
  exit 3
fi

if [ ! -f "$SPEC_FILE" ]; then
  echo "runner.sh (cursor): spec_file não encontrado: $SPEC_FILE" >&2
  exit 1
fi

MODEL_REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"

RESOLVED=$(MODEL_ID="$MODEL_ID" REGISTRY="$MODEL_REGISTRY" python3 -c '
import json, os, sys
mid = os.environ["MODEL_ID"]
try:
    models = json.load(open(os.environ["REGISTRY"]))["models"]
except Exception as e:
    print("registry ilegível: %s" % e, file=sys.stderr); sys.exit(3)
for m in models:
    hint = m.get("cli_hints", {}).get("cursor")
    if mid in (m["id"], hint) and hint:
        print(hint); sys.exit(0)
    if mid == m["id"]:
        print("modelo %s não tem cli_hint para cursor (ver model-registry.json)" % mid, file=sys.stderr); sys.exit(3)
print("modelo %s ausente do model-registry.json" % mid, file=sys.stderr); sys.exit(3)
') || exit 3

# Resolver binário
if [ -n "${CURSOR_AGENT_BIN:-}" ]; then
  BIN="$CURSOR_AGENT_BIN"
elif command -v cursor-agent >/dev/null 2>&1; then
  BIN="cursor-agent"
elif command -v agent >/dev/null 2>&1; then
  BIN="agent"
else
  echo "runner.sh (cursor): cursor-agent não encontrado no PATH — rode cursor agent / instale o CLI" >&2
  exit 3
fi

# Auth gate cedo (mensagem clara; evita hang opaco)
if [ -z "${CURSOR_API_KEY:-}${CURSOR_AUTH_TOKEN:-}" ]; then
  STATUS_OUT=$("$BIN" ${CURSOR_AGENT_SUBCOMMAND:+$CURSOR_AGENT_SUBCOMMAND} status 2>&1 || true)
  if echo "$STATUS_OUT" | grep -qiE 'not logged in|authentication required'; then
    echo "runner.sh (cursor): não autenticado — rode \`cursor-agent login\` ou exporte CURSOR_API_KEY" >&2
    exit 3
  fi
fi

ARGS=()
[ -n "${CURSOR_AGENT_SUBCOMMAND:-}" ] && ARGS+=(agent)
ARGS+=(-p --force --model "$RESOLVED")
[ -n "$SESSION_ID" ] && ARGS+=(--resume "$SESSION_ID")
[ "${DISPATCH_RUNNER_FORMAT_JSON:-1}" = "1" ] && ARGS+=(--output-format stream-json)
[ -n "${ORACFIT_WORKDIR:-}" ] && ARGS+=(--workspace "$ORACFIT_WORKDIR")
[ -n "${CURSOR_WORKDIR:-}" ] && ARGS+=(--workspace "$CURSOR_WORKDIR")

# stdout ao vivo (sem OUTPUT=$): cada linha do cursor-agent passa pelo
# parser e sai na hora. PIPESTATUS[0] é o exit do cursor-agent — o do
# python/tee não pode mascarar falha (contrato: 0/1/2/3/4).
OUT_F=$(mktemp)
_cursor_cleanup() { rm -f "$OUT_F"; }
trap _cursor_cleanup EXIT

"$BIN" "${ARGS[@]}" "$(cat "$SPEC_FILE")" 2>&1 \
  | PYTHONUNBUFFERED=1 python3 -u "$ADAPTER_DIR/stream-events.py" \
  | tee "$OUT_F"
EXIT_CODE=${PIPESTATUS[0]}

# system/init traz apiKeySource, que casa com api.?key e fazia exit 3
# em run bem-sucedido. Auth/429/quota só em linha NÃO-JSON e no campo
# result de {"type":"result","is_error":true}.
SIGNAL=$(python3 -c '
import json, re, sys

auth = re.compile(r"authentication required|not logged in|api.?key", re.I)
rate = re.compile(r"429|rate.?limit", re.I)
quota = re.compile(r"quota|insufficient|out of credit|usage.?limit", re.I)
auth_hit = rate_hit = quota_hit = False

def note(text):
    global auth_hit, rate_hit, quota_hit
    if not text:
        return
    if auth.search(text):
        auth_hit = True
    if rate.search(text):
        rate_hit = True
    if quota.search(text):
        quota_hit = True

with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        raw = line.rstrip("\n")
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError:
            note(raw)
            continue
        if not isinstance(obj, dict):
            continue
        if obj.get("type") == "result" and obj.get("is_error") is True:
            result = obj.get("result")
            if isinstance(result, str):
                note(result)
            elif result is not None:
                note(json.dumps(result))

if auth_hit:
    print(3)
elif rate_hit:
    print(2)
elif quota_hit:
    print(4)
else:
    print(0)
' "$OUT_F")

if [ "$SIGNAL" = "3" ]; then
  echo "runner.sh (cursor): auth falhou — cursor-agent login ou CURSOR_API_KEY" >&2
  exit 3
fi
if [ "$SIGNAL" = "2" ]; then
  exit 2
fi
if [ "$SIGNAL" = "4" ]; then
  exit 4
fi

[ "$EXIT_CODE" -ne 0 ] && exit 1
exit 0
