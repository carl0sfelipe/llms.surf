#!/usr/bin/env bash
# test-check-shadow-ledger.sh — D-NEXT-3: o medidor do cutover lê o ledger certo.
#
# writes: scratch dir only
# reads: bin/check-shadow-ledger.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHK="$ROOT/bin/check-shadow-ledger.sh"
pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not_() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WD=$(mktemp -d /tmp/shadow-ledger-XXXXXX)
trap 'rm -rf "$WD"' EXIT
echo "=== test-check-shadow-ledger (D-NEXT-3) ==="

# 1. ledger ausente → exit 3
rc=0; bash "$CHK" "$WD/nao-existe.jsonl" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] && ok "ledger ausente → exit 3" || not_ "ledger ausente rc=$rc (esperado 3)"

# 2. ledger sem linha em shadow → exit 0 e diz que não há tráfego
cat > "$WD/off.jsonl" <<'EOF'
{"task_name":"t-off","started_at":"2026-09-01T10:00:00Z","exit_status":"ok"}
{"task_name":"t-off-2","started_at":"2026-09-02T10:00:00Z","exit_status":"ok"}
EOF
rc=0; out=$(bash "$CHK" "$WD/off.jsonl" 2>&1) || rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "shadow: 0 linhas" \
  && ok "sem linha em shadow → exit 0, no-shadow-traffic" || not_ "sem shadow rc=$rc: $out"

# 3. três linhas em shadow, diff 0 → exit 0, conta 3 e 2 dias
cat > "$WD/zero.jsonl" <<'EOF'
{"task_name":"a","started_at":"2026-09-20T09:00:00Z","kernel_shadow_diff":0,"policy_version":{"crate":"0.1.0","kernel_sha":"abcdef123456789"}}
{"task_name":"b","started_at":"2026-09-20T12:00:00Z","kernel_shadow_diff":0,"policy_version":{"crate":"0.1.0","kernel_sha":"abcdef123456789"}}
{"task_name":"off","started_at":"2026-09-20T13:00:00Z"}
{"task_name":"c","started_at":"2026-09-21T09:00:00Z","kernel_shadow_diff":"0","policy_version":{"crate":"0.1.0","kernel_sha":"abcdef123456789"}}
EOF
rc=0; out=$(bash "$CHK" "$WD/zero.jsonl" 2>&1) || rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "shadow: 3 linhas · diff!=0: 0 · dias cobertos: 2" \
  && ok "3 linhas diff 0 → exit 0, 2 dias, linha off ignorada" || not_ "diff zero rc=$rc: $out"
echo "$out" | grep -q "crate 0.1.0" && ok "policy_version resumido" || not_ "policy_version ausente: $out"

# 4. uma linha diff 1 → exit 1 e nomeia a task
cat > "$WD/one.jsonl" <<'EOF'
{"task_name":"ok-1","started_at":"2026-09-20T09:00:00Z","kernel_shadow_diff":0}
{"task_name":"ruim","started_at":"2026-09-20T10:00:00Z","kernel_shadow_diff":1,"provider_efetivo_ref":"mimo-v2.5-free"}
lixo que não é json
EOF
rc=0; out=$(bash "$CHK" "$WD/one.jsonl" 2>&1) || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | grep -q "DIFF task=ruim" && echo "$out" | grep -q "malformadas puladas: 1" \
  && ok "diff 1 → exit 1, task nomeada, lixo pulado" || not_ "diff um rc=$rc: $out"

# 5. --json tem o contrato
rc=0; out=$(bash "$CHK" "$WD/one.jsonl" --json 2>/dev/null) || rc=$?
echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["shadow_rows"] == 2 and d["diff_rows"] == 1 and d["verdict"] == "diff-nonzero", d
assert d["diffs"][0]["task_name"] == "ruim", d
' 2>/dev/null && ok "--json: shadow_rows/diff_rows/verdict/diffs" || not_ "--json contrato: $out"

# 6. LEDGER_DIR sobrepõe o default (sem mode.jsonl no workdir → só o central)
mkdir -p "$WD/ld" && cp "$WD/zero.jsonl" "$WD/ld/ledger.jsonl"
rc=0; out=$(LEDGER_DIR="$WD/ld" ORACFIT_WORKDIR="$WD/vazio" bash "$CHK" 2>&1) || rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "$WD/ld/ledger.jsonl" \
  && ok "LEDGER_DIR respeitado" || not_ "LEDGER_DIR rc=$rc: $out"

# 7. ledger de modo (chaves planas, ts em vez de started_at) agregado ao central
mkdir -p "$WD/wd/.dispatch/ledger"
cat > "$WD/wd/.dispatch/ledger/mode.jsonl" <<'EOF'
{"v":1,"ts":"2026-09-22T01:00:00+00:00","run_id":"R1","mode_id":"kernel_test","stage":"multi","oracle_exit":"2","attempt":"3","task":"p1-T01","status":"fail","provider_efetivo":"","kernel_shadow_diff":"0","policy_version_crate":"0.1.0","policy_version_sha":"abcdef123456789"}
{"v":1,"ts":"2026-09-22T02:00:00+00:00","run_id":"R2","mode_id":"normal","stage":"run","oracle_exit":"0","attempt":"1","task":"off-run","status":"pass"}
EOF
rc=0; out=$(LEDGER_DIR="$WD/ld" ORACFIT_WORKDIR="$WD/wd" bash "$CHK" 2>&1) || rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "shadow: 4 linhas · diff!=0: 0 · dias cobertos: 3" \
  && echo "$out" | grep -q "mode.jsonl" \
  && ok "central + mode.jsonl agregados (4 linhas, 3 dias, chaves planas lidas)" || not_ "agregação rc=$rc: $out"

# 8. diff no ledger de modo nomeia o arquivo e a task
cat > "$WD/wd/.dispatch/ledger/mode.jsonl" <<'EOF'
{"v":1,"ts":"2026-09-22T01:00:00+00:00","run_id":"R3","mode_id":"kernel_test","task":"p1-T02","status":"fail","kernel_shadow_diff":"1","policy_version_crate":"0.1.0"}
EOF
rc=0; out=$(bash "$CHK" "$WD/wd/.dispatch/ledger/mode.jsonl" --json 2>/dev/null) || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["diff_rows"] == 1 and d["diffs"][0]["task_name"] == "p1-T02" and d["diffs"][0]["ledger"].endswith("mode.jsonl"), d
' 2>/dev/null && ok "diff em mode.jsonl → exit 1 com task e ledger" || not_ "diff em modo rc=$rc: $out"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
