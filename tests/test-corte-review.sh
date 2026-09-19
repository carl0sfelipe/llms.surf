#!/usr/bin/env bash
# tests/test-corte-review.sh — review de corte de versão (bin/corte-review.py
# + /api/gui/corte + /corte.html, o tripé da página de triagem do corte).
#
#  T1  corte sadio: APPROVED, todas as checagens passam, exit 0
#  T2  telefone no corte: REJECTED pelo scan (C1 do check-publico real)
#  T3  VERSION regredida: REJECTED (classe do rsync invertido, regra 52)
#  T4  specs/ vazando no corte: REJECTED (categoria privada)
#  T5  marcador de cliente em incidents: REJECTED (anon)
#  T6  diff: faltando/mudou/transform classificados (transform não é warn)
#  T7  sem marker PUBLIC-CUT.md / dir inexistente: exit 2 com erro claro
#  T8  --json é JSON válido com os campos do contrato
#  T9  /api/gui/corte responde ok:verdict na GUI; /corte.html servida com
#      marcador; nav do gui.js aponta pra ela
#
# Fixtures em mktemp: mini-oficina e mini-corte gitados — o diff compara
# árvore commitada, então nada de working tree suja entre eles.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$REPO_ROOT/bin/corte-review.py"
# shellcheck source=lib-gui-http.sh
source "$REPO_ROOT/tests/lib-gui-http.sh"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); gui_dump_log "${SRV_LOG:-}"; }

WORK=$(mktemp -d /tmp/test-corte-review.XXXXXX)
SERVER_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  wait "$SERVER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

GITC="git -c user.name=t -c user.email=t@local"

# ── fixture: mini-oficina (superfície mínima + VERSION 1.0.0) ──────────────
mk_oficina() {
  local d="$1"
  mkdir -p "$d/core/modes" "$d/docs" "$d/incidents"
  echo "id: x" > "$d/core/modes/x.yaml"
  echo "texto base" > "$d/core/lib.txt"
  printf 'oficina readme\n' > "$d/README.md"
  echo "1.0.0" > "$d/VERSION"
  echo "# i" > "$d/incidents/README.md"
  echo "doc" > "$d/docs/functions.md"
  (cd "$d" && git init -q -b main && $GITC add -A && $GITC commit -qm oficina)
}

# ── fixture: mini-corte (marker + espelho da superfície) ───────────────────
mk_corte() {
  local d="$1"
  mkdir -p "$d/core/modes" "$d/docs" "$d/incidents"
  echo "id: x" > "$d/core/modes/x.yaml"
  echo "texto base" > "$d/core/lib.txt"
  printf 'corte readme reescrito\n' > "$d/README.md" # TRANSFORM de propósito
  echo "1.0.0" > "$d/VERSION"
  echo "# corte público" > "$d/docs/PUBLIC-CUT.md"   # marker
  echo "# i" > "$d/incidents/README.md"
  echo "doc" > "$d/docs/functions.md"
  (cd "$d" && git init -q -b main && $GITC add -A && $GITC commit -qm corte)
}

run_review() { OFICINA_DIR="$OFICINA" python3 "$REVIEW" "$@"; }
run_json()   { OFICINA_DIR="$OFICINA" python3 "$REVIEW" --json "$1"; }

echo "=== test-corte-review ==="

OFICINA="$WORK/oficina"; mk_oficina "$OFICINA"
CORTE="$WORK/corte";     mk_corte "$CORTE"

# ── T1: corte sadio ─────────────────────────────────────────────────────────
OUT=$(run_review "$CORTE")
echo "$OUT" | grep -q "APPROVED" && ok "T1 corte sadio → APPROVED" \
  || not "T1 esperava APPROVED, saiu: $(echo "$OUT" | head -3)"
echo "$OUT" | grep -q "check-publico limpo" && ok "T1b scan limpo (check-publico real)" || not "T1b scan"

# ── T2: telefone no corte ───────────────────────────────────────────────────
# NOTA: formato sem espaço pós-9 — é o que o C1 do check-publico GARANTE
# casar. O formato "9 8888-7777" (espaço pós-9) não é coberto pelo C1 hoje:
# gap conhecido, candidado a evolução do check-publico, não deste teste.
CORTE2="$WORK/corte-fone"; mk_corte "$CORTE2"
# literal quebrado na fonte: o C1 do check-publico escaneia a própria
# oficina — em runtime a concatenação reconstitui o telefone do fixture.
echo "ligue pra (21) 9""8888-7777" > "$CORTE2/incidents/com-contato.md"
(cd "$CORTE2" && $GITC add -A && $GITC commit -qm fone)
OUT=$(run_review "$CORTE2")
echo "$OUT" | grep -q "REJECTED" && ok "T2 telefone → REJECTED" || not "T2 esperava REJECTED: $OUT"
echo "$OUT" | grep -q "biggest_gap: scan" && ok "T2b biggest_gap aponta o scan" || not "T2b biggest_gap"

# ── T3: VERSION regredida ───────────────────────────────────────────────────
CORTE3="$WORK/corte-velho"; mk_corte "$CORTE3"
echo "0.9.0" > "$CORTE3/VERSION"
(cd "$CORTE3" && $GITC add -A && $GITC commit -qm velho)
OUT=$(run_review "$CORTE3")
echo "$OUT" | grep -q "REGREDIU" && ok "T3 VERSION regredida → REJECTED" || not "T3: $OUT"

