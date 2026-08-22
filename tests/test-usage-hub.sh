#!/bin/bash
# tests/test-usage-hub.sh — hub de uso de tokens built-in (v3.5).
#
# Cobre bin/usage-hub.py (status/recommend/pick/observe) e a integração com
# bin/pre-dispatch-check.sh. Tudo em fixtures: DB sqlite sintético, limites
# calibrados de mentira, observações com timestamp real.
#
# Padrão: tests/test-model-override.sh (mktemp, contadores pass/fail,
# exit 1 se falhar).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HUB="$ROOT/bin/usage-hub.py"
PREDISPATCH="$ROOT/bin/pre-dispatch-check.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-usage-hub.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# ── fixtures ─────────────────────────────────────────────────────────────────
DB="$TMPDIR/opencode.db"
NOW_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
RECENT=$((NOW_MS - 60000))   # 1min atrás — dentro de todas as janelas
sqlite3 "$DB" <<EOF
CREATE TABLE session (
  id TEXT PRIMARY KEY, model TEXT,
  tokens_input INTEGER DEFAULT 0, tokens_output INTEGER DEFAULT 0,
  time_created INTEGER NOT NULL
);
INSERT INTO session VALUES
 ('s1','{"id":"m-exh","providerID":"prov-exhausted"}',600000,600000,$RECENT),
 ('s2','{"id":"m-warn","providerID":"prov-warn"}',450000,450000,$RECENT),
 ('s3','{"id":"m-ok","providerID":"prov-free"}',60,40,$RECENT);
EOF

LIMITS="$TMPDIR/usage-limits.json"
cat >"$LIMITS" <<'EOF'
{
 "wait_pct": 85,
 "providers": {
  "prov-exhausted": {"windows": {"5h": {"limit_tokens": 1000000}}},
  "prov-warn":      {"windows": {"5h": {"limit_tokens": 1000000}}},
  "prov-free":      {"windows": {"5h": {"limit_tokens": null}}}
 }
}
EOF

REGISTRY="$TMPDIR/registry.json"
cat >"$REGISTRY" <<'EOF'
{
 "version": 1,
 "models": [
  {"id": "m-dead", "provider": "prov-free", "tier": "free",
   "id_status": "FANTASMA — id inexistente"},
  {"id": "m-exh",  "provider": "prov-exhausted", "tier": "free"},
  {"id": "m-thr",  "provider": "prov-throttled", "tier": "free"},
  {"id": "m-ok",   "provider": "prov-free", "tier": "free"},
  {"id": "m-hint", "provider": "zen", "tier": "free",
   "cli_hints": {"opencode": "prov-free/m-hint"}}
 ]
}
EOF

OBS="$TMPDIR/observations.jsonl"
python3 -c "
import json, time
print(json.dumps({'epoch': time.time()-120, 'ts': 'x',
 'provider': 'prov-throttled', 'model': 'm-thr', 'kind': 'rate_limit',
 'message': 'fixture', 'source': 'test'}))
" >"$OBS"

hub() {
  ORACFIT_USAGE_DB="$DB" ORACFIT_USAGE_LIMITS="$LIMITS" \
  ORACFIT_USAGE_OBS="$OBS" MODEL_REGISTRY="$REGISTRY" \
    python3 "$HUB" "$@"
}

# ── 1. recommend: livre / 90% / estourado / rate limit observado ────────────
rc=0; out=$(hub recommend --provider prov-free 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^USE'; then
  ok "recommend prov-free → USE exit 0"
else not "recommend prov-free (rc=$rc): $out"; fi

rc=0; out=$(hub recommend --provider prov-warn 2>&1) || rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '90%'; then
  ok "recommend prov-warn (90% do limite) → WAIT exit 1"
else not "recommend prov-warn (rc=$rc): $out"; fi

rc=0; out=$(hub recommend --provider prov-exhausted 2>&1) || rc=$?
if [ "$rc" -eq 4 ] && printf '%s' "$out" | grep -q 'estourado'; then
  ok "recommend prov-exhausted (120% do limite) → EXHAUSTED exit 4"
else not "recommend prov-exhausted (rc=$rc): $out"; fi

rc=0; out=$(hub recommend --provider prov-throttled 2>&1) || rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'rate_limit'; then
  ok "recommend prov-throttled (observação RF-08 há 2min) → WAIT exit 1"
else not "recommend prov-throttled (rc=$rc): $out"; fi

# ── 2. pick: pula morto (id_status), estourado (quota) e throttled (obs) ────
rc=0; out=$(hub pick --tiers "m-dead m-exh m-thr m-ok" 2>/dev/null) || rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "m-ok" ]; then
  ok "pick pula FANTASMA + exhausted + rate-limited e escolhe m-ok"
else not "pick escolheu errado (rc=$rc): '$out'"; fi

rc=0; out=$(hub pick --tiers "m-dead m-exh m-thr" 2>&1) || rc=$?
if [ "$rc" -eq 1 ]; then
  ok "pick sem ref viável → exit 1 (stdout vazio, motivo no stderr)"
else not "pick sem viável deveria dar exit 1 (rc=$rc): $out"; fi

