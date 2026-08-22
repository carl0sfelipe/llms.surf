#!/usr/bin/env bash
# tests/test-check-verdict.sh — contrato canônico de veredito (bin/check-verdict.py).
#
# Cada teste protege um incidente real:
#  T1  APPROVED completo passa (rc=0)
#  T2  arquivo ausente = QUEBRADO rc=2 (fail-closed, nunca aprova)
#  T3  JSON truncado = QUEBRADO rc=2 (t4-integrity-override: truncado aprovou)
#  T4  enum desconhecido = QUEBRADO rc=2 (veredito-sem-degrau: None passou)
#  T5  biggest_gap vazio/evasivo recusa rc=1 (t3-judge loop cego)
#  T6  score abaixo do mínimo recusa rc=1
#  T7  PASS_WITH_NOTES com finding critical não-resolvido recusa rc=1
#      (veredito-sem-degrau: severidade estruturada ignorada pelo gate)
#  T8  campo exigido vazio recusa rc=1
#  T9  REJECTED recusa rc=1 (não é quebrado — é falha contável)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO_ROOT/bin/check-verdict.py"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK=$(mktemp -d /tmp/test-check-verdict.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

check() { # $1=arquivo, resto=flags → echo rc
  local rc=0
  python3 "$CHECK" "$@" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

echo "=== test-check-verdict ==="

echo "--- T1: APPROVED completo passa ---"
printf '{"verdict":"APPROVED","biggest_gap":"caminho de erro sem teste","owner_score_pred":4.8}' > "$WORK/good.json"
[ "$(check "$WORK/good.json" --min-score 4.5)" -eq 0 ] && ok "rc=0" || not "deveria passar"

echo "--- T2: arquivo ausente = quebrado ---"
[ "$(check "$WORK/nao-existe.json")" -eq 2 ] && ok "rc=2 fail-closed" || not "esperava rc=2"

echo "--- T3: JSON truncado = quebrado ---"
printf '{"verdict":"APPROVED","biggest_gap":"corte no meio da fra' > "$WORK/trunc.json"
[ "$(check "$WORK/trunc.json")" -eq 2 ] && ok "rc=2 (truncado nunca aprova)" || not "esperava rc=2"

echo "--- T4: enum desconhecido = quebrado ---"
printf '{"verdict":"None","biggest_gap":"x","owner_score_pred":5}' > "$WORK/none.json"
[ "$(check "$WORK/none.json")" -eq 2 ] && ok "verdict=None é quebrado, não pass" || not "esperava rc=2"
printf '{"verdict":"aprovado","biggest_gap":"x","owner_score_pred":5}' > "$WORK/typo.json"
[ "$(check "$WORK/typo.json")" -eq 2 ] && ok "vocabulário derivado é quebrado" || not "esperava rc=2"

echo "--- T5: biggest_gap vazio/evasivo recusa ---"
printf '{"verdict":"APPROVED","biggest_gap":"","owner_score_pred":5}' > "$WORK/gap1.json"
[ "$(check "$WORK/gap1.json")" -eq 1 ] && ok "gap vazio rc=1" || not "esperava rc=1"
printf '{"verdict":"APPROVED","biggest_gap":"nenhuma","owner_score_pred":5}' > "$WORK/gap2.json"
[ "$(check "$WORK/gap2.json")" -eq 1 ] && ok "gap evasivo ('nenhuma') rc=1" || not "esperava rc=1"

echo "--- T6: score abaixo do mínimo recusa ---"
printf '{"verdict":"APPROVED","biggest_gap":"gap real","owner_score_pred":3.9}' > "$WORK/low.json"
[ "$(check "$WORK/low.json" --min-score 4.5)" -eq 1 ] && ok "score 3.9 < 4.5 rc=1" || not "esperava rc=1"
printf '{"verdict":"APPROVED","biggest_gap":"gap real","owner_score_pred":"alta"}' > "$WORK/nonnum.json"
[ "$(check "$WORK/nonnum.json" --min-score 4.5)" -eq 1 ] && ok "score não-numérico rc=1" || not "esperava rc=1"

echo "--- T7: critical não-resolvido derruba PASS_WITH_NOTES e APPROVED ---"
printf '{"verdict":"APPROVED","biggest_gap":"gap","owner_score_pred":5,"findings":[{"severity":"CRITICAL","note":"quebra"}]}' > "$WORK/crit.json"
[ "$(check "$WORK/crit.json")" -eq 1 ] && ok "APPROVED com critical aberto rc=1" || not "esperava rc=1"
printf '{"verdict":"APPROVED","biggest_gap":"gap","owner_score_pred":5,"findings":[{"severity":"CRITICAL","resolved":true}]}' > "$WORK/critok.json"
[ "$(check "$WORK/critok.json")" -eq 0 ] && ok "critical resolvido passa" || not "resolved:true deveria passar"

echo "--- T8: campo exigido vazio recusa ---"
printf '{"verdict":"APPROVED","biggest_gap":"gap","owner_score_pred":5,"buyer_value":""}' > "$WORK/req.json"
[ "$(check "$WORK/req.json" --require-field buyer_value)" -eq 1 ] && ok "campo exigido vazio rc=1" || not "esperava rc=1"

echo "--- T9: REJECTED é falha contável, não quebra ---"
printf '{"verdict":"REJECTED","biggest_gap":"faltou X","owner_score_pred":2}' > "$WORK/rej.json"
[ "$(check "$WORK/rej.json")" -eq 1 ] && ok "REJECTED rc=1" || not "esperava rc=1"

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
