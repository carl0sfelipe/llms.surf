#!/usr/bin/env bash
# tests/test-pantocrator-mode.sh — modo PANTOCRATOR (god mode v3.5 em cadeia).
#
# A tese do modo é ser o primeiro god mode cujo YAML passa no mode-loader
# (postmortem 2026-08-12: "yaml vira documentação no host-mode" — campo fora
# do schema é protocolo silenciosamente ignorado). Este teste protege isso:
#
# TESTE 1: pantocrator.yaml VALIDA no lib-oracfit-mode-loader (rc=0).
# TESTE 2: dump expõe os campos de máquina que o protocolo promete
#          (id, gauntlet fail-closed com teto, on_fail halt, budget).
# TESTE 3: nenhuma chave fora do schema v1 escapou para o YAML (o dump não
#          pode conter chain/hardening/never/halt_conditions/critic_profile
#          — protocolo é comentário, máquina é schema).
# TESTE 4: critic profile pantocrator-auditor existe e contém as cláusulas
#          fail-closed (biggest_gap, claims-check, previsão de nota, classe).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$REPO_ROOT/bin/lib-oracfit-mode-loader.py"
MODE="$REPO_ROOT/core/modes/pantocrator.yaml"
PROFILE="$REPO_ROOT/core/critic-profiles/pantocrator-auditor.md"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-pantocrator-mode ==="

echo "--- TESTE 1: valida no loader ---"
rc=0
python3 "$LOADER" validate "$MODE" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "pantocrator.yaml valida (rc=0)"; else not "pantocrator.yaml deveria validar (rc=$rc)"; fi

echo "--- TESTE 2: campos de máquina prometidos ---"
dump=$(python3 "$LOADER" dump "$MODE" 2>/dev/null)
rc_dump=$?
if [ "$rc_dump" -ne 0 ] || [ -z "$dump" ]; then
  not "dump do yaml falhou (rc=$rc_dump) — testes 2 e 3 inválidos"
else
  echo "$dump" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["id"] == "pantocrator", d["id"]
g = d["gauntlet"]
assert g["enabled"] is True and g["until_approved"] is True
assert isinstance(g["safety_ceiling"], int) and g["safety_ceiling"] >= 1
assert g["critic_model_ref"] == "frontier-host"
assert d["on_fail"] == "halt"
assert isinstance(d["run_attempt_budget"], int) and d["run_attempt_budget"] >= 1
roles = [s["role"] for s in d["stages"]]
assert roles == ["plan", "run"], roles
' && ok "id/gauntlet/on_fail/budget/roles conferem" || not "campos de máquina divergem do protocolo"

  echo "--- TESTE 3: nenhuma chave fora do schema escapou ---"
  vazou=0
  for chave in chain hardening never halt_conditions critic_profile stop_when skip_when; do
    if echo "$dump" | grep -q "\"$chave\""; then
      not "chave '$chave' vazou para os campos de máquina"
      vazou=1
    fi
  done
  if [ "$vazou" -eq 0 ]; then ok "protocolo ficou em comentário; máquina é schema v1 puro"; fi
fi

echo "--- TESTE 4: critic profile fail-closed ---"
if [ ! -f "$PROFILE" ]; then
  not "critic profile ausente: $PROFILE"
else
  faltou=0
  for clausula in "biggest_gap" "laims-check" "nota do dono" "CLASSE"; do
    if ! grep -q "$clausula" "$PROFILE"; then
      not "cláusula '$clausula' ausente do profile"
      faltou=1
    fi
  done
  if [ "$faltou" -eq 0 ]; then ok "profile contém biggest_gap + claims-check + previsão de nota + gate de classe"; fi
fi

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