rc=0; out=$(hub pick --tiers "m-dead m-exh m-ok" --json 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"picked": "m-ok"' \
  && printf '%s' "$out" | grep -q '"skipped"'; then
  ok "pick --json expõe trail com motivo de cada ref pulado"
else not "pick --json (rc=$rc): $out"; fi

# Incidente 2026-08-12 (baseline da release): ref AUSENTE do registry passava
# batido e o runner rejeitava em ~0s — batch queimou 2x600s. pick deve pular.
rc=0; out=$(hub pick --tiers "ref-que-nao-existe m-ok" --json 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '"picked": "m-ok"' \
  && printf '%s' "$out" | grep -q 'ausente do model-registry'; then
  ok "pick pula ref ausente do registry (invento do chamador, regra 11.2)"
else not "pick com ref fantasma-de-chamador (rc=$rc): $out"; fi

# ── 3. observe: grava e a próxima recommend do MESMO provider vê ────────────
OBS2="$TMPDIR/obs2.jsonl"
rc=0
ORACFIT_USAGE_DB="$DB" ORACFIT_USAGE_LIMITS="$LIMITS" \
ORACFIT_USAGE_OBS="$OBS2" MODEL_REGISTRY="$REGISTRY" \
  python3 "$HUB" observe --kind rate_limit --model-ref m-ok \
  --source test 2>/dev/null || rc=$?
out=$(ORACFIT_USAGE_DB="$DB" ORACFIT_USAGE_LIMITS="$LIMITS" \
  ORACFIT_USAGE_OBS="$OBS2" MODEL_REGISTRY="$REGISTRY" \
  python3 "$HUB" recommend --provider prov-free 2>&1) && rc2=0 || rc2=$?
if [ "$rc" -eq 0 ] && [ "${rc2:-0}" -eq 1 ] \
  && grep -q '"provider": "prov-free"' "$OBS2"; then
  ok "observe --model-ref infere provider via registry e recommend passa a vetar"
else not "observe→recommend não fechou o ciclo (rc=$rc rc2=${rc2:-?}): $out"; fi

# ── 3b. vocabulário de provider: cli_hints vence campo provider; alias na obs ─
# Verificado 2026-08-12: registry diz "zen", opencode.db grava "opencode".
# O providerID exato vem do 1º segmento de cli_hints.opencode.
rc=0; out=$(hub pick --tiers "m-hint" --json 2>&1) || rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s' "$out" | grep -q '"provider": "prov-free"'; then
  ok "provider_of usa cli_hints.opencode (provider 'zen' do registry ignorado)"
else not "provider via cli_hints (rc=$rc): $out"; fi

OBS3="$TMPDIR/obs3.jsonl"
python3 -c "
import json, time
print(json.dumps({'epoch': time.time()-60, 'ts': 'x', 'provider': 'zen',
 'model': 'x', 'kind': 'rate_limit', 'message': 'fixture', 'source': 'test'}))
" >"$OBS3"
rc=0; out=$(ORACFIT_USAGE_DB="$DB" ORACFIT_USAGE_LIMITS="$LIMITS" \
  ORACFIT_USAGE_OBS="$OBS3" MODEL_REGISTRY="$REGISTRY" \
  python3 "$HUB" recommend --provider opencode 2>&1) || rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'rate_limit'; then
  ok "observação gravada como 'zen' veta o canônico 'opencode' (alias)"
else not "alias zen→opencode na obs (rc=$rc): $out"; fi

# ── 4. fail-open: DB ausente nunca trava o gate ──────────────────────────────
rc=0; out=$(ORACFIT_USAGE_DB="$TMPDIR/nao-existe.db" \
  ORACFIT_USAGE_LIMITS="$LIMITS" ORACFIT_USAGE_OBS="$OBS" \
  MODEL_REGISTRY="$REGISTRY" \
  python3 "$HUB" recommend --provider prov-free 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'fail-open'; then
  ok "recommend com DB ausente → USE com aviso fail-open"
else not "fail-open quebrou (rc=$rc): $out"; fi

# ── 5. status --json: soma bate com o fixture ────────────────────────────────
rc=0; out=$(hub status --json 2>&1) || rc=$?
tok=$(printf '%s' "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
p = {r['provider']: r for r in d['providers']}
print(p['prov-free']['tokens']['5h'])
" 2>/dev/null || echo "?")
if [ "$rc" -eq 0 ] && [ "$tok" = "100" ]; then
  ok "status --json soma tokens_input+tokens_output por providerID (prov-free=100)"
else not "status --json (rc=$rc tok=$tok)"; fi

# ── 6. pre-dispatch-check integrado: exits 0/1/4 sem daemon HTTP ────────────
pdc() {
  DISPATCH_SKIP_CONCURRENCY=1 ORACFIT_USAGE_DB="$DB" \
  ORACFIT_USAGE_LIMITS="$LIMITS" ORACFIT_USAGE_OBS="$OBS" \
  MODEL_REGISTRY="$REGISTRY" bash "$PREDISPATCH" "$@"
}
rc=0; out=$(pdc prov-free 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^GO'; then
  ok "pre-dispatch-check prov-free → GO exit 0 (hub built-in, sem AI_USAGE_HUB_URL)"
else not "pre-dispatch-check GO (rc=$rc): $out"; fi

rc=0; out=$(pdc prov-warn 2>&1) || rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q '^WAIT'; then
  ok "pre-dispatch-check prov-warn → WAIT exit 1"
else not "pre-dispatch-check WAIT (rc=$rc): $out"; fi

rc=0; out=$(pdc prov-exhausted 2>&1) || rc=$?
if [ "$rc" -eq 4 ] && printf '%s' "$out" | grep -q '^EXHAUSTED'; then
  ok "pre-dispatch-check prov-exhausted → EXHAUSTED exit 4"
else not "pre-dispatch-check EXHAUSTED (rc=$rc): $out"; fi

echo
echo "=== RESULTS: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
