#!/usr/bin/env bash
# tests/test-ananke-mode.sh — modo ANANKE (god mode v4 sobre mecanismos).
#
# A tese do modo é ser o primeiro god mode que passa no VALIDATE **E** no
# LINT claims→mecanismos (regra 32 mecanizada): toda claim da description
# aponta executável existente. Este teste protege isso:
#
# TESTE 1: ananke.yaml VALIDA no lib-oracfit-mode-loader (rc=0).
# TESTE 2: ananke.yaml passa no LINT — claims wake/ring/visual têm
#          mecanismo declarado apontando executável REAL.
# TESTE 3: dump expõe os campos de máquina (id, gauntlet fail-closed com
#          teto, on_fail halt, budget) e nenhuma chave de protocolo vazou.
# TESTE 4: critic profile ananke-critic existe com as cláusulas fail-closed
#          (biggest_gap, owner_score_pred, claims-check, oracle_change).
# TESTE 5: os mecanismos declarados no yaml são exatamente os que o ring
#          runner implementa (oracfit-ring.sh, oracfit-daemon.sh).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$REPO_ROOT/bin/lib-oracfit-mode-loader.py"
MODE="$REPO_ROOT/core/modes/ananke.yaml"
PROFILE="$REPO_ROOT/core/critic-profiles/ananke-critic.md"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-ananke-mode ==="

echo "--- TESTE 1: valida no loader ---"
rc=0
python3 "$LOADER" validate "$MODE" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "ananke.yaml valida (rc=0)" || not "deveria validar (rc=$rc)"

echo "--- TESTE 2: passa no lint claims→mecanismos ---"
rc=0
out=$(python3 "$LOADER" lint "$MODE" --root "$REPO_ROOT" 2>&1) || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "lint rc=0"
  echo "$out" | grep -q "ring" && echo "$out" | grep -q "wake" && echo "$out" | grep -q "visual" \
    && ok "mecanismos ring+wake+visual declarados" || not "declarações incompletas: $out"
else
  not "lint falhou: $out"
fi

echo "--- TESTE 3: campos de máquina + nenhum vazamento de protocolo ---"
dump=$(python3 "$LOADER" dump "$MODE" 2>/dev/null)
echo "$dump" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["id"] == "ananke", d["id"]
g = d["gauntlet"]
assert g["enabled"] is True and g["until_approved"] is True
assert isinstance(g["safety_ceiling"], int) and g["safety_ceiling"] >= 1
assert g["critic_model_ref"] == "frontier-host"
assert d["on_fail"] == "halt"
assert isinstance(d["run_attempt_budget"], int) and d["run_attempt_budget"] >= 1
assert [s["role"] for s in d["stages"]] == ["plan", "run"]
' && ok "id/gauntlet/on_fail/budget/roles conferem" || not "campos de máquina divergem"
vazou=0
for chave in chain hardening never halt_conditions critic_profile stop_when skip_when mecanismo; do
  if echo "$dump" | grep -q "\"$chave\""; then
    not "chave '$chave' vazou para os campos de máquina"
    vazou=1
  fi
done
[ "$vazou" -eq 0 ] && ok "protocolo em comentário; máquina é schema v1 puro"

echo "--- TESTE 4: critic profile fail-closed ---"
if [ ! -f "$PROFILE" ]; then
  not "critic profile ausente: $PROFILE"
else
  faltou=0
  for clausula in "biggest_gap" "owner_score_pred" "laims-check" "oracle_change_approved" "check-verdict"; do
    if ! grep -q "$clausula" "$PROFILE"; then
      not "cláusula '$clausula' ausente do profile"
      faltou=1
    fi
  done
  [ "$faltou" -eq 0 ] && ok "profile contém contrato do arquivo + claims-check + guarda da trave"
fi

echo "--- TESTE 5: mecanismos declarados = implementados ---"
faltou=0
for mech in bin/oracfit-ring.sh bin/oracfit-daemon.sh; do
  if ! grep -q "mecanismo(.*): $mech" "$MODE"; then
    not "yaml não declara $mech"
    faltou=1
  fi
  if [ ! -x "$REPO_ROOT/$mech" ]; then
    not "$mech não existe ou não é executável"
    faltou=1
  fi
done
[ "$faltou" -eq 0 ] && ok "declarações batem com executáveis reais"

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
