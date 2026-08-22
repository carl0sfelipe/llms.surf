#!/usr/bin/env bash
# tests/test-ring-runner.sh — runner de anel v4 (bin/oracfit-ring.sh).
#
# Protege os mecanismos que os incidentes de 2026-08-12 provaram necessários:
#  T1  init cria scaffold commitado + hook
#  T2  open com anel aberto recusa (um anel por vez)
#  T3  close sem veredito recusa e CONTA tentativa no ledger
#  T4  veredito com biggest_gap vazio recusa (fail-closed, lib compartilhada)
#  T5  close verde: build commit + checkpoint commit + árvore LIMPA
#      (transação do satélite aion: ledger dentro do commit)
#  T6  ledger close tem schema fixo (schema=ring-v1, oracle.exit, verdict)
#  T7  hook pre-commit bloqueia commit fora do runner com anel aberto
#  T8  guarda monotônica: oráculo editado com anel aberto recusa close
#      sem DECLARACAO-ORACULO + oracle_change_approved
#  T9  teto de anéis: open além do ceiling recusa
#  T10 gate visual: diff tocando *.html sem screenshot recusa; com screenshot fecha
#  T11 score --real grava delta previsão×nota no ledger
#  T12 oráculo vermelho recusa close e anel continua aberto
#  T13 daemon start/status/stop sobrevive fora do grupo (double-fork)
#  T15 init em worktree NÃO vaza hook pro .git compartilhado do principal;
#      hook por-worktree (core.hooksPath --worktree) dispara no worktree
#  T16 init com identidade git efetiva vazia seta identidade local do run
#  T17 run id não colide entre alvos (minuto + slug do alvo + sufixo hex,
#      prefixo <mode>-YYYYMMDD intacto); evento do central carrega "target"
#  T18 recusa por árvore suja diagnostica artefato regenerável do oráculo
#      (__pycache__/*.pyc) sem deixar de recusar
#  T19 abort exige motivo não-vazio OU notes/<RING>.md — abort mudo recusa,
#      motivo vai pro ledger
#  T20 hook do alvo (commitlint) recusa o commit do init → init falha ALTO
#      com diagnóstico, nada fica staged em silêncio
#  T21 durações do oráculo em ms por rodada; rodada-espelho (cache do runner
#      de teste) marca retest_suspeito=true sem bloquear; rápido-nas-duas
#      não flagra
#  T22 hook do ring em worktree ENCADEIA o pre-commit alheio do repo (gate
#      do dono roda e o exit code dele é respeitado)
#  T23 DECLARACAO-ORACULO aceita heading markdown; recusa documenta o formato
#  T24 run id com sufixo discriminador; init recusa run id já presente no
#      central (colisão de granularidade de minuto — runs 0323/0347 2026-08-13)
#  T25 lock de dono: init/open sobre alvo com dono VIVO estrangeiro recusam
#      com mensagem clara; pid morto é adotado; lock ilegível é QUEBRADO
#      (incidente executor-duplicado-no-mesmo-worktree 2026-08-13)
#  T27 init recusa alvo com ring/ no .gitignore ANTES de escrever qualquer
#      coisa — nem run id no central (incidente ring-init-nao-atomico 2026-08-13)
#  T26 histórico de vereditos: round REJECTED snapshotado + evento verdict
#      no ledger ANTES da sobrescrita; rounds commitados no close verde
#      (gap aceito do A-3, run ananke-20260813-0011)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORACFIT="$REPO_ROOT/bin/oracfit"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK=$(mktemp -d /tmp/test-ring-runner.XXXXXX)
export ORACFIT_CENTRAL_LEDGER="$WORK/central.jsonl"
trap 'rm -rf "$WORK"' EXIT

