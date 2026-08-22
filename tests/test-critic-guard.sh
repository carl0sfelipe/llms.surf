#!/usr/bin/env bash
# tests/test-critic-guard.sh — write-guard por papel (bin/critic-guard.sh).
#
# SIMULAÇÃO ADVERSARIAL dos incidentes godmode-btc de 2026-08-12: um critic
# "read-only" commitou o trabalho do builder e travou 2h04m sem teto. Antes
# do guard, TODOS estes cenários passavam em silêncio; agora cada um morre
# ou grita:
#  T1  arm arma a janela (hooksPath, identidade de janela) e check limpo
#      restaura e fecha (exit 0)
#  T2  ADVERSARIAL (a): critic tenta `git commit` na janela → hook recusa,
#      HEAD intacto; check devolve violação (exit 5) + incident automático
#  T3  ADVERSARIAL: commit com --no-verify fura o hook → check quarentena
#      (exit 4 por head_drift) e o commit rogue carrega a IDENTIDADE DE
#      JANELA no autor (atribuição mecânica, não por eliminação)
#  T4  allowlist: write em ring/verdicts/ (canal de veredito do ananke) NÃO
#      é drift — check limpo (sem falso positivo)
#  T5  ADVERSARIAL (a, canal run): write na árvore durante o dispatch → o
#      vigia MATA o dispatch em voo (exit 5) muito antes do fim natural
#  T6  ADVERSARIAL (canal run): tentativa de commit → hook marca violação e
#      o dispatch morre (exit 5), HEAD intacto
#  T7  ADVERSARIAL (c): dispatch dormindo estoura o teto → morto (exit 124)
#      + incident gravado sem intervenção humana
#  T8  run limpo: critic lê e escreve só no sandbox de notas → exit 0,
#      árvore intacta, guard_clean no ledger
#  T9  run repassa falha do critic (rc!=0) como exit 1 com árvore intacta
#  T10 arm duplo recusa (exit 1); check sem janela é quebrado (exit 2)
#  T11 ADVERSARIAL (c, canal Task): vigia com teto vencido grava incident e
#      sai 124 SEM humano; drift no canal Task também alarma (exit 5)
#  T12 arm --budget lança vigia em daemon (pidfile vivo) e check o derruba
#  T14 alvo worktree-com-ring (core.hooksPath --worktree do ring): o guard
#      arma no MESMO escopo — hook não é mascarado, commit do critic morre,
#      e o hooksPath do ring é restaurado no desarme
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$REPO_ROOT/bin/critic-guard.sh"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK=$(mktemp -d /tmp/test-critic-guard.XXXXXX)
export ORACFIT_GUARD_DIR="$WORK/guard"
export ORACFIT_CENTRAL_LEDGER="$WORK/central.jsonl"
export INCIDENTS_DIR="$WORK/incidents"
mkdir -p "$INCIDENTS_DIR"
trap 'rm -rf "$WORK"' EXIT

new_target() { # $1=nome → repo git com 1 commit, echo path
  local t="$WORK/$1"
  mkdir -p "$t"
  ( cd "$t" \
    && git init -q \
    && git config user.email owner@test.dev && git config user.name Owner \
    && echo hi > README.md && mkdir -p ring/verdicts && touch ring/verdicts/.keep \
    && git add -A && git commit -qm init ) >/dev/null
  echo "$t"
}

n_incidents() { find "$INCIDENTS_DIR" -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }

echo "=== test-critic-guard ==="