# ── T4: categoria privada presente ──────────────────────────────────────────
CORTE4="$WORK/corte-specs"; mk_corte "$CORTE4"
mkdir -p "$CORTE4/specs" && echo "lista de contatos" > "$CORTE4/specs/cliente.md"
(cd "$CORTE4" && $GITC add -A && $GITC commit -qm specs)
OUT=$(run_review "$CORTE4")
echo "$OUT" | grep -q "categoria privada NO corte: specs" && ok "T4 specs/ vaza → REJECTED" || not "T4: $OUT"

# ── T5: marcador de cliente em incidents ────────────────────────────────────
CORTE5="$WORK/corte-orbe"; mk_corte "$CORTE5"
echo "o bug nasceu no repo orbe do cliente" > "$CORTE5/incidents/2026-01-01-postmortem.md"
(cd "$CORTE5" && $GITC add -A && $GITC commit -qm orbe)
OUT=$(run_review "$CORTE5")
echo "$OUT" | grep -q "anon" && echo "$OUT" | grep -q "REJECTED" \
  && ok "T5 marcador de cliente → REJECTED (anon)" || not "T5: $OUT"

# ── T6: diff faltando/mudou/transform ───────────────────────────────────────
CORTE6="$WORK/corte-diff"; mk_corte "$CORTE6"
rm "$CORTE6/core/lib.txt"                      # faltando
echo "id: y" > "$CORTE6/core/modes/x.yaml"     # mudou
(cd "$CORTE6" && $GITC add -A && $GITC commit -qm diff)
J=$(run_json "$CORTE6")
echo "$J" | python3 -c '
import json, sys
d = json.load(sys.stdin)
diff = [c for c in d["checks"] if c["id"] == "diff"][0]
assert "core/lib.txt" in diff["faltando"], diff["faltando"]
assert "core/modes/x.yaml" in diff["mudou"], diff["mudou"]
assert "README.md" in diff["transform"], diff["transform"]
assert d["verdict"] == "APPROVED", d["verdict"]  # divergência não bloqueia
' 2>/dev/null && ok "T6 diff classifica faltando/mudou/transform" || not "T6 classificação do diff"

# ── T7: uso errado ──────────────────────────────────────────────────────────
run_review "$WORK/nao-existe" >/dev/null 2>&1; [ $? -eq 2 ] \
  && ok "T7 dir inexistente → exit 2" || not "T7 exit esperado 2"
CORTE7="$WORK/corte-sem-marker"; mk_corte "$CORTE7"; rm "$CORTE7/docs/PUBLIC-CUT.md"
(cd "$CORTE7" && $GITC add -A && $GITC commit -qm semmarker)
OUT=$(run_review "$CORTE7" 2>&1)
echo "$OUT" | grep -q "PUBLIC-CUT" \
  && ok "T7b sem marker → erro claro" || not "T7b sem marker: $OUT"

# ── T8: --json válido ───────────────────────────────────────────────────────
run_json "$CORTE" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in ("ok", "ts", "oficina", "corte", "checks", "contexto", "verdict", "fontes"):
    assert k in d, k
assert d["corte"]["commits"] >= 1
assert len(d["checks"]) == 5
' 2>/dev/null && ok "T8 --json tem o contrato completo" || not "T8 contrato do JSON"

# ── T9: GUI — API + página + nav ────────────────────────────────────────────
# Porta efêmera (--port 0), como as outras suítes de GUI: 8797 fixa colidia
# com qualquer servidor deixado vivo por outra suíte no mesmo runner.
SRV_LOG="$WORK/server.log"
ORACFIT_CORTE_DIR="$CORTE" python3 "$REPO_ROOT/bin/oracfit-todo-server.py" \
  --panel-dir "$REPO_ROOT/panel" --logs-dir "$WORK/logs" --port 0 --bind 127.0.0.1 \
  > "$SRV_LOG" 2>&1 &
SERVER_PID=$!
PORT=$(gui_wait_port "$SRV_LOG" corte.html || true)
[ -n "$PORT" ] || not "T9 servidor da GUI não subiu"
GUI=$(gui_get "http://127.0.0.1:$PORT/api/gui/corte" || true)
echo "$GUI" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d.get("ok") and d.get("verdict") in ("APPROVED", "REJECTED"), d.get("error")
' 2>/dev/null && ok "T9 /api/gui/corte ok+verdict" || not "T9 API: $GUI"
gui_get "http://127.0.0.1:$PORT/corte.html" | grep -q "Corte público — revisão de versão" \
  && ok "T9b /corte.html servida" || not "T9b página"
grep -q 'corte.html" label: "Corte público"' "$REPO_ROOT/panel/gui.js" 2>/dev/null
grep -q '"corte.html", label: "Corte público"' "$REPO_ROOT/panel/gui.js" \
  && ok "T9c nav do gui.js aponta pra corte" || not "T9c nav"

echo "=== Result: $pass passaram, $fail falharam ==="
[ "$fail" -eq 0 ]
