#!/bin/bash
# test-lineup-machine.sh — S13: o medidor do The Lineup em fixtures.
# Prova: ordenação por created_at · anti-sockpuppet (indicado sem
# contribuição não converte) · determinismo byte-a-byte · issue única ·
# E6-4.5: janela de conversão de referral atrás de dial.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

WD="$(mktemp -d)"
trap 'rm -rf "$WD"' EXIT

# issues fixture: 3 waitlisters
#   @ana    (sem referral, contribuiu 4 pts no bestmodel)
#   @bruno  (referred by @ana — ana contribuiu → CONVERTE)
#   @carla  (referred by @duda — duda não existe na lista → NÃO converte)
cat > "$WD/issues.json" <<'ISSUES'
[
  {"number": 12, "user": {"login": "bruno"}, "created_at": "2026-08-29T10:00:00Z",
   "body": "quero rodar meus agents\nreferred by: @ana\n- [x] consent: ok"},
  {"number": 10, "user": {"login": "ana"}, "created_at": "2026-08-28T09:00:00Z",
   "body": "benchmarks de vision\n- [x] consent: ok"},
  {"number": 15, "user": {"login": "carla"}, "created_at": "2026-08-30T08:00:00Z",
   "body": "sou dev\nreferred by: @duda\n- [x] consent: ok"}
]
ISSUES
cat > "$WD/export.json" <<'EXPORT'
{"generated_at": "2026-08-30T12:00:00Z",
 "contributors": [{"handle": "@ana", "points": 4, "validated_runs": 2}]}
EXPORT
# points fixture do teste: a máquina não pode depender do dial VIVO do dono
cat > "$WD/points.json" <<'POINTS'
{"dial": "fixture-v0",
 "points": {"join_issue": 1, "referral_converted": 3, "signed_run": 2,
            "run_reproduction": 3, "fake_caught": 5, "shared_custom_mode": 2},
 "referral_conversion": {"mode": "any_contribution"}}
POINTS

# ═══ T1: ordenação + pontos + anti-sockpuppet ═══
bash "$ROOT/bin/lineup-build.sh" --issues "$WD/issues.json" --export "$WD/export.json" --points "$WD/points.json" --out "$WD/lineup1.json"
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
assert d["points_table_dial"] == "fixture-v0"
print("ok: ordenação, pontos e anti-sockpuppet")
PY

# ═══ T2: determinismo byte-a-byte ═══
bash "$ROOT/bin/lineup-build.sh" --issues "$WD/issues.json" --export "$WD/export.json" --points "$WD/points.json" --out "$WD/lineup2.json"
cmp -s "$WD/lineup1.json" "$WD/lineup2.json" || fail "saída não é determinística byte-a-byte"
echo "ok: byte-determinismo"

# ═══ T3: issue duplicado entra UMA vez ═══
python3 -c "
import json
d = json.load(open('$WD/issues.json'))
d.append(d[0])
json.dump(d, open('$WD/issues-dup.json', 'w'))"
bash "$ROOT/bin/lineup-build.sh" --issues "$WD/issues-dup.json" --export "$WD/export.json" --points "$WD/points.json" --out "$WD/lineup3.json"
[ "$(grep -c '"handle"' "$WD/lineup3.json")" = "3" ] || fail "issue duplicado contou duas vezes"
echo "ok: issue única"

# ═══ T4: janela de conversão de referral (E6 4.5, atrás de dial) ═══
# @bruno foi indicado por @ana (primeiro signed run em 9d da conta →
# CONVERTE na janela de 30d); @carla por @duda (signed run em 45d →
# NÃO converte). Aqui duda EXISTE na fila (o T1 prova o caso dela
# ausente), então a decisão é da janela, não do no-origin.
cat > "$WD/issues-window.json" <<'ISSUESW'
[
  {"number": 12, "user": {"login": "bruno"}, "created_at": "2026-08-29T10:00:00Z",
   "body": "quero rodar meus agents\nreferred by: @ana\n- [x] consent: ok"},
  {"number": 10, "user": {"login": "ana"}, "created_at": "2026-08-28T09:00:00Z",
   "body": "benchmarks de vision\n- [x] consent: ok"},
  {"number": 15, "user": {"login": "carla"}, "created_at": "2026-08-30T08:00:00Z",
   "body": "sou dev\nreferred by: @duda\n- [x] consent: ok"},
  {"number": 11, "user": {"login": "duda"}, "created_at": "2026-08-27T08:00:00Z",
   "body": "rig antiga\n- [x] consent: ok"}
]
ISSUESW
cat > "$WD/export-window.json" <<'EXPORTW'
{"generated_at": "2026-08-30T12:00:00Z",
 "contributors": [{"handle": "@ana", "points": 4, "validated_runs": 2},
                  {"handle": "@duda", "points": 4, "validated_runs": 2}],
 "timeline": [
   {"handle": "@ana", "account_created_at": "2026-08-01T00:00:00+00:00",
    "first_signed_run_at": "2026-08-10T00:00:00+00:00"},
   {"handle": "@duda", "account_created_at": "2026-08-01T00:00:00+00:00",
    "first_signed_run_at": "2026-09-15T00:00:00+00:00"}]}
EXPORTW
cat > "$WD/points-window.json" <<'POINTSW'
{"dial": "fixture-e6-window",
 "points": {"join_issue": 1, "referral_converted": 3, "signed_run": 2,
            "run_reproduction": 3, "fake_caught": 5, "shared_custom_mode": 2},
 "referral_conversion": {"mode": "first_signed_run_within", "window_days": 30}}
POINTSW
bash "$ROOT/bin/lineup-build.sh" --issues "$WD/issues-window.json" --export "$WD/export-window.json" --points "$WD/points-window.json" --out "$WD/lineup4.json"
python3 - "$WD/lineup4.json" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
es = {e["handle"]: e for e in d["entries"]}
# ana: primeiro signed run em 9d da conta → referral de bruno CONVERTE
assert es["bruno"]["referral_converted"] is True, es["bruno"]
assert es["bruno"]["points_total"] == 1 + 3
# duda: signed run em 45d → FORA da janela de 30d
assert es["carla"]["referral_converted"] is False, es["carla"]
assert es["carla"]["points_total"] == 1
assert "fora da janela" in es["carla"]["referral_note"], es["carla"]
print("ok: janela de conversão (E6 4.5) atrás do dial")
PY

echo "test-lineup-machine: ok (4 casos)"