echo "--- T1: arm arma, check limpo restaura ---"
T=$(new_target t1)
bash "$GUARD" arm --target "$T" --task t1 >/dev/null 2>&1 || not "arm deveria passar"
hp=$(git -C "$T" config core.hooksPath || true)
case "$hp" in "$ORACFIT_GUARD_DIR"/*) ok "hooksPath aponta para a janela" ;; *) not "hooksPath errado: '$hp'" ;; esac
[ "$(git -C "$T" config user.name)" = "oracfit-critic-window(t1)" ] \
  && ok "identidade de janela aplicada" || not "identidade não trocada"
rc=0; bash "$GUARD" check --target "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "check limpo (rc=0)" || not "check limpo falhou (rc=$rc)"
[ "$(git -C "$T" config user.name)" = "Owner" ] \
  && ok "identidade restaurada" || not "identidade não restaurada: $(git -C "$T" config user.name)"
git -C "$T" config core.hooksPath >/dev/null 2>&1 \
  && not "hooksPath deveria voltar a <unset>" || ok "hooksPath restaurado (unset)"
grep -q '"event": "guard_clean"' "$ORACFIT_CENTRAL_LEDGER" \
  && ok "guard_clean no ledger central" || not "guard_clean ausente do ledger"

echo "--- T2: commit na janela → hook recusa, check acusa violação ---"
T=$(new_target t2)
head0=$(git -C "$T" rev-parse HEAD)
bash "$GUARD" arm --target "$T" --task t2 >/dev/null 2>&1
echo rogue > "$T/rogue.txt"
git -C "$T" add rogue.txt
rc=0; git -C "$T" commit -qm "critic commitando o trabalho do builder" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "commit do critic RECUSADO pelo hook (rc=$rc)" || not "hook deixou o critic commitar"
[ "$(git -C "$T" rev-parse HEAD)" = "$head0" ] && ok "HEAD intacto" || not "HEAD mudou"
inc0=$(n_incidents)
rc=0; bash "$GUARD" check --target "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] && ok "check devolve violação (rc=5)" || not "esperava rc=5, veio $rc"
[ "$(n_incidents)" -gt "$inc0" ] && ok "incident automático criado" || not "sem incident automático"
grep -q '"event": "guard_write_violation"' "$ORACFIT_CENTRAL_LEDGER" \
  && ok "guard_write_violation no ledger" || not "violação ausente do ledger"

echo "--- T3: --no-verify fura o hook → quarentena + autoria de janela ---"
T=$(new_target t3)
bash "$GUARD" arm --target "$T" --task t3 >/dev/null 2>&1
echo rogue > "$T/rogue.txt"
git -C "$T" add rogue.txt
git -C "$T" commit -q --no-verify -m "rogue por fora do hook" >/dev/null 2>&1 \
  || not "commit --no-verify deveria passar (é o cenário adversarial)"
autor=$(git -C "$T" log -1 --format='%an')
[ "$autor" = "oracfit-critic-window(t3)" ] \
  && ok "commit rogue carrega identidade de janela ('$autor')" \
  || not "atribuição perdida: autor='$autor'"
rc=0; bash "$GUARD" check --target "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 4 ] && ok "check quarentena por head_drift (rc=4)" || not "esperava rc=4, veio $rc"
grep -q '"event": "guard_quarantine"' "$ORACFIT_CENTRAL_LEDGER" \
  && ok "guard_quarantine no ledger" || not "quarentena ausente do ledger"

echo "--- T4: veredito em ring/verdicts/ não é drift (allowlist) ---"
T=$(new_target t4)
bash "$GUARD" arm --target "$T" --task t4 >/dev/null 2>&1
printf '{"verdict":"APPROVED","biggest_gap":"gap real"}' > "$T/ring/verdicts/RING-1.json"
rc=0; bash "$GUARD" check --target "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "write no canal de veredito fecha limpo (rc=0)" || not "falso positivo no allowlist (rc=$rc)"

echo "--- T5: canal run — write na árvore MATA o dispatch em voo ---"
T=$(new_target t5)
t0=$(date +%s)
rc=0
bash "$GUARD" run --target "$T" --task t5 --budget 60 --poll 1 -- \
  bash -c "echo hacked > '$T/hack.txt'; sleep 30" >/dev/null 2>&1 || rc=$?
t1=$(date +%s)
[ "$rc" -eq 5 ] && ok "dispatch morto com rc=5" || not "esperava rc=5, veio $rc"
[ $((t1 - t0)) -lt 15 ] && ok "morto em voo ($((t1 - t0))s, não esperou os 30s)" \
  || not "demorou $((t1 - t0))s — vigia não matou"
grep -q '"reason": "morto_em_voo"' "$ORACFIT_CENTRAL_LEDGER" \
  && ok "morto_em_voo no ledger" || not "motivo ausente do ledger"

echo "--- T6: canal run — tentativa de commit mata o dispatch, HEAD intacto ---"
T=$(new_target t6)
head0=$(git -C "$T" rev-parse HEAD)
rc=0
bash "$GUARD" run --target "$T" --task t6 --budget 60 --poll 1 -- \
  bash -c "cd '$T' && echo x > f.txt && git add f.txt && git commit -qm rogue; sleep 30" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] && ok "commit tentado → dispatch morto (rc=5)" || not "esperava rc=5, veio $rc"
[ "$(git -C "$T" rev-parse HEAD)" = "$head0" ] && ok "árvore sem commit (HEAD intacto)" || not "commit passou"

echo "--- T7: canal run — teto estourado mata + incident sem humano ---"
T=$(new_target t7)
inc0=$(n_incidents)
t0=$(date +%s)
rc=0
bash "$GUARD" run --target "$T" --task t7 --budget 2 --poll 1 -- sleep 30 >/dev/null 2>&1 || rc=$?
t1=$(date +%s)
[ "$rc" -eq 124 ] && ok "teto estourado (rc=124)" || not "esperava rc=124, veio $rc"
[ $((t1 - t0)) -lt 15 ] && ok "morto no teto ($((t1 - t0))s)" || not "não morreu no teto ($((t1 - t0))s)"
[ "$(n_incidents)" -gt "$inc0" ] && ok "incident automático do teto criado" || not "sem incident do teto"
grep -q '"event": "guard_timeout"' "$ORACFIT_CENTRAL_LEDGER" \
  && ok "guard_timeout no ledger" || not "timeout ausente do ledger"

echo "--- T8: canal run — critic limpo passa, notas no sandbox fora da árvore ---"
T=$(new_target t8)
rc=0
bash "$GUARD" run --target "$T" --task t8 --budget 60 --poll 1 -- \
  bash -c 'cat "$0/README.md" >/dev/null; echo finding > "$ORACFIT_CRITIC_NOTES_DIR/notas.md"' "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "run limpo (rc=0)" || not "run limpo falhou (rc=$rc)"
[ -z "$(git -C "$T" status --porcelain)" ] && ok "árvore intacta" || not "árvore suja"
[ ! -e "$T/notas.md" ] && ok "notas foram para o sandbox, não para a árvore" || not "notas caíram na árvore"

echo "--- T9: run repassa falha do critic com árvore intacta ---"
T=$(new_target t9)
rc=0; bash "$GUARD" run --target "$T" --task t9 --budget 60 --poll 1 -- false >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "falha do critic vira rc=1" || not "esperava rc=1, veio $rc"
grep -q '"event": "guard_dispatch_failed"' "$ORACFIT_CENTRAL_LEDGER" \
  && ok "guard_dispatch_failed no ledger" || not "falha ausente do ledger"

echo "--- T10: arm duplo recusa; check sem janela é quebrado ---"
T=$(new_target t10)
bash "$GUARD" arm --target "$T" --task t10 >/dev/null 2>&1
rc=0; bash "$GUARD" arm --target "$T" --task t10b >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "segundo arm recusado (rc=1)" || not "esperava rc=1, veio $rc"
bash "$GUARD" check --target "$T" >/dev/null 2>&1
rc=0; bash "$GUARD" check --target "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && ok "check sem janela é quebrado (rc=2)" || not "esperava rc=2, veio $rc"

echo "--- T11: vigia do canal Task — teto vencido e drift alarmam sem humano ---"
T=$(new_target t11)
SPAWN_WATCH=0 bash "$GUARD" arm --target "$T" --task t11 --budget 1 >/dev/null 2>&1
# forja janela vencida: armed_epoch 10s no passado
python3 -c "
import json, sys, hashlib
wid = hashlib.sha256('$T'.encode()).hexdigest()[:12]
p = '$ORACFIT_GUARD_DIR/' + wid + '/state.json'
d = json.load(open(p)); d['armed_epoch'] -= 10
json.dump(d, open(p, 'w'))"
inc0=$(n_incidents)
rc=0; bash "$GUARD" watch --target "$T" --interval 1 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 124 ] && ok "vigia sai 124 no teto vencido" || not "esperava rc=124, veio $rc"
[ "$(n_incidents)" -gt "$inc0" ] && ok "incident do canal Task criado sem humano" || not "sem incident do vigia"
# drift no canal Task: vigia pega write em voo
echo hacked > "$T/hack.txt"
rc=0; bash "$GUARD" watch --target "$T" --interval 1 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] && ok "vigia alarma drift (rc=5)" || not "esperava rc=5, veio $rc"
grep -q '"reason": "detectado_pelo_vigia"' "$ORACFIT_CENTRAL_LEDGER" \
  && ok "detecção do vigia no ledger" || not "vigia ausente do ledger"
rm -f "$T/hack.txt"
bash "$GUARD" check --target "$T" >/dev/null 2>&1 || true

echo "--- T12: arm --budget lança vigia em daemon e check derruba ---"
T=$(new_target t12)
bash "$GUARD" arm --target "$T" --task t12 --budget 60 --interval 1 >/dev/null 2>&1
WPID_FILE="$ORACFIT_GUARD_DIR/$(python3 -c "import hashlib;print(hashlib.sha256('$T'.encode()).hexdigest()[:12])")/watch.log.pid"
sleep 1
wpid=$(head -1 "$WPID_FILE" 2>/dev/null | tr -d '[:space:]')
if [ -n "$wpid" ] && kill -0 "$wpid" 2>/dev/null; then
  ok "vigia vivo em daemon (pid $wpid)"
else
  not "vigia não subiu (pidfile: $WPID_FILE)"
fi
bash "$GUARD" check --target "$T" >/dev/null 2>&1
sleep 1
if [ -n "$wpid" ] && kill -0 "$wpid" 2>/dev/null; then
  kill -KILL "$wpid" 2>/dev/null
  not "check não derrubou o vigia"
else
  ok "check derrubou o vigia"
fi

echo "--- T13: central resolvido do STATE do alvo, não do env (cápsula de daemon) ---"
# 2026-08-13: daemon do prime-agent herdou ORACFIT_CENTRAL_LEDGER de um
# terminal de smoke de ontem e desviou guard_armed/guard_clean para o
# ledger de debug. Alvo com ring/state.json declara o central — STATE vence.
T=$(new_target t13)
STATE_LEDGER="$WORK/central-do-state.jsonl"
python3 - "$T/ring/state.json" "$STATE_LEDGER" <<'EOF'
import json, sys
json.dump({"schema": "ring-state-v1", "central_ledger": sys.argv[2]}, open(sys.argv[1], "w"))
EOF
( cd "$T" && git add ring/state.json && git commit -qm state ) >/dev/null
bash "$GUARD" arm --target "$T" --task t13 >/dev/null 2>&1
bash "$GUARD" check --target "$T" >/dev/null 2>&1
if grep -q '"task": "t13"' "$STATE_LEDGER" 2>/dev/null; then
  ok "eventos do guard no central do STATE"
else
  not "eventos não foram para o central do state ($STATE_LEDGER)"
fi
if grep -q '"task": "t13"' "$ORACFIT_CENTRAL_LEDGER" 2>/dev/null; then
  not "eventos vazaram para o central do ENV (cápsula venceu)"
else
  ok "central do ENV intocado para alvo com state"
fi

echo "--- T14: alvo worktree-com-ring — hook do guard não é mascarado ---"
# débito 6 (2026-08-13): config --worktree vence --local; com o ring armando
# core.hooksPath --worktree (rodada 1), o guard armado em --local ficava com
# a camada de hook CEGA em alvo worktree. Simula o alvo como o ring o deixa.
WM="$WORK/t14-main"
mkdir -p "$WM"
( cd "$WM" \
  && git init -q \
  && git config user.email owner@test.dev && git config user.name Owner \
  && echo hi > README.md && mkdir -p ring/verdicts && touch ring/verdicts/.keep \
  && git add -A && git commit -qm init ) >/dev/null
WT="$WORK/t14-wt"
git -C "$WM" worktree add -q "$WT" -b t14-ring >/dev/null 2>&1
mkdir -p "$WT/ring/hooks"
printf '#!/bin/sh\nexit 0\n' > "$WT/ring/hooks/pre-commit"
chmod +x "$WT/ring/hooks/pre-commit"
git -C "$WT" config extensions.worktreeConfig true
git -C "$WT" config --worktree core.hooksPath "$WT/ring/hooks"
head0=$(git -C "$WT" rev-parse HEAD)
bash "$GUARD" arm --target "$WT" --task t14 >/dev/null 2>&1 || not "arm no worktree falhou"
hp=$(git -C "$WT" config core.hooksPath || true)   # valor EFETIVO, todos os escopos
case "$hp" in
  "$ORACFIT_GUARD_DIR"/*) ok "hooksPath efetivo aponta pro guard (não mascarado)" ;;
  *) not "guard MASCARADO no worktree: hooksPath efetivo='$hp'" ;;
esac
echo rogue > "$WT/rogue.txt"
git -C "$WT" add rogue.txt
rc=0; git -C "$WT" commit -qm "critic rogue no worktree" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "commit do critic no worktree RECUSADO pelo hook (rc=$rc)" \
  || not "hook do guard deixou o critic commitar no worktree"
[ "$(git -C "$WT" rev-parse HEAD)" = "$head0" ] && ok "HEAD do worktree intacto" || not "HEAD mudou"
git -C "$WT" reset -q rogue.txt 2>/dev/null; rm -f "$WT/rogue.txt"
rc=0; bash "$GUARD" check --target "$WT" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] && ok "check acusa a violação (rc=5)" || not "esperava rc=5, veio $rc"
hp_after=$(git -C "$WT" config --worktree core.hooksPath 2>/dev/null || true)
[ "$hp_after" = "$WT/ring/hooks" ] \
  && ok "hooksPath do ring restaurado no desarme" \
  || not "restore perdeu o hooksPath do ring: '$hp_after'"

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