new_target() { # $1=nome -> cria repo git com ring init pronto, echo path
  local t="$WORK/$1"
  mkdir -p "$t"
  ( cd "$t" \
    && git init -q \
    && git config user.email ring@test.dev && git config user.name RingTest \
    && echo hi > README.md && git add README.md && git commit -qm init \
    && "$ORACFIT" ring init --mode smoketest --target . --oracle-cmd "true" --ceiling 2 >/dev/null 2>&1 \
    && python3 -c "
import json
d = json.load(open('ring/state.json')); d['min_disk_gb'] = 0
json.dump(d, open('ring/state.json','w'))" \
    && ORACFIT_RING_COMMIT=1 git commit -qam "test: disk gate off" ) >/dev/null
  echo "$t"
}

good_verdict() { # $1=target $2=ring
  mkdir -p "$1/ring/verdicts" "$1/ring/notes"
  printf '{"verdict":"APPROVED","biggest_gap":"cobertura rasa no caminho de erro","owner_score_pred":4.8}' \
    > "$1/ring/verdicts/$2.json"
  echo "notas do executor" > "$1/ring/notes/$2.md"
}

echo "=== test-ring-runner ==="

echo "--- T1: init cria scaffold commitado + hook ---"
T=$(new_target t1)
if [ -f "$T/ring/state.json" ] && [ -x "$T/ring/oracle.sh" ] && [ -f "$T/ring/ledger.jsonl" ]; then
  ok "scaffold criado"
else
  not "scaffold incompleto"
fi
if [ -x "$T/.git/hooks/pre-commit" ] && grep -q oracfit-ring-guard "$T/.git/hooks/pre-commit"; then
  ok "hook instalado"
else
  not "hook ausente"
fi
if [ -z "$(git -C "$T" status --porcelain)" ]; then
  ok "scaffold commitado (árvore limpa pós-init)"
else
  not "init deixou árvore suja: $(git -C "$T" status --porcelain | head -3)"
fi

echo "--- T2: um anel por vez ---"
"$ORACFIT" ring open R-1 "primeiro" --target "$T" >/dev/null 2>&1 || not "open R-1 deveria passar"
rc=0; "$ORACFIT" ring open R-2 "segundo" --target "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "segundo open recusado (rc=1)" || not "segundo open deveria recusar (rc=$rc)"

echo "--- T3: close sem veredito recusa e conta tentativa ---"
rc=0; "$ORACFIT" ring close R-1 --target "$T" -- file.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "close sem veredito recusa (rc=1)" || not "esperava rc=1, veio $rc"
if grep -q '"event": "close_attempt"' "$T/ring/ledger.jsonl" \
   && grep -q '"reason": "verdict_ausente"' "$T/ring/ledger.jsonl"; then
  ok "tentativa contada no ledger com motivo"
else
  not "close_attempt não registrado"
fi

echo "--- T4: biggest_gap vazio recusa ---"
mkdir -p "$T/ring/verdicts" "$T/ring/notes"
printf '{"verdict":"APPROVED","biggest_gap":"","owner_score_pred":5}' > "$T/ring/verdicts/R-1.json"
echo n > "$T/ring/notes/R-1.md"
rc=0; "$ORACFIT" ring close R-1 --target "$T" -- file.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "gap vazio recusa (rc=1)" || not "esperava rc=1, veio $rc"

echo "--- T5: close verde é transacional ---"
good_verdict "$T" R-1
echo conteudo > "$T/file.txt"
rc=0; "$ORACFIT" ring close R-1 --target "$T" -- file.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "close verde (rc=0)" || not "close verde falhou (rc=$rc)"
n_commits=$(git -C "$T" log --oneline | grep -c "ring(R-1)")
[ "$n_commits" -eq 2 ] && ok "build + checkpoint commits" || not "esperava 2 commits ring(R-1), achou $n_commits"
if [ -z "$(git -C "$T" status --porcelain)" ]; then
  ok "pós-condição: árvore limpa"
else
  not "árvore suja pós-close"
fi
if git -C "$T" show --stat HEAD | grep -q "ring/ledger.jsonl"; then
  ok "ledger INCLUÍDO no commit de checkpoint (satélite aion fechado)"
else
  not "ledger fora do commit de checkpoint"
fi

echo "--- T6: schema fixo do ledger ---"
close_line=$(grep '"event": "close"' "$T/ring/ledger.jsonl" | head -1)
echo "$close_line" | python3 -c '
import json, sys
e = json.load(sys.stdin)
assert e["schema"] == "ring-v1", e
assert e["oracle"]["exit"] == 0 and e["oracle"]["runs"] >= 1
assert e["verdict"] == "APPROVED"
assert isinstance(e["owner_score_pred"], (int, float))
assert e["biggest_gap"].strip()
assert e["build_commit"]
' && ok "close com schema ring-v1 completo" || not "schema do close divergente: $close_line"
if grep -q '"event": "checkpoint_commit"' "$ORACFIT_CENTRAL_LEDGER"; then
  ok "hash do checkpoint no ledger central"
else
  not "checkpoint_commit ausente do central"
fi

echo "--- T7: hook bloqueia commit fora do runner ---"
"$ORACFIT" ring open R-2 "hook" --target "$T" >/dev/null 2>&1 || not "open R-2 falhou"
echo x > "$T/fora.txt"
git -C "$T" add fora.txt
rc=0; git -C "$T" commit -qm "fora do runner" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "commit fora do runner bloqueado" || not "hook deixou passar commit com anel aberto"
git -C "$T" reset -q fora.txt && rm -f "$T/fora.txt"

echo "--- T8: guarda monotônica do oráculo ---"
echo "# trave editada com anel aberto" >> "$T/ring/oracle.sh"
good_verdict "$T" R-2
echo t8 > "$T/t8.txt"
rc=0; "$ORACFIT" ring close R-2 --target "$T" -- t8.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "oráculo mudado sem declaração recusa (rc=1)" || not "esperava rc=1, veio $rc"
grep -q '"reason": "oraculo_mudou_sem_declaracao"' "$T/ring/ledger.jsonl" \
  && ok "motivo registrado no ledger" || not "motivo ausente"
# com DECLARACAO + aprovação do critic, fecha
printf 'notas\nDECLARACAO-ORACULO: trave ampliada, teste novo coberto\n' > "$T/ring/notes/R-2.md"
printf '{"verdict":"APPROVED","biggest_gap":"gap real","owner_score_pred":4.9,"oracle_change_approved":true}' \
  > "$T/ring/verdicts/R-2.json"
rc=0; "$ORACFIT" ring close R-2 --target "$T" -- t8.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "declaração + aprovação do critic fecham (rc=0)" || not "close declarado falhou (rc=$rc)"

echo "--- T9: teto de anéis ---"
rc=0; "$ORACFIT" ring open R-3 "estoura" --target "$T" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "open além do teto recusa (rc=1)" || not "teto não segurou (rc=$rc)"

echo "--- T10: gate visual por gatilho de diff ---"
V=$(new_target t10)
"$ORACFIT" ring open V-1 "tela" --target "$V" >/dev/null 2>&1
good_verdict "$V" V-1
echo "<html></html>" > "$V/index.html"
rc=0; "$ORACFIT" ring close V-1 --target "$V" -- index.html >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "diff visual sem screenshot recusa (rc=1)" || not "esperava rc=1, veio $rc"
grep -q '"reason": "visual_sem_screenshot"' "$V/ring/ledger.jsonl" \
  && ok "motivo visual no ledger" || not "motivo visual ausente"
mkdir -p "$V/ring/screens/V-1" && echo fake-png > "$V/ring/screens/V-1/tela.png"
rc=0; "$ORACFIT" ring close V-1 --target "$V" -- index.html >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "com screenshot fecha (rc=0)" || not "close visual falhou (rc=$rc)"

echo "--- T11: score --real grava calibração ---"
"$ORACFIT" ring score V-1 --real 4.0 --target "$V" >/dev/null 2>&1 \
  && grep -q '"event": "owner_score"' "$V/ring/ledger.jsonl" \
  && grep -q '"delta": -0.8' "$V/ring/ledger.jsonl" \
  && ok "owner_score com delta -0.8 no ledger" || not "score não gravou delta"

echo "--- T12: oráculo vermelho recusa close ---"
R=$(new_target t12)
( cd "$R" && printf '#!/usr/bin/env bash\nexit 1\n' > ring/oracle.sh \
  && ORACFIT_RING_COMMIT=1 git commit -qam "oracle vermelho" )
"$ORACFIT" ring open X-1 "vermelho" --target "$R" >/dev/null 2>&1
good_verdict "$R" X-1
rc=0; "$ORACFIT" ring close X-1 --target "$R" -- file.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "oráculo exit 1 recusa close (rc=1)" || not "esperava rc=1, veio $rc"
grep -q 'oraculo_vermelho_exit_1' "$R/ring/ledger.jsonl" \
  && ok "exit code do oráculo no ledger" || not "motivo do oráculo ausente"
[ "$(python3 -c "import json;print(json.load(open('$R/ring/state.json'))['current_ring'])")" = "X-1" ] \
  && ok "anel continua aberto após recusa" || not "anel fechou indevidamente"

echo "--- T14: teste novo dispara retest descorrelacionado ---"
RT=$(new_target t14)
"$ORACFIT" ring open RT-1 "retest" --target "$RT" >/dev/null 2>&1
good_verdict "$RT" RT-1
# convenção python test_*.py — achado do teste de campo A-1 (regex não cobria)
echo "def test_x(): pass" > "$RT/test_novo.py"
rc=0; "$ORACFIT" ring close RT-1 --target "$RT" -- test_novo.py >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || not "close com teste novo falhou (rc=$rc)"
runs=$(grep '"event": "close"' "$RT/ring/ledger.jsonl" | python3 -c "import json,sys;print(json.load(sys.stdin)['oracle']['runs'])")
[ "$runs" -ge 2 ] && ok "oráculo re-rodado ${runs}x com teste novo staged" \
  || not "retest não disparou (runs=$runs, esperava >=2)"

echo "--- T13: daemon start/status/stop ---"
DLOG="$WORK/daemon.log"
"$ORACFIT" daemon start "$DLOG" sleep 60 >/dev/null 2>&1
sleep 1
rc=0; "$ORACFIT" daemon status "$DLOG" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "daemon vivo após start" || not "daemon não subiu"
# macOS: ps -o sess não diferencia — compara process GROUP (kill -PGID do
# lançador não pode alcançar o daemon; era exatamente o modo de morte)
dpid=$(head -1 "$DLOG.pid" 2>/dev/null)
dpgid=$(ps -o pgid= -p "$dpid" 2>/dev/null | tr -d ' ' || true)
mypgid=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || true)
if [ -n "$dpid" ] && [ -n "$dpgid" ] && [ "$dpgid" != "$mypgid" ]; then
  ok "daemon fora do process group do lançador ($dpgid != $mypgid)"
else
  not "daemon no mesmo grupo do lançador (morreria com kill de grupo)"
fi
"$ORACFIT" daemon stop "$DLOG" >/dev/null 2>&1
rc=0; "$ORACFIT" daemon status "$DLOG" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "daemon morto após stop" || not "stop não matou (rc=$rc)"

