#!/bin/bash
# runner.sh — implementação prime-agent do contrato core/runner-contract.md
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
#
# Traduz para: prime-agent -p --model "<hint>" [--resume ID | --fork ID] "$(cat spec)"
# Sintaxe verificada em adapters/prime-agent/DISCOVERY.md (`prime-agent --help`).
#
# Exit codes (RNF-04): 0=ok, 1=erro, 2=rate-limit, 3=erro de uso, 4=quota exausta
set -uo pipefail

MODEL_ID="${1:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
SPEC_FILE="${2:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
shift 2

SESSION_ID=""
FORK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --session) SESSION_ID="${2:?--session requer ID}"; shift 2 ;;
    --fork) FORK=1; shift ;;
    *) echo "runner.sh (prime-agent): flag desconhecida: $1" >&2; exit 3 ;;
  esac
done

if [ "$FORK" = "1" ] && [ -z "$SESSION_ID" ]; then
  echo "runner.sh (prime-agent): --fork requer --session ID (ver core/runner-contract.md)" >&2
  exit 3
fi
[ -f "$SPEC_FILE" ] || { echo "runner.sh (prime-agent): spec_file não encontrado: $SPEC_FILE" >&2; exit 1; }

# Incidente 2026-08-12-runner-herda-cwd-do-lancador: workdir do run é contrato.
# prime-agent tem --cwd nativo; usamos a flag E canonicalizamos a spec antes.
SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
CWD_ARGS=()
if [ -n "${ORACFIT_WORKDIR:-}" ]; then
  [ -d "$ORACFIT_WORKDIR" ] || { echo "runner.sh (prime-agent): workdir inexistente: $ORACFIT_WORKDIR" >&2; exit 3; }
  CWD_ARGS=(--cwd "$ORACFIT_WORKDIR")
fi

PRIME_BIN="${PRIME_AGENT_BIN:-prime-agent}"
command -v "$PRIME_BIN" >/dev/null 2>&1 || { echo "runner.sh (prime-agent): binário não encontrado (rode o installer, ver DISCOVERY.md)" >&2; exit 1; }

# Resolve <model_id> via cli_hints do registry (core/runner-contract.md).
# id ausente ou sem hint para prime-agent → exit 3 (nunca inventar model id).
MODEL_REGISTRY="${MODEL_REGISTRY:-$(cd "$(dirname "$0")/../.." && pwd)/model-registry.json}"
RESOLVED=$(MODEL_ID="$MODEL_ID" REGISTRY="$MODEL_REGISTRY" python3 -c '
import json, os, sys
mid = os.environ["MODEL_ID"]
try:
    models = json.load(open(os.environ["REGISTRY"]))["models"]
except Exception as e:
    print("registry ilegível: %s" % e, file=sys.stderr); sys.exit(3)
for m in models:
    hint = m.get("cli_hints", {}).get("prime-agent")
    if mid in (m["id"], hint) and hint:
        print(hint); sys.exit(0)
    if mid == m["id"]:
        print("modelo %s não tem cli_hint para prime-agent (ver model-registry.json e adapters/prime-agent/DISCOVERY.md)" % mid, file=sys.stderr); sys.exit(3)
print("modelo %s ausente do model-registry.json" % mid, file=sys.stderr); sys.exit(3)
') || exit 3

# --model aceita "provider/model" ou model puro conforme `prime-agent model list`.
ARGS=(-p --model "$RESOLVED")
[ ${#CWD_ARGS[@]} -gt 0 ] && ARGS+=("${CWD_ARGS[@]}")
if [ "$FORK" = "1" ]; then
  ARGS+=(--fork "$SESSION_ID")
elif [ -n "$SESSION_ID" ]; then
  ARGS+=(--resume "$SESSION_ID")
fi

ERR_F=$(mktemp)
limpar() { rm -f "$ERR_F"; }
trap limpar EXIT

# `--` antes do positional: spec com frontmatter YAML começa com `---`
# (mesma lição do runner opencode, 2026-08-10).
"$PRIME_BIN" "${ARGS[@]}" -- "$(cat "$SPEC_FILE")" 2> "$ERR_F"
EXIT_CODE=$?

# Classificação de erro de provider (contrato RNF-04)
if grep -qiE 'rate limit|429|too many requests' "$ERR_F"; then
  grep -iE 'rate limit|429|too many requests' "$ERR_F" | head -1 >&2
  echo "runner.sh (prime-agent): RATE LIMIT — exit 2" >&2
  exit 2
fi
if grep -qiE 'insufficient balance|quota exceeded|out of credit|insufficient_quota' "$ERR_F"; then
  grep -iE 'insufficient balance|quota exceeded|out of credit|insufficient_quota' "$ERR_F" | head -1 >&2
  echo "runner.sh (prime-agent): SALDO/QUOTA esgotado — exit 4" >&2
  exit 4
fi
if grep -qiE 'authentication failed|401' "$ERR_F"; then
  grep -iE 'authentication failed|401' "$ERR_F" | head -1 >&2
  echo "runner.sh (prime-agent): sem auth — rode 'prime-agent' interativo e /login (dono)" >&2
  exit 1
fi

[ -s "$ERR_F" ] && cat "$ERR_F" >&2
[ $EXIT_CODE -ne 0 ] && exit 1
exit 0
