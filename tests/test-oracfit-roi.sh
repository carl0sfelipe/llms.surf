#!/bin/bash
# tests/test-oracfit-roi.sh — ROI por executor a partir dos ledgers.
# Proposta: docs/proposta-check-delegacao.md §4. Padrão: tests/test-verificar.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROI="$ROOT/bin/oracfit-roi.py"
OF="$ROOT/bin/oracfit"
TMPDIR="$(mktemp -d /tmp/oracfit-roi.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_de() { set +e; "$@" >"$TMPDIR/last.log" 2>&1; echo $?; set -e; }

escreve_ledger() {
  mkdir -p "$1/.dispatch/ledger"
  cat >"$1/.dispatch/ledger/mode.jsonl" <<'EOF'
{"ts":"2026-09-01T10:00:00Z","model_id":"claude-sonnet-5","task":"a","status":"pass","attempt":"1","estimated_cost":"0.4","flash_work_s":"10","executor_out_tok":"100"}
{"ts":"2026-09-02T10:00:00Z","model_id":"claude-sonnet-5","task":"b","status":"pass","attempt":"1","estimated_cost":"0.5","flash_work_s":"10","executor_out_tok":"100"}
{"ts":"2026-09-03T10:00:00Z","model_id":"claude-sonnet-5","task":"c","status":"pass","attempt":"1","estimated_cost":"0.6","flash_work_s":"10","executor_out_tok":"100"}
{"ts":"2026-09-04T10:00:00Z","model_id":"claude-sonnet-5","task":"d","status":"fail","attempt":"5","estimated_cost":"0","flash_work_s":"10"}
{"ts":"2026-09-05T10:00:00Z","model_id":"orquestrador","task":"e","status":"pass","attempt":"1","estimated_cost":"0","flash_work_s":"10","cost_source":"orquestrador-nao-medido"}
{"ts":"2026-09-06T10:00:00Z","model_id":"orquestrador","task":"f","status":"pass","attempt":"1","estimated_cost":"0","flash_work_s":"10","cost_source":"orquestrador-nao-medido"}
isto nao e json
EOF
}

W="$TMPDIR/w"; escreve_ledger "$W"

echo "== 1. --json: sonnet e orquestrador"
[ "$(rc_de python3 "$ROI" --workdir "$W" --json)" -eq 0 ] && ok "exit 0" || not "exit 0"
python3 - "$TMPDIR/last.log" <<'PY' && ok "json campos" || not "json campos"
import json, sys
d = json.loads(open(sys.argv[1]).read())
s = d["modelos"]["claude-sonnet-5"]
assert s["runs"] == 4 and s["pass"] == 3 and s["primeira"] == 75, s
assert s["custo_medido_usd"] == 1.5 and s["runs_com_custo"] == 3, s
assert s["custo_por_pass_usd"] == 0.5, s
o = d["modelos"]["orquestrador"]
assert o["custo_medido_usd"] == 0 and o["runs_com_custo"] == 0, o
assert o["custo_por_pass_usd"] == "n/d", o
assert d["linhas_ignoradas"] == 1, d
PY

echo "== 2. tabela mostra n/d (custo não medido)"
[ "$(rc_de python3 "$ROI" --workdir "$W")" -eq 0 ] || not "tabela rc"
grep -q n/d "$TMPDIR/last.log" && grep -q orquestrador "$TMPDIR/last.log" && ok "tabela n/d" || not "tabela n/d"

echo "== 3. --desde posterior a todas as linhas → nenhum modelo"
[ "$(rc_de python3 "$ROI" --workdir "$W" --desde 2099-01-01 --json)" -eq 0 ] || not "desde rc"
python3 - "$TMPDIR/last.log" <<'PY' && ok "desde vazio" || not "desde vazio"
import json, sys
assert json.loads(open(sys.argv[1]).read())["modelos"] == {}
PY

echo "== 4. dois --workdir somam"
W2="$TMPDIR/w2"; escreve_ledger "$W2"
[ "$(rc_de python3 "$ROI" --workdir "$W" --workdir "$W2" --json)" -eq 0 ] || not "soma rc"
python3 - "$TMPDIR/last.log" <<'PY' && ok "dois workdirs somam" || not "dois workdirs somam"
import json, sys
d = json.loads(open(sys.argv[1]).read())
s = d["modelos"]["claude-sonnet-5"]
assert s["runs"] == 8 and s["pass"] == 6 and s["custo_medido_usd"] == 3.0, s
assert d["linhas_ignoradas"] == 2, d
PY

echo "== 5. workdir sem ledger → exit 3"
E="$TMPDIR/empty"; mkdir -p "$E"
[ "$(rc_de python3 "$ROI" --workdir "$E")" -eq 3 ] && ok "exit 3" || not "exit 3"
grep -q ".dispatch/ledger/mode.jsonl" "$TMPDIR/last.log" && ok "cita caminho" || not "cita caminho"

echo "== 6. bin/oracfit roi --json igual ao script"
[ "$(rc_de python3 "$ROI" --workdir "$W" --json)" -eq 0 ] || not "script json"
cp "$TMPDIR/last.log" "$TMPDIR/script.json"
[ "$(rc_de "$OF" roi --workdir "$W" --json)" -eq 0 ] || not "oracfit roi rc"
diff -q "$TMPDIR/script.json" "$TMPDIR/last.log" >/dev/null && ok "oracfit roi igual" || not "oracfit roi igual"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