echo "--- T15: init em worktree escopa hook por-worktree (não vaza pro principal) ---"
WM="$WORK/t15-main"
mkdir -p "$WM"
( cd "$WM" \
  && git init -q \
  && git config user.email ring@test.dev && git config user.name RingTest \
  && echo hi > README.md && git add README.md && git commit -qm init ) >/dev/null
WT="$WORK/t15-wt"
git -C "$WM" worktree add -q "$WT" -b t15-ring >/dev/null 2>&1
"$ORACFIT" ring init --mode smoketest --target "$WT" --oracle-cmd "true" --ceiling 2 >/dev/null 2>&1
python3 -c "
import json
d = json.load(open('$WT/ring/state.json')); d['min_disk_gb'] = 0
json.dump(d, open('$WT/ring/state.json','w'))"
( cd "$WT" && ORACFIT_RING_COMMIT=1 git commit -qam "test: disk gate off" ) >/dev/null 2>&1
# 1) hooks compartilhado do repo principal intocado (era o vazamento do run
#    ananke-20260813-0347: hook ia parar no common dir e pegava TODO checkout)
if [ ! -e "$WM/.git/hooks/pre-commit" ]; then
  ok "hook NÃO vazou pro .git/hooks do repo principal"
else
  not "hook vazou: $WM/.git/hooks/pre-commit"
fi
# 2) hook por-worktree instalado e apontado via core.hooksPath --worktree
wt_hookspath=$(git -C "$WT" config --worktree core.hooksPath 2>/dev/null || true)
if [ -n "$wt_hookspath" ] && [ -x "$wt_hookspath/pre-commit" ] \
   && grep -q oracfit-ring-guard "$wt_hookspath/pre-commit"; then
  ok "hook por-worktree em core.hooksPath ($wt_hookspath)"
else
  not "hook por-worktree ausente (hooksPath='$wt_hookspath')"
fi
if [ -z "$(git -C "$WM" config core.hooksPath 2>/dev/null || true)" ]; then
  ok "core.hooksPath do repo principal intocado"
else
  not "core.hooksPath vazou pro principal: $(git -C "$WM" config core.hooksPath)"
fi
if [ -z "$(git -C "$WT" status --porcelain)" ]; then
  ok "árvore do worktree limpa pós-init (ring/hooks commitado)"
else
  not "init em worktree deixou árvore suja: $(git -C "$WT" status --porcelain | head -3)"
fi
# 3) o hook DISPARA no worktree: anel aberto bloqueia commit fora do runner
"$ORACFIT" ring open W-1 "hook no worktree" --target "$WT" >/dev/null 2>&1 || not "open W-1 no worktree falhou"
echo x > "$WT/fora.txt"
git -C "$WT" add fora.txt
rc=0; git -C "$WT" commit -qm "fora do runner" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "hook dispara no worktree (commit fora do runner bloqueado)" \
  || not "hook não disparou no worktree"
# 4) o repo principal segue commitando livre (guard não alcança outras árvores)
rc=0; ( cd "$WM" && echo y > livre.txt && git add livre.txt && git commit -qm "principal livre" ) >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "repo principal commita livre com anel aberto no worktree" \
  || not "commit no repo principal bloqueado (rc=$rc)"

echo "--- T16: init seta identidade local quando a efetiva está vazia ---"
I="$WORK/t16"; NH="$WORK/t16-nohome"
mkdir -p "$I" "$NH"
( cd "$I" && git init -q ) >/dev/null 2>&1
# HOME/XDG vazios + NOSYSTEM: identidade efetiva do alvo fica vazia de verdade
HOME="$NH" XDG_CONFIG_HOME="$NH" GIT_CONFIG_NOSYSTEM=1 \
  "$ORACFIT" ring init --mode smoketest --target "$I" --oracle-cmd "true" >/dev/null 2>&1
if [ "$(git -C "$I" config --local user.name 2>/dev/null)" = "oracfit-ring" ] \
   && [ "$(git -C "$I" config --local user.email 2>/dev/null)" = "ring@oracfit.local" ]; then
  ok "identidade local do run gravada no alvo"
else
  not "identidade não setada (name='$(git -C "$I" config --local user.name 2>/dev/null)' email='$(git -C "$I" config --local user.email 2>/dev/null)')"
fi
author=$(git -C "$I" log -1 --format='%an <%ae>' 2>/dev/null || true)
[ "$author" = "oracfit-ring <ring@oracfit.local>" ] \
  && ok "commit de init com autoria do run" || not "autoria do init: '$author'"
# débito 8: o preflight não pode avisar sobre a identidade que o PRÓPRIO init
# setou de propósito — WARN a cada open treina executor a ignorar warning
pout=$(bash "$REPO_ROOT/bin/ring-preflight.sh" "$I" --min-disk-gb 0 2>&1); prc=$?
if [ "$prc" -eq 0 ] && ! printf '%s' "$pout" | grep -q "WARN: identidade"; then
  ok "preflight não avisa sobre a identidade do run"
else
  not "WARN contradiz o init (rc=$prc): $(printf '%s' "$pout" | grep -i identidade)"
fi
printf '%s' "$pout" | grep -q "identidade do run" \
  && ok "preflight nomeia a identidade do run" || not "identidade do run não reconhecida"
# identidade vazia DE VERDADE continua avisando (a exceção não engole o warn)
E="$WORK/t16-vazio"
mkdir -p "$E"
( cd "$E" && git init -q ) >/dev/null 2>&1
pout=$(HOME="$NH" XDG_CONFIG_HOME="$NH" GIT_CONFIG_NOSYSTEM=1 \
  bash "$REPO_ROOT/bin/ring-preflight.sh" "$E" --min-disk-gb 0 2>&1) || true
printf '%s' "$pout" | grep -q "WARN: identidade" \
  && ok "identidade vazia de verdade segue avisando" || not "warn sumiu para identidade vazia"

echo "--- T17: run id não colide entre alvos; evento do central carrega target ---"
# colisão real de 2026-08-13: dois inits no MESMO minuto (CanIRunIt e
# ai-usage-hub) geraram ananke-20260813-0347 nos DOIS e o central misturou
# os anéis. Agora: minuto + slug do alvo + sufixo hex — mesmo minuto, ids
# distintos.
CA=$(new_target t17a)
CB=$(new_target t17b)
run_a=$(python3 -c "import json;print(json.load(open('$CA/ring/state.json'))['run'])")
run_b=$(python3 -c "import json;print(json.load(open('$CB/ring/state.json'))['run'])")
[ -n "$run_a" ] && [ "$run_a" != "$run_b" ] \
  && ok "ids distintos ($run_a × $run_b)" || not "COLISÃO de run id: '$run_a'"
case "$run_a" in
  smoketest-20[0-9][0-9][01][0-9][0-3][0-9]-*) ok "prefixo <mode>-YYYYMMDD intacto (monitoração filtra startswith)" ;;
  *) not "prefixo quebrado: $run_a" ;;
esac
case "$run_a" in *-t17a-????) ok "slug do alvo no id" ;; *) not "slug ausente: $run_a" ;; esac
"$ORACFIT" ring open C-1 "target no evento" --target "$CA" >/dev/null 2>&1 || not "open C-1 falhou"
grep '"event": "open"' "$ORACFIT_CENTRAL_LEDGER" | tail -1 | RUN_A="$run_a" TGT_A="$CA" python3 -c "
import json, os, sys
e = json.load(sys.stdin)
assert e['run'] == os.environ['RUN_A'], e
assert e.get('target') == os.environ['TGT_A'], e
" && ok "open no central com run+target do alvo" || not "evento do central sem target correto"

