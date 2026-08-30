#!/bin/bash
# tests/test-single-flight-status.sh — S7: single-flight por workdir +
# veredito canônico por comando (regra 53, mecanismos 1–2).
#
#   T1: run A vivo (stub dormindo) ⇒ run B no MESMO workdir é RECUSADO
#       (exit 6, mensagem com pid do dono e caminho do lock, sem ensinar
#       remoção forçada — espírito da regra 47), e não deixa rastro de task.
#   T2: A termina verde sozinho e o lock é liberado.
#   T3: oracfit status --task devolve o veredito CANÔNICO do run mais
#       recente da task (JSON: run_id, status, attempts, last_oracle_exit);
#       task desconhecida ⇒ not_found + exit 3.
#   T4: lock órfão de pid MORTO é assumido, não recusado (run morto não
#       segura workdir para sempre — incidente 2026-08-27).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WD="$(mktemp -d /tmp/oracfit-sf.XXXXXX)"
cleanup() { [ -n "${A_PID:-}" ] && kill "$A_PID" 2>/dev/null; rm -rf "$WD"; }
trap cleanup EXIT

git -C "$WD" init -q
git -C "$WD" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export ORACFIT_ROOT="$ROOT"
export DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh"
export ORACFIT_WORKDIR="$WD"
SPEC="$ROOT/tests/fixtures/oracfit-smoke-normal.md"

pas=0
falhas=0
ok()  { echo "PASS: $1"; pas=$((pas + 1)); }
not() { echo "FAIL: $1"; falhas=$((falhas + 1)); }

# ═══ T1: B recusado enquanto A está vivo ═══
echo "=== T1: segundo dispatch no mesmo workdir é recusado (exit 6) ==="
ORACFIT_STUB_SLEEP=6 bin/oracfit run normal "$SPEC" task-A >"$WD/.a.out" 2>"$WD/.a.err" &
A_PID=$!
sleep 2  # A está dentro do runner (dormindo), lock garantidamente seguro
ORACFIT_STUB_SLEEP=0 bin/oracfit run normal "$SPEC" task-B >"$WD/.b.out" 2>"$WD/.b.err"
B_RC=$?
if [ "$B_RC" -eq 6 ]; then
  ok "run B recusado com exit 6"
else
  not "run B deveria sair 6, saiu $B_RC"
fi
if grep -q "run vivo neste workdir" "$WD/.b.err" && grep -qE "pid dono [0-9]+" "$WD/.b.err" \
   && grep -q "run-lock" "$WD/.b.err"; then
  ok "recusa nomeia pid do dono e caminho do lock"
else
  not "mensagem de recusa incompleta: $(tail -2 "$WD/.b.err")"
fi
if grep -qiE "rm -rf|force|apague o lock|delete the lock" "$WD/.b.err"; then
  not "recusa ENSINA remoção forçada (viola espírito da regra 47)"
else
  ok "recusa não ensina remoção forçada (regra 47)"
fi
if ! ls "$WD/.dispatch/logs/inbox/" 2>/dev/null | grep -q "task-B"; then
  ok "recusa não deixou rastro (nenhuma task-B persistida)"
else
  not "run recusado persistiu state de task-B"
fi

# ═══ T2: A termina verde e libera o lock ═══
echo ""
echo "=== T2: A termina verde sozinho; lock liberado ==="
wait "$A_PID"
A_RC=$?
if [ "$A_RC" -eq 0 ] && grep -q "status: pass" "$WD/.a.out"; then
  ok "run A fechou pass (exit 0)"
else
  not "run A rc=$A_RC (err: $(tail -3 "$WD/.a.err"))"
fi
if [ ! -e "$WD/.dispatch/.run-lock" ]; then
  ok "lock liberado no fim do run"
else
  not "lock sobrou depois do run terminar"
fi

# ═══ T3: status --task é o veredito canônico ═══
echo ""
echo "=== T3: oracfit status --task devolve o veredito canônico ==="
A_RUN_ID="$(grep -oE 'run_id: [a-f0-9-]+' "$WD/.a.out" | head -1 | cut -d' ' -f2)"
ST="$(bin/oracfit status --task task-A)"
ST_RC=$?
if [ "$ST_RC" -eq 0 ] && printf '%s' "$ST" | grep -q '"status": *"pass"' \
   && printf '%s' "$ST" | grep -q "\"run_id\": *\"$A_RUN_ID\""; then
  ok "status --task task-A → JSON com run_id e status pass do run certo"
else
  not "status --task: rc=$ST_RC out='$ST' (esperava run_id=$A_RUN_ID pass)"
fi
printf '%s' "$ST" | grep -q '"attempts"' && printf '%s' "$ST" | grep -q '"last_oracle_exit"' \
  && ok "JSON traz attempts e last_oracle_exit" \
  || not "JSON sem attempts/last_oracle_exit"
bin/oracfit status --task task-inexistente >"$WD/.nf.out" 2>/dev/null
NF_RC=$?
if [ "$NF_RC" -eq 3 ] && grep -q '"status": *"not_found"' "$WD/.nf.out"; then
  ok "task desconhecida → not_found + exit 3"
else
  not "task desconhecida: rc=$NF_RC out=$(cat "$WD/.nf.out")"
fi
# a task RECUSADA (T1) não existe — recusa não é run
bin/oracfit status --task task-B >/dev/null 2>&1
[ $? -eq 3 ] && ok "task-B (recusada) é not_found — recusa não conta como run" \
               || not "task recusada aparece como run"

# ═══ T4: lock órfão de pid morto é assumido ═══
echo ""
echo "=== T4: lock órfão (pid morto) é assumido, não recusado ==="
sleep 0.1 & DEAD=$!; wait "$DEAD"  # pid garantidamente morto
# prova do run A removida: o gate de frescor (regra 39) reprovaria "oráculo
# já passa" — o cenário aqui é lock órfão, não trabalho já feito.
rm -f "$WD/.dispatch/stub-proof"
mkdir -p "$WD/.dispatch/.run-lock"
printf '%s\n' "$DEAD" >"$WD/.dispatch/.run-lock/pid"
if bin/oracfit run normal "$SPEC" task-C >"$WD/.c.out" 2>"$WD/.c.err" && grep -q "status: pass" "$WD/.c.out" \
   && grep -q "lock órfão" "$WD/.c.err"; then
  ok "run C assumiu o lock órfão e fechou pass"
else
  not "lock órfão não foi assumido (rc/out: $(tail -2 "$WD/.c.out") $(tail -2 "$WD/.c.err"))"
fi

echo ""
echo "resultado: $pas pass, $falhas fail"
[ "$falhas" -eq 0 ]
