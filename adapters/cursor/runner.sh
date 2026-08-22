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
[ "${DISPATCH_RUNNER_FORMAT_JSON:-1}" = "1" ] && ARGS+=(--output-format json)
[ -n "${ORACFIT_WORKDIR:-}" ] && ARGS+=(--workspace "$ORACFIT_WORKDIR")
[ -n "${CURSOR_WORKDIR:-}" ] && ARGS+=(--workspace "$CURSOR_WORKDIR")

OUTPUT=$("$BIN" "${ARGS[@]}" "$(cat "$SPEC_FILE")" 2>&1)
EXIT_CODE=$?

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qiE 'authentication required|not logged in|api.?key'; then
  echo "runner.sh (cursor): auth falhou — cursor-agent login ou CURSOR_API_KEY" >&2
  exit 3
fi
if echo "$OUTPUT" | grep -qiE '429|rate.?limit'; then
  exit 2
fi
if echo "$OUTPUT" | grep -qiE 'quota|insufficient|out of credit|usage.?limit'; then
  exit 4
fi

[ $EXIT_CODE -ne 0 ] && exit 1
exit 0