echo "--- T18: árvore suja só de artefato regenerável ganha diagnóstico (e segue recusando) ---"
P="$WORK/t18"
mkdir -p "$P/pkg/__pycache__"
( cd "$P" \
  && git init -q \
  && git config user.email ring@test.dev && git config user.name RingTest \
  && echo x > pkg/mod.py && echo bytecode1 > pkg/__pycache__/mod.cpython-312.pyc \
  && git add -A && git commit -qm init ) >/dev/null
# o caso do ai-usage-hub: .pyc RASTREADO regenerado pelo pytest do oráculo
echo bytecode2 > "$P/pkg/__pycache__/mod.cpython-312.pyc"
out=$(bash "$REPO_ROOT/bin/ring-preflight.sh" "$P" --min-disk-gb 0 --require-clean 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "recusa continua fail-closed (rc=1)" || not "esperava rc=1, veio $rc"
printf '%s' "$out" | grep -q "artefato regenerado pelo oráculo" \
  && ok "diagnóstico de artefato presente" || not "diagnóstico ausente: $out"
printf '%s' "$out" | grep -q "pkg/__pycache__/mod.cpython-312.pyc" \
  && ok "candidato a .gitignore/untrack listado" || not "candidato não listado"
# sujeira MISTA (arquivo real junto) NÃO pode ganhar o diagnóstico
echo real > "$P/pkg/real.txt"
out=$(bash "$REPO_ROOT/bin/ring-preflight.sh" "$P" --min-disk-gb 0 --require-clean 2>&1); rc=$?
if [ "$rc" -eq 1 ] && ! printf '%s' "$out" | grep -q "artefato regenerado"; then
  ok "sujeira mista recusa SEM o diagnóstico (não mascara colisão real)"
else
  not "diagnóstico apareceu em sujeira mista (rc=$rc)"
fi

echo "--- T19: abort exige motivo ou notas (abort mudo é buraco de auditoria) ---"
AB=$(new_target t19)
"$ORACFIT" ring open A-1 "abortavel" --target "$AB" >/dev/null 2>&1 || not "open A-1 falhou"
rc=0; "$ORACFIT" ring abort A-1 --target "$AB" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "abort sem motivo e sem notas recusa (rc=1)" || not "esperava rc=1, veio $rc"
[ "$(python3 -c "import json;print(json.load(open('$AB/ring/state.json'))['current_ring'])")" = "A-1" ] \
  && ok "anel segue aberto após recusa" || not "anel fechou sem motivo registrado"
rc=0; "$ORACFIT" ring abort A-1 "hipotese refutada pelo oraculo" --target "$AB" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "abort com motivo aceita (rc=0)" || not "abort com motivo falhou (rc=$rc)"
grep -q '"reason": "hipotese refutada pelo oraculo"' "$AB/ring/ledger.jsonl" \
  && ok "reason no ledger" || not "reason ausente do ledger"
# ramo OU: sem motivo posicional mas com notes/<RING>.md existente aceita
"$ORACFIT" ring open A-2 "abortavel 2" --target "$AB" >/dev/null 2>&1 || not "open A-2 falhou"
mkdir -p "$AB/ring/notes"
echo "motivo escrito nas notas" > "$AB/ring/notes/A-2.md"
rc=0; "$ORACFIT" ring abort A-2 --target "$AB" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "abort sem motivo mas com notas aceita (rc=0)" || not "abort com notas falhou (rc=$rc)"
grep -q '"reason": "ver ring/notes/A-2.md"' "$AB/ring/ledger.jsonl" \
  && ok "reason aponta para as notas" || not "reason das notas ausente do ledger"

echo "--- T20: hook do alvo recusa o commit do init → falha ALTA, staging limpo ---"
# caso leadher (run ananke-20260813-0412): commitlint recusa type "ring", o
# || true engolia, e o 1º close recusava por staging_com_resto_alheio
CL="$WORK/t20"
mkdir -p "$CL"
( cd "$CL" \
  && git init -q \
  && git config user.email ring@test.dev && git config user.name RingTest \
  && echo hi > README.md && git add -A && git commit -qm init ) >/dev/null
cat > "$CL/.git/hooks/commit-msg" <<'HOOK'
#!/bin/sh
# simula commitlint: type "ring" fora do type-enum do repo
grep -qE '^ring[:(]' "$1" && { echo "commitlint: type 'ring' nao permitido" >&2; exit 1; }
exit 0
HOOK
chmod +x "$CL/.git/hooks/commit-msg"
out=$("$ORACFIT" ring init --mode smoketest --target "$CL" --oracle-cmd true 2>&1); rc=$?
[ "$rc" -ne 0 ] && ok "init falha ALTO (rc=$rc)" || not "init engoliu a recusa do hook (rc=0)"
printf '%s' "$out" | grep -q "commitlint/lefthook" \
  && ok "diagnóstico nomeia a hipótese do hook" || not "sem hipótese de hook no diagnóstico"
[ -z "$(git -C "$CL" diff --cached --name-only)" ] \
  && ok "nada ficou staged em silêncio" || not "staging sujo após init falho: $(git -C "$CL" diff --cached --name-only | head -3)"

echo "--- T21: durations_ms por rodada + rodada-espelho marca retest_suspeito ---"
# caso leadher: 2ª rodada "FULL TURBO" em 77ms — cache anula o anti-flake
RT2=$(new_target t21)
( cd "$RT2" \
  && printf '#!/usr/bin/env bash\nif [ ! -f .oracle-ran ]; then touch .oracle-ran; sleep 6; fi\nexit 0\n' > ring/oracle.sh \
  && ORACFIT_RING_COMMIT=1 git commit -qam "oracle com cache simulado" ) >/dev/null
"$ORACFIT" ring open S-1 "rodada espelho" --target "$RT2" >/dev/null 2>&1
good_verdict "$RT2" S-1
echo "def test_s(): pass" > "$RT2/test_cache.py"   # teste novo → retest dispara
rc=0; out=$("$ORACFIT" ring close S-1 --target "$RT2" -- test_cache.py 2>&1) || rc=$?
[ "$rc" -eq 0 ] && ok "close com espelho NÃO bloqueia (rc=0)" || not "close S-1 falhou (rc=$rc)"
close_line=$(grep '"event": "close"' "$RT2/ring/ledger.jsonl" | head -1)
vals=$(echo "$close_line" | python3 -c '
import json, sys
e = json.load(sys.stdin)
d = e["oracle"]["durations_ms"]
assert len(d) >= 2 and d[0] >= 5000 and d[1] * 10 < d[0], d
assert e["retest_suspeito"] is True, e
assert e["oracle"]["duration_s"] > 0, e
print("durations_ms=%s retest_suspeito=%s duration_s=%s" % (d, e["retest_suspeito"], e["oracle"]["duration_s"]))
' 2>&1) && ok "espelho no ledger: $vals" || not "flag de espelho ausente: $close_line"
printf '%s' "$out" | grep -q "retest descorrelacionado SUSPEITO" \
  && ok "WARN nomeia cache de runner" || not "sem WARN de espelho"
# oráculo rápido nas DUAS rodadas (T14, oracle `true`) não pode flagrar
grep '"event": "close"' "$RT/ring/ledger.jsonl" | head -1 | python3 -c '
import json, sys
e = json.load(sys.stdin)
assert e.get("retest_suspeito") is False, e
assert len(e["oracle"]["durations_ms"]) >= 2, e
' && ok "rápido nas duas rodadas: sem flag (T14)" || not "falso positivo de espelho no T14"

echo "--- T22: hook do ring encadeia o pre-commit alheio do repo (worktree) ---"
WM2="$WORK/t22-main"
mkdir -p "$WM2"
( cd "$WM2" \
  && git init -q \
  && git config user.email ring@test.dev && git config user.name RingTest \
  && echo hi > README.md && git add -A && git commit -qm init ) >/dev/null
cat > "$WM2/.git/hooks/pre-commit" <<HOOK
#!/bin/sh
# hook do DONO (simula lefthook): registra que rodou e respeita ALIEN_EXIT
echo ran >> "$WM2/alien-ran.log"
exit \${ALIEN_EXIT:-0}
HOOK
chmod +x "$WM2/.git/hooks/pre-commit"
WT2="$WORK/t22-wt"
git -C "$WM2" worktree add -q "$WT2" -b t22-ring >/dev/null 2>&1
"$ORACFIT" ring init --mode smoketest --target "$WT2" --oracle-cmd true --ceiling 2 >/dev/null 2>&1
python3 -c "
import json
d = json.load(open('$WT2/ring/state.json')); d['min_disk_gb'] = 0
json.dump(d, open('$WT2/ring/state.json','w'))"
( cd "$WT2" && ORACFIT_RING_COMMIT=1 git commit -qam "test: disk gate off" ) >/dev/null 2>&1
[ -s "$WM2/alien-ran.log" ] && ok "hook do dono rodou nos commits do próprio runner" \
  || not "chain não executou o hook do dono no init"
"$ORACFIT" ring open H-1 "chain" --target "$WT2" >/dev/null 2>&1 || not "open H-1 falhou"
echo x > "$WT2/fora.txt"
git -C "$WT2" add fora.txt
rc=0; git -C "$WT2" commit -qm "fora do runner" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "guard do ring dispara primeiro (anel aberto bloqueia)" \
  || not "ring guard não bloqueou com anel aberto"
"$ORACFIT" ring abort H-1 "teste de chain" --target "$WT2" >/dev/null 2>&1
n0=$(wc -l < "$WM2/alien-ran.log" | tr -d ' ')
rc=0; git -C "$WT2" commit -qm "livre com chain" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "sem anel aberto, commit passa pelo chain (rc=0)" || not "commit livre falhou (rc=$rc)"
n1=$(wc -l < "$WM2/alien-ran.log" | tr -d ' ')
[ "$n1" -gt "$n0" ] && ok "hook alheio RODOU via chain ($n0 → $n1)" || not "hook do dono não rodou via chain"
echo y > "$WT2/fora2.txt"
git -C "$WT2" add fora2.txt
rc=0; ALIEN_EXIT=1 git -C "$WT2" commit -qm "dono recusa" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "exit code do hook alheio propagado (commit recusado)" \
  || not "exit do hook do dono foi ignorado"

echo "--- T23: DECLARACAO-ORACULO aceita heading markdown; recusa documenta formato ---"
MD=$(new_target t23)
"$ORACFIT" ring open M-1 "declaracao em heading" --target "$MD" >/dev/null 2>&1 || not "open M-1 falhou"
echo "# trave editada" >> "$MD/ring/oracle.sh"
printf 'notas\n## DECLARACAO-ORACULO: trave apertada, teste novo coberto\n' > "$MD/ring/notes/M-1.md"
printf '{"verdict":"APPROVED","biggest_gap":"gap real","owner_score_pred":4.9,"oracle_change_approved":true}' \
  > "$MD/ring/verdicts/M-1.json"
echo m > "$MD/m.txt"
rc=0; "$ORACFIT" ring close M-1 --target "$MD" -- m.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "heading markdown de DECLARACAO fecha (rc=0)" || not "heading recusado (rc=$rc)"
"$ORACFIT" ring open M-2 "sem declaracao" --target "$MD" >/dev/null 2>&1 || not "open M-2 falhou"
echo "# trave editada 2" >> "$MD/ring/oracle.sh"
good_verdict "$MD" M-2
echo m2 > "$MD/m2.txt"
rc=0; out=$("$ORACFIT" ring close M-2 --target "$MD" -- m2.txt 2>&1) || rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "formato esperado"; then
  ok "recusa documenta o formato exato esperado"
else
  not "recusa sem documentação do formato (rc=$rc)"
fi

echo "--- T24: run id discriminado + recusa de colisão no central ---"
mk_bare_repo() { # $1=path — repo git SEM ring init
  mkdir -p "$1"
  ( cd "$1" && git init -q \
    && git config user.email ring@test.dev && git config user.name RingTest \
    && echo hi > README.md && git add README.md && git commit -qm init ) >/dev/null
}
TA="$WORK/t24a"; TB="$WORK/t24b"; TC="$WORK/t24c"
mk_bare_repo "$TA"; mk_bare_repo "$TB"; mk_bare_repo "$TC"
ORACFIT_RING_RUN_SUFFIX=aaaa "$ORACFIT" ring init --mode smoketest --target "$TA" --oracle-cmd "true" >/dev/null 2>&1 \
  || not "init A falhou"
ORACFIT_RING_RUN_SUFFIX=bbbb "$ORACFIT" ring init --mode smoketest --target "$TB" --oracle-cmd "true" >/dev/null 2>&1 \
  || not "init B falhou"
runA=$(python3 -c "import json;print(json.load(open('$TA/ring/state.json'))['run'])")
runB=$(python3 -c "import json;print(json.load(open('$TB/ring/state.json'))['run'])")
[ -n "$runA" ] && [ "$runA" != "$runB" ] \
  && ok "run ids distintos no mesmo minuto ($runA / $runB)" \
  || not "run ids colidiram ou vazios: '$runA' / '$runB'"
echo "$runA" | grep -qE -- '-[0-9a-f]{4}$' \
  && ok "sufixo de 4 hex no run id" || not "run id sem sufixo: $runA"
grep -q "\"event\": \"init\"" "$TA/ring/ledger.jsonl" \
  && grep -q "\"run\": \"$runA\".*\"target\": \"$TA\"" "$ORACFIT_CENTRAL_LEDGER" \
  && ok "evento init com target no ledger workdir e central" \
  || not "evento init ausente (workdir ou central)"
# colisão: semeia o central com um run id que o init de C vai gerar (sufixo
# forçado + minuto corrente). Retry se o minuto virar entre semear e initar.
t24_rc=""; t24_tries=0
while [ "$t24_tries" -lt 3 ]; do
  rm -rf "$TC/ring"
  m1=$(date +%Y%m%d-%H%M)
  printf '{"schema": "ring-v1", "run": "smoketest-%s-t24c-cafe", "event": "open", "target": "%s"}\n' "$m1" "$TB" \
    >> "$ORACFIT_CENTRAL_LEDGER"
  rc=0; ORACFIT_RING_RUN_SUFFIX=cafe "$ORACFIT" ring init --mode smoketest --target "$TC" --oracle-cmd "true" >/dev/null 2>"$WORK/t24c.err" || rc=$?
  m2=$(date +%Y%m%d-%H%M)
  if [ "$m1" = "$m2" ]; then t24_rc="$rc"; break; fi
  t24_tries=$((t24_tries + 1))   # minuto virou no meio — tenta de novo
done
if [ "$t24_rc" = "1" ]; then
  ok "init com run id já existente no central recusa (rc=1)"
else
  not "esperava rc=1 na colisão, veio '$t24_rc' (tries=$t24_tries)"
fi
grep -q "já existe no ledger central" "$WORK/t24c.err" \
  && ok "mensagem de colisão clara no stderr" || not "mensagem de colisão ausente"
[ ! -f "$TC/ring/state.json" ] \
  && ok "recusa não deixou scaffold pela metade" || not "init recusado deixou ring/state.json em $TC"
# corrida: dois inits VIVOS disputando o mesmo minuto+slug+sufixo — a reserva
# atômica (flock no critical section) garante exatamente 1 vencedor. O
# check-then-append em dois passos deixava os dois passarem (gap do critic
# do RING-1). Alvos com o MESMO basename (app) → mesmo slug no id fundido.
# Retry se o minuto virar no meio.
TD="$WORK/t24d/app"; TE="$WORK/t24e/app"
mk_bare_repo "$TD"; mk_bare_repo "$TE"
t24_race=""; t24_tries=0
while [ "$t24_tries" -lt 3 ]; do
  rm -rf "$TD/ring" "$TE/ring"
  m1=$(date +%Y%m%d-%H%M)
  ORACFIT_RING_RUN_SUFFIX=dddd "$ORACFIT" ring init --mode smoketest --target "$TD" --oracle-cmd "true" >/dev/null 2>&1 &
  p1=$!
  ORACFIT_RING_RUN_SUFFIX=dddd "$ORACFIT" ring init --mode smoketest --target "$TE" --oracle-cmd "true" >/dev/null 2>&1 &
  p2=$!
  rc1=0; rc2=0
  wait "$p1" || rc1=$?
  wait "$p2" || rc2=$?
  m2=$(date +%Y%m%d-%H%M)
  if [ "$m1" = "$m2" ]; then t24_race="$rc1:$rc2"; break; fi
  t24_tries=$((t24_tries + 1))   # minuto virou entre os dois — não é corrida real
done
case "$t24_race" in
  0:1|1:0) ok "corrida de inits com mesmo minuto+slug+sufixo: exatamente 1 vencedor ($t24_race)" ;;
  *) not "corrida deveria dar 1 vencedor + 1 recusa, veio '$t24_race' (tries=$t24_tries)" ;;
