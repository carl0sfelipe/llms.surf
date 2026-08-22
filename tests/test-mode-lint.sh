#!/usr/bin/env bash
# tests/test-mode-lint.sh — regra 32 mecanizada: lint claims→mecanismos
# (lib-oracfit-mode-loader.py lint) + extensão do incident.sh audit.
#
#  T1  claim de perpetuidade na description SEM mecanismo(wake) = LINT FAIL
#      (aion: yaml declarava a fragilidade e ela matou o despertador)
#  T2  mecanismo declarado apontando path inexistente = LINT FAIL
#      (demiurgo: alegou hard-fails mecânicos que não eram código)
#  T3  claim + mecanismo válido e executável = LINT OK
#  T4  id != nome do arquivo = LINT FAIL (colisão hefesto)
#  T5  'mecânico' na description sem nenhuma declaração = LINT FAIL
#  T6  audit: incidente novo (>=2026-08-13) quitado por 'mecanismo aplicado'
#      sem path existente citado = DÍVIDA; com path real = quitado
#  T7  audit: incidente LEGADO com quitação por mecanismo sem path = warning,
#      não dívida (não reabrir os 87)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$REPO_ROOT/bin/lib-oracfit-mode-loader.py"
INCIDENT="$REPO_ROOT/bin/incident.sh"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK=$(mktemp -d /tmp/test-mode-lint.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

lint() { # $1=arquivo → echo rc
  local rc=0
  python3 "$LOADER" lint "$1" --root "$REPO_ROOT" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

base_yaml() { # $1=id $2=description $3=linhas extra
  cat <<EOF
id: $1
version: 1
description: $2
$3
stages:
  - role: plan
    model_ref: frontier-host
  - role: run
    model_ref: frontier-host
EOF
}

echo "=== test-mode-lint ==="

echo "--- T1: claim de perpetuidade sem mecanismo(wake) ---"
base_yaml claimmode "god mode com cadeia perpetua de aneis" "" > "$WORK/claimmode.yaml"
[ "$(lint "$WORK/claimmode.yaml")" -eq 2 ] && ok "LINT FAIL rc=2" || not "claim sem mecanismo deveria falhar"

echo "--- T2: mecanismo apontando path inexistente ---"
base_yaml fakemech "god mode com cadeia perpetua" "# mecanismo(wake): bin/nao-existe.sh" > "$WORK/fakemech.yaml"
[ "$(lint "$WORK/fakemech.yaml")" -eq 2 ] && ok "path fantasma falha rc=2" || not "mecanismo fantasma deveria falhar"

echo "--- T3: claim + mecanismo real e executável ---"
base_yaml realmech "god mode com cadeia perpetua e ledger mecanico" \
"# mecanismo(wake): bin/oracfit-daemon.sh
# mecanismo(ring): bin/oracfit-ring.sh" > "$WORK/realmech.yaml"
[ "$(lint "$WORK/realmech.yaml")" -eq 0 ] && ok "LINT OK rc=0" || not "mecanismo real deveria passar"

echo "--- T4: id != nome do arquivo ---"
base_yaml outronome "modo simples" "" > "$WORK/arquivo.yaml"
[ "$(lint "$WORK/arquivo.yaml")" -eq 2 ] && ok "id/arquivo divergentes falham rc=2" || not "colisão de id deveria falhar"

echo "--- T5: 'mecânico' sem declaração nenhuma ---"
base_yaml vaziomech "oraculo mecanico soberano" "" > "$WORK/vaziomech.yaml"
[ "$(lint "$WORK/vaziomech.yaml")" -eq 2 ] && ok "'mecânico' sem declaração falha rc=2" || not "deveria falhar"

echo "--- T6: audit exige path real em quitação por mecanismo (novos) ---"
INC_DIR="$WORK/incidents"
mkdir -p "$INC_DIR"
cat > "$INC_DIR/2026-08-14-mecanismo-sem-codigo.md" <<'EOF'
---
id: 2026-08-14-mecanismo-sem-codigo
titulo: alega mecanismo sem citar código
data: 2026-08-14
recorrivel: sim
regra: mecanismo aplicado
status: aberto
---
Corpo sem nenhum path citado.
EOF
rc=0; INCIDENTS_DIR="$INC_DIR" bash "$INCIDENT" audit >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "mecanismo sem path = dívida (rc=1)" || not "esperava rc=1, veio $rc"
cat > "$INC_DIR/2026-08-14-mecanismo-sem-codigo.md" <<'EOF'
---
id: 2026-08-14-mecanismo-sem-codigo
titulo: alega mecanismo citando código real
data: 2026-08-14
recorrivel: sim
regra: mecanismo aplicado
status: aberto
---
Fechado por bin/oracfit-ring.sh (guarda monotônica).
EOF
rc=0; INCIDENTS_DIR="$INC_DIR" bash "$INCIDENT" audit >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "path real quita (rc=0)" || not "esperava rc=0, veio $rc"

echo "--- T7: legado sem path = warning, não dívida ---"
rm -f "$INC_DIR"/*.md
cat > "$INC_DIR/2026-07-20-legado-mecanismo.md" <<'EOF'
---
id: 2026-07-20-legado-mecanismo
titulo: legado quitado por mecanismo sem path
data: 2026-07-20
recorrivel: sim
regra: virou codigo
status: aberto
---
Corpo antigo sem path.
EOF
out=$(INCIDENTS_DIR="$INC_DIR" bash "$INCIDENT" audit 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "legado"; then
  ok "legado passa com warning (rc=0)"
else
  not "legado deveria passar com warning (rc=$rc)"
fi

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
