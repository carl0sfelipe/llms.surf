#!/bin/bash
# runner.sh — implementação hermes do contrato core/runner-contract.md
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
#
# Traduz para: hermes -z "$(cat <spec_file>)" -m <modelo> [--provider P] [--resume ID]
# Sintaxe verificada em adapters/hermes/DISCOVERY.md (`hermes --help`):
#   -z/--oneshot PROMPT  → "send a single prompt and print ONLY the final response text"
#   -m MODEL             → modelo desta invocação
#   --provider PROVIDER  → override de provider (aplica-se a -z/--oneshot)
#   --resume/-r SESSION  → retoma sessão por ID ou título
#
# Exit codes (RNF-04): 0=ok, 1=erro, 2=rate-limit, 3=erro de uso, 4=quota exausta

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
  cd "$ORACFIT_WORKDIR" || { echo "runner.sh (hermes): workdir inexistente: $ORACFIT_WORKDIR" >&2; exit 3; }
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
      echo "runner.sh (hermes): flag desconhecida: $1" >&2
      exit 3
      ;;
  esac
done

# `hermes --help` (DISCOVERY.md) não expõe equivalente a --fork. Capacidade
# declarada FORK=0 em capabilities.env. Nunca simular fork com --resume:
# seção 4.5 do PRD proíbe degradar em silêncio.
if [ "$FORK" = "1" ]; then
  echo "runner.sh (hermes): hermes não suporta --fork (ver adapters/hermes/DISCOVERY.md; capabilities.env FORK=0)" >&2
  exit 3
fi

if [ ! -f "$SPEC_FILE" ]; then
  echo "runner.sh (hermes): spec_file não encontrado: $SPEC_FILE" >&2
  exit 1
fi

HERMES_BIN="${HERMES_BIN:-hermes}"

# Resolve <model_id> via cli_hints.hermes do registry (core/runner-contract.md).
# Formato do hint: "<provider> <modelo>" ou só "<modelo>".
MODEL_REGISTRY="${MODEL_REGISTRY:-$(cd "$(dirname "$0")/../.." && pwd)/model-registry.json}"
RESOLVED=$(MODEL_ID="$MODEL_ID" REGISTRY="$MODEL_REGISTRY" python3 -c '
import json, os, sys
mid = os.environ["MODEL_ID"]
try:
    models = json.load(open(os.environ["REGISTRY"]))["models"]
except Exception as e:
    print("registry ilegível: %s" % e, file=sys.stderr); sys.exit(3)
for m in models:
    hint = m.get("cli_hints", {}).get("hermes")
    if mid in (m["id"], hint) and hint:   # aceita id ou hint já resolvido (idempotente)
        print(hint); sys.exit(0)
    if mid == m["id"]:
        print("modelo %s não tem cli_hint para hermes (ver model-registry.json)" % mid, file=sys.stderr); sys.exit(3)
print("modelo %s ausente do model-registry.json" % mid, file=sys.stderr); sys.exit(3)
') || exit 3

# Hint no formato "provider modelo" vira --provider + -m; hint simples vira só -m.
ARGS=(-z "$(cat "$SPEC_FILE")")
read -r HINT_A HINT_B <<< "$RESOLVED"
if [ -n "${HINT_B:-}" ]; then
  ARGS+=(--provider "$HINT_A" -m "$HINT_B")
else
  ARGS+=(-m "$HINT_A")
fi

[ -n "$SESSION_ID" ] && ARGS+=(--resume "$SESSION_ID")

OUTPUT=$("$HERMES_BIN" "${ARGS[@]}" 2>&1)
EXIT_CODE=$?

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qiE '429|rate.?limit'; then
  exit 2
fi

if echo "$OUTPUT" | grep -qiE 'quota (exceeded|exhausted)|limite (semanal|mensal) (atingido|excedido)'; then
  exit 4
fi

[ $EXIT_CODE -ne 0 ] && exit 1
exit 0