esac

echo "--- T25: lock de dono (executor duplicado no mesmo alvo) ---"
O=$(new_target t25)
# dono VIVO estrangeiro: forja o lock com o pid de um sleep de fundo
sleep 300 &
T25_FOREIGN=$!
t25_start=$(ps -o lstart= -p "$T25_FOREIGN" | sed 's/^ *//;s/ *$//')
python3 - "$O/ring/owner.lock" "$T25_FOREIGN" "$t25_start" <<'PYEOF'
import json, socket, sys
path, pid, start = sys.argv[1:4]
json.dump({"schema": "ring-owner-v1", "host": socket.gethostname(),
           "pid": int(pid), "pid_start": start, "run": "smoketest-forjado",
           "ts": "t25"}, open(path, "w"))
PYEOF
rc=0; "$ORACFIT" ring open O-1 "invasor" --target "$O" >/dev/null 2>"$WORK/t25a.err" || rc=$?
[ "$rc" -eq 1 ] && ok "open com dono vivo estrangeiro recusa (rc=1)" || not "esperava rc=1, veio $rc"
grep -q "OUTRO processo VIVO" "$WORK/t25a.err" \
  && ok "mensagem cita o dono vivo" || not "mensagem do dono ausente"
rc=0; "$ORACFIT" ring init --mode smoketest --target "$O" --oracle-cmd "true" >/dev/null 2>"$WORK/t25b.err" || rc=$?
[ "$rc" -eq 1 ] && ok "segundo init sobre alvo com dono vivo recusa (rc=1)" || not "esperava rc=1, veio $rc"
grep -q "OUTRO processo VIVO" "$WORK/t25b.err" \
  && ok "recusa do init com mensagem clara (não 'state já existe')" || not "mensagem clara ausente no init"
