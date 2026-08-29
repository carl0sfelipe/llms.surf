#!/bin/bash
# tests/test-owner-question.sh — S8: a pergunta do dono no unlock_plan.
#
# O padrão medido em 2026-08-29: bloqueado em fato que só o dono tem, o
# estágio caro faz UMA pergunta com o garfo de consequências anexado e o
# run PAUSA (exit 7) em vez de queimar tentativas caras inventando. A
# resposta do dono entra por `oracfit resume` e o run retoma verde.
#
#   T1: pergunta válida pausa o run — exit 7, status owner_question,
#       pergunta no inbox, evento owner_question, NENHUMA tentativa além.
#   T2: oracfit resume <run_id> "<resposta>" retoma e fecha pass (exit 0),
#       resposta consumida (message_consumed).
#   T3: segunda pergunta no MESMO run_id é IGNORADA — uma pergunta por run;
#       depois dela o oráculo governa (o garfo não é escape do oráculo).
#   T4: owner-question.md malformado (sem garfo) não pausa — aviso no
#       stderr, oráculo decide, run passa normal.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ORACFIT_ROOT="$ROOT"
export DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh"
SPEC="$ROOT/tests/fixtures/oracfit-smoke-unlock-plan.md"

pas=0
falhas=0
ok()  { echo "PASS: $1"; pas=$((pas + 1)); }
not() { echo "FAIL: $1"; falhas=$((falhas + 1)); }

novo_wd() {
  local wd
  wd=$(mktemp -d "/tmp/oracfit-test-oq.XXXXXX")
  git -C "$wd" init -q
  git -C "$wd" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo "$wd"
}

run_id_of() {  # run_id_of <stdout-file>
  grep -oE 'run_id: [a-f0-9-]+' "$1" | head -1 | cut -d' ' -f2
}

# ═══ T1: pergunta válida pausa ═══
echo "=== T1: unlock bloqueado → pergunta com garfo → pausa (exit 7) ==="
WD1=$(novo_wd)
ORACFIT_WORKDIR="$WD1" ORACFIT_STUB_QUESTION=1 \
  bin/oracfit run unlock_plan "$SPEC" oq-t1 >"$WD1/.out" 2>"$WD1/.err"
rc=$?
RID1=$(run_id_of "$WD1/.out")
if [ "$rc" -eq 7 ] && [ -n "$RID1" ]; then
  ok "exit 7 com run_id"
else
  not "esperava exit 7, veio rc=$rc (out: $(tail -2 "$WD1/.out" 2>/dev/null))"
fi
EV="$WD1/.dispatch/logs/events.jsonl"
if grep -q '"type": *"owner_question"' "$EV" 2>/dev/null \
   && grep -q '"status": *"owner_question"\|status=owner_question' "$EV" 2>/dev/null; then
  ok "eventos owner_question + run_finished status=owner_question"
else
  not "eventos de pausa ausentes"
fi
if [ -f "$WD1/.dispatch/logs/inbox/${RID1}.question.md" ] \
   && grep -q '^pergunta: ' "$WD1/.dispatch/logs/inbox/${RID1}.question.md" \
   && [ "$(grep -cE '^se .+ -> ' "$WD1/.dispatch/logs/inbox/${RID1}.question.md")" -ge 2 ]; then
  ok "pergunta no inbox com garfo (>=2 linhas 'se ... -> ...')"
else
  not "pergunta ausente/malformada no inbox"
fi
# pausa acontece no attempt 1 do stage 1 — nenhuma tentativa cara além
_n_attempts="$(grep -c '"type": *"attempt_started"' "$EV" 2>/dev/null)"
if [ "${_n_attempts:-0}" -le 1 ]; then
  ok "uma única tentativa — nenhuma queimada adivinhando"
else
  not "mais de uma tentativa antes da pausa"
fi

# ═══ T2: resposta do dono retoma e fecha verde ═══
echo ""
echo "=== T2: oracfit resume com a resposta → pass (exit 0) ==="
ORACFIT_WORKDIR="$WD1" \
  bin/oracfit resume "$RID1" "se a oficial — siga o registry" >"$WD1/.out2" 2>"$WD1/.err2"
rc2=$?
if [ "$rc2" -eq 0 ] && grep -q 'status: pass' "$WD1/.out2"; then
  ok "resume multi-stage fecha pass"
else
  not "resume rc=$rc2 (err: $(tail -3 "$WD1/.err2" 2>/dev/null))"
fi
if grep -q '"type": *"message_consumed"' "$EV" 2>/dev/null; then
  ok "resposta consumida na spec do próximo attempt"
else
  not "message_consumed ausente — resposta não chegou ao modelo"
fi

# ═══ T3: segunda pergunta no mesmo run_id é ignorada ═══
echo ""
echo "=== T3: segunda pergunta NÃO pausa — uma por run_id ==="
ORACFIT_WORKDIR="$WD1" ORACFIT_STUB_QUESTION=1 \
  bin/oracfit resume "$RID1" "de novo, agora tentando perguntar" >"$WD1/.out3" 2>"$WD1/.err3"
rc3=$?
_oq_events="$(grep -c '"type": *"owner_question"' "$EV" 2>/dev/null || echo 0)"
if [ "$rc3" -eq 0 ] && [ "$_oq_events" -eq 1 ]; then
  ok "segunda pergunta ignorada; oráculo governou; pass"
else
  not "rc3=$rc3, owner_question events=$_oq_events (esperava 0 e 1)"
fi

# ═══ T4: malformada não pausa ═══
echo ""
echo "=== T4: pergunta sem garfo é ignorada com aviso ==="
WD4=$(novo_wd)
ORACFIT_WORKDIR="$WD4" ORACFIT_STUB_QUESTION=malformed \
  bin/oracfit run unlock_plan "$SPEC" oq-t4 >"$WD4/.out" 2>"$WD4/.err"
rc4=$?
if [ "$rc4" -eq 0 ] \
   && ! grep -q '"type": *"owner_question"' "$WD4/.dispatch/logs/events.jsonl" 2>/dev/null \
   && grep -q "malformado" "$WD4/.err"; then
  ok "sem pausa, aviso no stderr, run passou pelo oráculo"
else
  not "rc4=$rc4 — malformada deveria ser ignorada"
fi

rm -rf "$WD1" "$WD4"
echo ""
echo "resultado: $pas pass, $falhas fail"
[ "$falhas" -eq 0 ]
