#!/bin/bash
# test-lineup-machine.sh — S13: o medidor do The Lineup em fixtures.
# Prova: ordenação por created_at · anti-sockpuppet (indicado sem
# contribuição não converte) · determinismo byte-a-byte · issue única.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

WD="$(mktemp -d)"
trap 'rm -rf "$WD"' EXIT

# issues fixture: 3 waitlisters
#   @ana    (sem referral, contribuiu 4 pts no bestmodel)
#   @bruno  (referred by @ana — ana contribuiu → CONVERTE)
#   @carla  (referred by @duda — duda não existe na lista → NÃO converte)
cat > "$WD/issues.json" <<'EOF'
[
  {"number": 12, "user": {"login": "bruno"}, "created_at": "2026-08-29T10:00:00Z",
   "body": "quero rodar meus agents\nreferred by: @ana\n- [x] consent: ok"},
  {"number": 10, "user": {"login": "ana"}, "created_at": "2026-08-28T09:00:00Z",
   "body": "benchmarks de vision\n- [x] consent: ok"},
  {"number": 15, "user": {"login": "carla"}, "created_at": "2026-08-30T08:00:00Z",
   "body": "sou dev\nreferred by: @duda\n- [x] consent: ok"}
]
EOF
cat > "$WD/export.json" <<'EOF'
{"generated_at": "2026-08-30T12:00:00Z",
 "contributors": [{"handle": "@ana", "points": 4, "validated_runs": 2}]}
EOF

# ═══ T1: ordenação + pontos + anti-sockpuppet ═══
bash "$ROOT/bin/lineup-build.sh" --issues "$WD/issues.json" --export "$WD/export.json" --out "$WD/lineup1.json"
python3 - "$WD/lineup1.json" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
es = d["entries"]
assert [e["handle"] for e in es] == ["ana", "bruno", "carla"], f"ordem errada: {[e['handle'] for e in es]}"
ana, bruno, carla = es
assert ana["points_total"] == 1 + 4, f"ana: {ana['points_total']} (join 1 + contrib 4)"
assert ana["contribution_points"] == 4
assert bruno["referral_converted"] is True and bruno["points_total"] == 1 + 3, f"bruno: {bruno}"
assert carla["referral_converted"] is False and carla["points_total"] == 1, f"carla: {carla} (duda não existe → não converte)"
assert d["points_table_dial"] == "pending-owner"
print("ok: ordenação, pontos e anti-sockpuppet")
PY

# ═══ T2: determinismo byte-a-byte ═══
bash "$ROOT/bin/lineup-build.sh" --issues "$WD/issues.json" --export "$WD/export.json" --out "$WD/lineup2.json"
cmp -s "$WD/lineup1.json" "$WD/lineup2.json" || fail "saída não é determinística byte-a-byte"
echo "ok: byte-determinismo"

# ═══ T3: issue duplicado entra UMA vez ═══
python3 -c "
import json
d = json.load(open('$WD/issues.json'))
d.append(d[0])
json.dump(d, open('$WD/issues-dup.json', 'w'))"
bash "$ROOT/bin/lineup-build.sh" --issues "$WD/issues-dup.json" --export "$WD/export.json" --out "$WD/lineup3.json"
[ "$(grep -c '"handle"' "$WD/lineup3.json")" = "3" ] || fail "issue duplicado contou duas vezes"
echo "ok: issue única"

echo "test-lineup-machine: ok (3 casos)"
exit 0