# dono morto: lock obsoleto é adotado e o open segue
kill "$T25_FOREIGN" 2>/dev/null; wait "$T25_FOREIGN" 2>/dev/null
rc=0; "$ORACFIT" ring open O-1 "retomada legítima" --target "$O" >/dev/null 2>"$WORK/t25c.err" || rc=$?
[ "$rc" -eq 0 ] && ok "lock de pid morto: posse assumida e open segue (rc=0)" || not "adoção falhou (rc=$rc)"
t25_newpid=$(python3 -c "import json;print(json.load(open('$O/ring/owner.lock'))['pid'])")
[ "$t25_newpid" != "$T25_FOREIGN" ] && ok "lock reescrito para o novo dono (pid $t25_newpid)" \
  || not "lock ainda aponta para o dono morto"
grep -q '"event": "owner_adopt"' "$O/ring/ledger.jsonl" \
  && ok "adoção auditada no ledger (owner_adopt)" || not "adoção silenciosa: sem owner_adopt no ledger"
git -C "$O" status --porcelain | grep -q owner.lock \
  && not "owner.lock aparece no porcelain (deveria estar no info/exclude)" \
  || ok "owner.lock invisível ao porcelain (info/exclude)"
# lock ilegível é QUEBRADO, não adotável
echo "{corrompido" > "$O/ring/owner.lock"
rc=0; "$ORACFIT" ring close O-1 --target "$O" -- README.md >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && ok "lock ilegível é QUEBRADO (rc=2, fail-closed)" || not "esperava rc=2, veio $rc"
# token de sessão: posse sobrevive a shell efêmero (pid do lock nem precisa
# ser ancestral) — e token errado com dono vivo estrangeiro recusa
E=$(new_target t25e)
sleep 300 &
T25E_FOREIGN=$!
t25e_start=$(ps -o lstart= -p "$T25E_FOREIGN" | sed 's/^ *//;s/ *$//')
python3 - "$E/ring/owner.lock" "$T25E_FOREIGN" "$t25e_start" <<'PYEOF'
import json, socket, sys
path, pid, start = sys.argv[1:4]
json.dump({"schema": "ring-owner-v1", "host": socket.gethostname(),
           "pid": int(pid), "pid_start": start, "token": "tok-legitimo",
           "run": "smoketest-efemero", "ts": "t25e"}, open(path, "w"))
PYEOF
rc=0; ORACFIT_RING_OWNER=tok-legitimo "$ORACFIT" ring open E-1 "sessão de shell efêmero" --target "$E" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "token igual = posse, mesmo com pid estrangeiro vivo (rc=0)" \
  || not "token igual deveria abrir (rc=$rc)"
rc=0; ORACFIT_RING_OWNER=tok-errado "$ORACFIT" ring close E-1 --target "$E" -- README.md >/dev/null 2>"$WORK/t25e.err" || rc=$?
[ "$rc" -eq 1 ] && grep -q "OUTRO processo VIVO" "$WORK/t25e.err" \
  && ok "token errado + dono vivo estrangeiro recusa (rc=1)" \
  || not "esperava rc=1 com mensagem de dono vivo, veio $rc"
