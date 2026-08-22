#!/bin/bash
# token-plan.sh — semáforo de token plan semanal (RF-05.2)
# Uso: token-plan.sh status
#      token-plan.sh consume <tokens>
#      token-plan.sh reset
#
# Porta a lógica de specs/free-model-ecosystem.md seção 5.3: plano semanal com
# limite; ao estourar, marca como exausto e o dispatcher troca de tier.
#
# Estado em $TOKEN_PLAN_STATE (default: .dispatch/qwen-token-plan.json).
# Exit codes (RNF-04): 0=GO (tem saldo), 4=quota exausta, 3=erro de uso.

set -uo pipefail

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

STATE_FILE="${TOKEN_PLAN_STATE:-$REPO_ROOT/.dispatch/qwen-token-plan.json}"
LIMIT="${TOKEN_PLAN_LIMIT:-500000}"   # specs/free-model-ecosystem.md:206
ACTION="${1:-status}"

mkdir -p "$(dirname "$STATE_FILE")"

if [ ! -f "$STATE_FILE" ]; then
  printf '{"limit": %s, "used": 0, "reset_day": "Monday"}\n' "$LIMIT" > "$STATE_FILE"
fi

case "$ACTION" in
  status)
    STATE_FILE="$STATE_FILE" python3 -c '
import json, os, sys
s = json.load(open(os.environ["STATE_FILE"]))
used, limit, reset = s["used"], s["limit"], s["reset_day"]
pct = (used / limit * 100) if limit else 0
print("token plan qwen: %d/%d (%.1f%%) — reset: %s" % (used, limit, pct, reset))
sys.exit(4 if used >= limit else 0)
'
    ;;
  consume)
    TOKENS="${2:?Uso: token-plan.sh consume <tokens>}"
    STATE_FILE="$STATE_FILE" TOKENS="$TOKENS" python3 -c '
import json, os, sys
p = os.environ["STATE_FILE"]
s = json.load(open(p))
add = int(os.environ["TOKENS"])
s["used"] += add
json.dump(s, open(p, "w"))
print("consumido: %d — total %d/%d" % (add, s["used"], s["limit"]))
sys.exit(4 if s["used"] >= s["limit"] else 0)
'
    ;;
  reset)
    printf '{"limit": %s, "used": 0, "reset_day": "Monday"}\n' "$LIMIT" > "$STATE_FILE"
    echo "token plan qwen resetado (limite $LIMIT)"
    ;;
  *)
    echo "Uso: token-plan.sh {status|consume <tokens>|reset}" >&2
    exit 3
    ;;
esac