kill "$T25E_FOREIGN" 2>/dev/null; wait "$T25E_FOREIGN" 2>/dev/null
# claim atômico no init: dois inits simultâneos num alvo VIRGEM (sufixos
# distintos — a reserva de run id não deduplica por target) → 1 vencedor.
# O `; exit $?` impede o exec-optimize do bash -c: cada init precisa de um
# PAI VIVO DISTINTO (duas sessões de verdade), senão ambos herdam o pid da
# suíte como dono e a posse é legitimamente a mesma.
F="$WORK/t25f"
mk_bare_repo "$F"
ORACFIT_RING_RUN_SUFFIX=f001 bash -c '"$1" ring init --mode smoketest --target "$2" --oracle-cmd true; exit $?' _ "$ORACFIT" "$F" >/dev/null 2>&1 &
q1=$!
ORACFIT_RING_RUN_SUFFIX=f002 bash -c '"$1" ring init --mode smoketest --target "$2" --oracle-cmd true; exit $?' _ "$ORACFIT" "$F" >/dev/null 2>&1 &
q2=$!
qrc1=0; qrc2=0
wait "$q1" || qrc1=$?
wait "$q2" || qrc2=$?
case "$qrc1:$qrc2" in
  0:*[!0]*|*[!0]*:0) ok "init duplo simultâneo em alvo virgem: exatamente 1 vencedor ($qrc1:$qrc2)" ;;
  *) not "init duplo deveria ter 1 vencedor e 1 recusa, veio $qrc1:$qrc2" ;;
esac
[ -f "$F/ring/state.json" ] && ok "o vencedor deixou o ring inicializado" || not "nenhum init completou"
# OWN por ANCESTRALIDADE no fluxo real: init direto da suíte (dono = este
# shell, vivo) e open em seguida DEVEM passar sem adoção — se is_ancestor
# regredir, o open recusa e este teste fica vermelho (antes, todo o resto da
# suíte só exercitava o caminho stale→adoção e uma regressão ficaria verde)
G="$WORK/t25g"
mk_bare_repo "$G"
"$ORACFIT" ring init --mode smoketest --target "$G" --oracle-cmd "true" >/dev/null 2>&1 \
  || not "init direto (dono vivo) falhou"
python3 -c "
import json
d = json.load(open('$G/ring/state.json')); d['min_disk_gb'] = 0
json.dump(d, open('$G/ring/state.json','w'))" \
  && ORACFIT_RING_COMMIT=1 git -C "$G" commit -qam "test: disk gate off"
t25g_pid=$(python3 -c "import json;print(json.load(open('$G/ring/owner.lock'))['pid'])")
rc=0; "$ORACFIT" ring open G-1 "dono vivo por ancestralidade" --target "$G" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "OWN por ancestralidade: open do próprio dono passa (rc=0)" \
  || not "open do dono vivo recusado (rc=$rc) — is_ancestor regrediu?"
grep -q '"event": "owner_adopt"' "$G/ring/ledger.jsonl" \
  && not "open do dono vivo caiu em adoção (deveria ser OWN)" \
  || ok "sem adoção: posse reconhecida, lock intacto"
[ "$(python3 -c "import json;print(json.load(open('$G/ring/owner.lock'))['pid'])")" = "$t25g_pid" ] \
  && ok "lock não foi reescrito no caminho OWN" || not "lock reescrito indevidamente"
# OWN por TOKEN no fluxo real: init num pai que MORRE (âncora morta), token
# capturado da linha de export que o próprio init imprime, reutilizado num
# comando posterior — posse continua, sem adoção
H="$WORK/t25h"
mk_bare_repo "$H"
bash -c '"$1" ring init --mode smoketest --target "$2" --oracle-cmd true; exit $?' _ "$ORACFIT" "$H" \
  >/dev/null 2>"$WORK/t25h.err" || not "init com pai efêmero falhou"
python3 -c "
import json
d = json.load(open('$H/ring/state.json')); d['min_disk_gb'] = 0
json.dump(d, open('$H/ring/state.json','w'))" \
  && ORACFIT_RING_COMMIT=1 git -C "$H" commit -qam "test: disk gate off"
t25h_tok=$(sed -n 's/.*export ORACFIT_RING_OWNER=//p' "$WORK/t25h.err" | head -1)
[ -n "$t25h_tok" ] && ok "init imprime a linha de export do token" || not "token não impresso pelo init"
rc=0; ORACFIT_RING_OWNER="$t25h_tok" "$ORACFIT" ring open H-1 "token real de init real" --target "$H" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "OWN por token real com âncora morta: open passa (rc=0)" \
  || not "token real não deu posse (rc=$rc)"
grep -q '"event": "owner_adopt"' "$H/ring/ledger.jsonl" \
  && not "token real caiu em adoção (deveria ser OWN)" \
  || ok "sem adoção: token é posse, não takeover"

echo "--- T26: histórico de vereditos (REJECTED→APPROVED preserva rounds) ---"
W=$(new_target t26)
"$ORACFIT" ring open W-1 "historia" --target "$W" >/dev/null 2>&1 || not "open W-1 falhou"
mkdir -p "$W/ring/verdicts" "$W/ring/notes"
printf '{"verdict":"REJECTED","biggest_gap":"faltou o caminho de erro","owner_score_pred":3.1}' \
  > "$W/ring/verdicts/W-1.json"
echo "notas" > "$W/ring/notes/W-1.md"
echo conteudo > "$W/w.txt"
rc=0; "$ORACFIT" ring close W-1 --target "$W" -- w.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "close com REJECTED recusa (rc=1)" || not "esperava rc=1, veio $rc"
[ -f "$W/ring/verdicts/W-1.round-1.json" ] \
  && grep -q '"verdict":"REJECTED"' "$W/ring/verdicts/W-1.round-1.json" \
  && ok "round 1 (REJECTED) snapshotado antes da validação" \
  || not "snapshot do round 1 ausente ou errado"
grep -q '"event": "verdict"' "$W/ring/ledger.jsonl" \
  && grep -q '"verdict": "REJECTED"' "$W/ring/ledger.jsonl" \
  && ok "evento verdict REJECTED no ledger do workdir" || not "evento verdict ausente"
grep -q '"verdict": "REJECTED"' "$ORACFIT_CENTRAL_LEDGER" \
  && ok "evento verdict REJECTED também no central (sobrevive sem commit)" \
  || not "evento verdict fora do central"
# recusa repetida do MESMO veredito não duplica round
rc=0; "$ORACFIT" ring close W-1 --target "$W" -- w.txt >/dev/null 2>&1 || rc=$?
[ -f "$W/ring/verdicts/W-1.round-2.json" ] \
  && not "dedupe falhou: mesmo veredito virou round-2" \
  || ok "dedupe: recusa repetida não multiplica round"
# round 2 (APPROVED, sobrescrevendo) fecha e preserva os dois rounds no git
printf '{"verdict":"APPROVED","biggest_gap":"gap real remanescente","owner_score_pred":4.8}' \
  > "$W/ring/verdicts/W-1.json"
rc=0; "$ORACFIT" ring close W-1 --target "$W" -- w.txt >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "close verde após sobrescrita (rc=0)" || not "close verde falhou (rc=$rc)"
n_rounds=$(git -C "$W" ls-files 'ring/verdicts/W-1.round-*.json' | wc -l | tr -d ' ')
[ "$n_rounds" -eq 2 ] && ok "2 rounds TRACKED no git ($n_rounds)" || not "esperava 2 rounds tracked, achou $n_rounds"
grep -q '"verdict":"REJECTED"' "$W/ring/verdicts/W-1.round-1.json" \
  && grep -q '"verdict":"APPROVED"' "$W/ring/verdicts/W-1.round-2.json" 2>/dev/null \
  && ok "REJECTED (round 1) e APPROVED (round 2) preservados" \
  || not "conteúdo dos rounds divergente"
t26_order=$(python3 - "$W/ring/ledger.jsonl" <<'PYEOF'
import json, sys
evs = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    e = json.loads(line)
    if e.get("ring") == "W-1" and e.get("event") in ("verdict", "close"):
        evs.append((e["event"], e.get("verdict")))
print("|".join("%s:%s" % t for t in evs))
PYEOF
)
[ "$t26_order" = "verdict:REJECTED|verdict:APPROVED|close:APPROVED" ] \
  && ok "ledger em ordem: verdict REJECTED → verdict APPROVED → close" \
  || not "ordem do ledger divergente: $t26_order"
# veredito presente + notes AUSENTES: a recusa não pode perder o veredito
# (gap do critic do RING-3: guarda notes_ausentes rodava antes do snapshot —
# critic que morre depois do veredito mas antes das notas perdia o round)
W2=$(new_target t26b)
"$ORACFIT" ring open W-2 "notas truncadas" --target "$W2" >/dev/null 2>&1 || not "open W-2 falhou"
mkdir -p "$W2/ring/verdicts"
printf '{"verdict":"REJECTED","biggest_gap":"critic caiu antes das notas","owner_score_pred":2.0}' \
  > "$W2/ring/verdicts/W-2.json"
echo conteudo > "$W2/w.txt"
t26b_out=$("$ORACFIT" ring close W-2 --target "$W2" -- w.txt 2>&1) \
  && not "close sem notas deveria recusar" || true
echo "$t26b_out" | grep -q "notes_ausentes" \
  && ok "recusa por notes_ausentes (rc!=0)" || not "razão inesperada: $t26b_out"
[ -f "$W2/ring/verdicts/W-2.round-1.json" ] \
  && ok "veredito preservado MESMO com notes ausentes (round-1 existe)" \
  || not "recusa por notas perdeu o veredito presente"
grep -q '"event": "verdict"' "$W2/ring/ledger.jsonl" \
  && ok "evento verdict no ledger mesmo na recusa por notas" \
  || not "evento verdict ausente na recusa por notas"
# recusa por TETO de tentativas também preserva o veredito (gap do critic
# round 2 do RING-3: a guarda de teto rodava antes do snapshot — veredito
# novo numa close acima do teto se perdia sem round nem evento)
W3=$(new_target t26c)
python3 -c "
import json
d = json.load(open('$W3/ring/state.json')); d['close_attempt_ceiling'] = 1
json.dump(d, open('$W3/ring/state.json','w'))"
( cd "$W3" && ORACFIT_RING_COMMIT=1 git commit -qam "test: teto 1" ) >/dev/null
"$ORACFIT" ring open W-3 "teto preserva" --target "$W3" >/dev/null 2>&1 || not "open W-3 falhou"
mkdir -p "$W3/ring/verdicts"
printf '{"verdict":"REJECTED","biggest_gap":"round na borda do teto","owner_score_pred":2.5}' \
  > "$W3/ring/verdicts/W-3.json"
echo conteudo > "$W3/w.txt"
"$ORACFIT" ring close W-3 --target "$W3" -- w.txt >/dev/null 2>&1 \
  && not "close 1 sem notas deveria recusar" || true
# teto (1/1) atingido; um veredito NOVO chega DEPOIS do teto
printf '{"verdict":"APPROVED","biggest_gap":"gap remanescente real","owner_score_pred":4.9}' \
  > "$W3/ring/verdicts/W-3.json"
t26c_out=$("$ORACFIT" ring close W-3 --target "$W3" -- w.txt 2>&1) \
  && not "close acima do teto deveria recusar" || true
echo "$t26c_out" | grep -q "teto" \
  && ok "recusa por teto de tentativas (rc!=0)" || not "razão inesperada: $t26c_out"
[ -f "$W3/ring/verdicts/W-3.round-2.json" ] \
  && grep -q '"verdict":"APPROVED"' "$W3/ring/verdicts/W-3.round-2.json" \
  && ok "veredito NOVO preservado MESMO acima do teto (round-2)" \
  || not "recusa por teto perdeu o veredito novo"
t26c_ev=$(grep -c '"event": "verdict"' "$W3/ring/ledger.jsonl")
[ "$t26c_ev" -eq 2 ] && ok "2 eventos verdict no ledger (um por round)" \
  || not "esperava 2 eventos verdict, achou $t26c_ev"
# TERCEIRO veredito distinto ainda acima do teto: round = próximo LIVRE,
# não tentativa+1 (achado do critic round 3: attempts congela acima do teto
# e o segundo veredito novo sobrescrevia o round anterior)
t26c_sha2=$(shasum -a 256 "$W3/ring/verdicts/W-3.round-2.json" | cut -d' ' -f1)
printf '{"verdict":"NEEDS_WORK","biggest_gap":"terceiro veredito na borda","owner_score_pred":3.9}' \
  > "$W3/ring/verdicts/W-3.json"
"$ORACFIT" ring close W-3 --target "$W3" -- w.txt >/dev/null 2>&1 \
  && not "close acima do teto deveria recusar (3º veredito)" || true
[ -f "$W3/ring/verdicts/W-3.round-3.json" ] \
  && grep -q '"verdict":"NEEDS_WORK"' "$W3/ring/verdicts/W-3.round-3.json" \
  && ok "3º veredito ganhou round-3 (próximo livre, sem clobber)" \
  || not "3º veredito não virou round-3"
[ "$(shasum -a 256 "$W3/ring/verdicts/W-3.round-2.json" | cut -d' ' -f1)" = "$t26c_sha2" ] \
  && ok "round-2 anterior INTACTO (sha inalterado)" \
  || not "round-2 foi sobrescrito pelo 3º veredito"

echo "--- T27: init recusa ring/ no .gitignore ANTES de escrever (incidente ring-init-nao-atomico) ---"
T27="$WORK/t27"; mkdir -p "$T27"
( cd "$T27" && git init -q \
  && git config user.email ring@test.dev && git config user.name RingTest \
  && echo hi > README.md && printf 'ring/\n' > .gitignore \
  && git add README.md .gitignore && git commit -qm init ) >/dev/null
T27_central_antes=$( [ -f "$ORACFIT_CENTRAL_LEDGER" ] && wc -l < "$ORACFIT_CENTRAL_LEDGER" || echo 0)
T27_out=$("$ORACFIT" ring init --mode smoketest --target "$T27" --oracle-cmd "true" 2>&1) \
  && not "init sobre ring/ ignorado deveria recusar" || true
echo "$T27_out" | grep -qi "ignore" \
  && ok "recusa aponta o ignore do alvo" || not "mensagem sem diagnóstico: $T27_out"
[ ! -e "$T27/ring" ] \
  && ok "nenhum scaffold escrito (recusa antes de criar)" \
  || not "init deixou ring/ pela metade: $(ls "$T27/ring" 2>/dev/null | tr '\n' ' ')"
T27_central_depois=$( [ -f "$ORACFIT_CENTRAL_LEDGER" ] && wc -l < "$ORACFIT_CENTRAL_LEDGER" || echo 0)
[ "$T27_central_antes" = "$T27_central_depois" ] \
  && ok "central ledger intocado (run id não reservado à toa)" \
  || not "init recusado ainda reservou run id no central"

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
