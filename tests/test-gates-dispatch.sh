#!/usr/bin/env bash
# tests/test-gates-dispatch.sh — fase 5 do v4: gates nos modos DESPACHÁVEIS.
#
# Protege o fechamento dos path-gaps declarados no mapa-regras (12/37/39:
# "dispatch.sh e dispatch-escalate.sh chamados direto seguem sem gate") e o
# gate visual único (mesmo predicado do ring) no gauntlet do escalate:
#  T1  oracfit_visual_hits: default casa html/tsx, não casa py; override;
#      globs VAZIO desliga (paridade com visual_globs:[] do ring);
#      caminho de TESTE não é hit visual no default (incidente 2026-08-13),
#      mas globs custom são respeitados sem exclusão
#  T2  dispatch.sh direto recusa spec fraca (check-spec, exit 1) SEM chamar runner
#  T3  dispatch.sh direto recusa oráculo quebrado (check-oracle, exit 2) SEM runner
#  T4  dispatch-escalate.sh recusa spec fraca no preflight (exit 3) SEM modelo
#  T5  escalate: oráculo verde + diff tocando *.html sem screenshot → gate visual
#      reprova, gap VISION GATE REJECTED transportado ao feedback, run NÃO é sucesso
#  T6  escalate: GAUNTLET_VISUAL_GLOBS="" desliga o gate → mesmo diff fecha verde
#  T7  escalate: >=1 screenshot em GAUNTLET_SCREENS_DIR satisfaz (paridade ring)
#  T8  critic P3: biggest_gap evasivo ("none"/"n/a") vira vazio pelo vocabulário
#      canônico de bin/check-verdict.py — gap real passa intacto

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK=$(mktemp -d /tmp/test-gates-dispatch.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

export DISPATCH_USAGE_FEEDBACK=0

# workdir git com alvo que faz o oráculo FALHAR pelo motivo certo
new_workdir() { # $1=nome → echo path
  local w="$WORK/$1"
  mkdir -p "$w"
  ( cd "$w" && git init -q . \
    && git config user.email gates@test.dev && git config user.name GatesTest \
    && echo "not yet" > alvo.txt && git add -A && git commit -qm init ) >/dev/null
  echo "$w"
}

# spec mínima que passa check-spec + facts + check-oracle (validada à mão)
write_spec() { # $1=path [$2=oracle_cmd]
  local oracle="${2:-grep -q done alvo.txt}"
  cat > "$1" <<EOF
# Task: marcar alvo

Nao invente numero, prazo ou fonte alem dos listados.
NUNCA use declare const como workaround — importe de verdade.

## Dados verificados
- alvo.txt existe no workdir (verificado)

## Verificacao
VERIFICACAO: grep -q done alvo.txt

## Oráculo
- comando: $oracle
EOF
}

# runner fake: marca chamada, completa o trabalho e toca artefato visual
FAKE_RUNNER="$WORK/fake-runner.sh"
cat > "$FAKE_RUNNER" <<'EOF'
#!/bin/bash
echo "$1" >> "$FAKE_CALLS"
cd "${ORACFIT_WORKDIR:?}" || exit 1
echo done > alvo.txt
echo '<html>x</html>' > index.html
exit 0
EOF
chmod +x "$FAKE_RUNNER"

# critic fake no PATH: o loop de feedback do escalate chama `opencode` — o
# shim evita rede/modelo real e devolve o contrato JSON do critic P3
mkdir -p "$WORK/shim"
cat > "$WORK/shim/opencode" <<'EOF'
#!/bin/bash
echo '{"biggest_gap":"faltam screenshots da tela alterada","must_fix":["renderize e salve screenshot"],"pick":"oracle"}'
EOF
chmod +x "$WORK/shim/opencode"

# ── T1: predicado visual compartilhado ───────────────────────────────────────
echo "T1: oracfit_visual_hits (predicado único ring+gauntlet)"
T1_OUT=$(bash -c '
source "'"$REPO_ROOT"'/bin/lib-oracfit-preflight.sh"
printf "src/app.tsx\nmain.py\npages/index.html\n" | oracfit_visual_hits
')
if [ "$T1_OUT" = "src/app.tsx
pages/index.html" ]; then ok "default casa tsx+html e ignora py"; else not "default: [$T1_OUT]"; fi

T1_OVR=$(bash -c '
source "'"$REPO_ROOT"'/bin/lib-oracfit-preflight.sh"
printf "tela.qml\npages/index.html\n" | oracfit_visual_hits "*.qml"
')
if [ "$T1_OVR" = "tela.qml" ]; then ok "override de globs respeitado"; else not "override: [$T1_OVR]"; fi

T1_OFF=$(bash -c '
source "'"$REPO_ROOT"'/bin/lib-oracfit-preflight.sh"
printf "pages/index.html\n" | oracfit_visual_hits ""
echo "rc=$?"
')
if [ "$T1_OFF" = "rc=0" ]; then ok "globs vazio desliga sem rc fantasma"; else not "off: [$T1_OFF]"; fi

# caminho de teste não é hit visual (incidente 2026-08-13: diff test-only
# em .test.tsx exigia screenshot e travava o close do anel)
T1_TESTS=$(bash -c '
source "'"$REPO_ROOT"'/bin/lib-oracfit-preflight.sh"
printf "src/components/trading/TradeControls.hedge.test.tsx\nsrc/Button.tsx\ntests/foo.spec.ts\nsrc/Button.css\n__tests__/page.html\n" | oracfit_visual_hits
')
if [ "$T1_TESTS" = "src/Button.tsx
src/Button.css" ]; then ok "default exclui teste (.test.tsx, tests/, __tests__/) e mantém tsx/css normais"
else not "exclusão de teste: [$T1_TESTS]"; fi

# globs custom são a palavra do usuário: sem exclusão de teste
T1_CUSTOM=$(bash -c '
source "'"$REPO_ROOT"'/bin/lib-oracfit-preflight.sh"
printf "src/App.test.tsx\n" | oracfit_visual_hits "*.tsx"
')
if [ "$T1_CUSTOM" = "src/App.test.tsx" ]; then ok "globs custom não sofrem exclusão de teste"
else not "custom: [$T1_CUSTOM]"; fi

# ── T2: dispatch.sh direto recusa spec fraca sem chamar runner ───────────────
echo "T2: dispatch.sh — check-spec no caminho direto (regra 37)"
WD2=$(new_workdir t2)
echo "so um titulo, sem defesa" > "$WD2/spec-fraca.md"
export FAKE_CALLS="$WORK/t2-calls.txt"
rc=0
( cd "$WD2" && DISPATCH_RUNNER="$FAKE_RUNNER" LOG_DIR="$WORK/t2-logs" PID_DIR="$WORK/t2-pids" \
    bash "$REPO_ROOT/bin/dispatch.sh" test/fake spec-fraca.md t2 ) >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then ok "spec fraca recusada com exit 1"; else not "esperava exit 1, veio $rc"; fi
if [ ! -f "$FAKE_CALLS" ]; then ok "runner NÃO foi chamado (nenhum token gasto)"; else not "runner foi chamado com gate vermelho"; fi

# ── T3: dispatch.sh direto recusa oráculo quebrado ───────────────────────────
echo "T3: dispatch.sh — check-oracle no caminho direto (regra 39)"
WD3=$(new_workdir t3)
write_spec "$WD3/spec.md" "comando-inexistente-xyz alvo.txt"
export FAKE_CALLS="$WORK/t3-calls.txt"
rc=0
( cd "$WD3" && DISPATCH_RUNNER="$FAKE_RUNNER" LOG_DIR="$WORK/t3-logs" PID_DIR="$WORK/t3-pids" \
    bash "$REPO_ROOT/bin/dispatch.sh" test/fake spec.md t3 ) >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then ok "oráculo quebrado recusado com exit 2"; else not "esperava exit 2, veio $rc"; fi
if [ ! -f "$FAKE_CALLS" ]; then ok "runner NÃO foi chamado"; else not "runner chamado com oráculo quebrado"; fi

# ── T4: escalate recusa spec fraca no preflight ──────────────────────────────
echo "T4: dispatch-escalate.sh — preflight no caminho escalate (regras 37/39)"
WD4=$(new_workdir t4)
echo "sem defesa nenhuma" > "$WD4/spec-fraca.md"
export FAKE_CALLS="$WORK/t4-calls.txt"
rc=0
DISPATCH_RUNNER="$FAKE_RUNNER" DISPATCH_TIERS="test/fake" LOG_DIR="$WORK/t4-logs" \
  bash "$REPO_ROOT/bin/dispatch-escalate.sh" "$WD4/spec-fraca.md" t4 --workdir "$WD4" --max-per-tier 1 \
  >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 3 ]; then ok "preflight recusou com exit 3 (erro de uso)"; else not "esperava exit 3, veio $rc"; fi
if [ ! -f "$FAKE_CALLS" ]; then ok "nenhum modelo chamado"; else not "modelo chamado com gate vermelho"; fi

# ── T5: gate visual reprova sucesso do oráculo e transporta o gap ────────────
echo "T5: escalate — oráculo verde + html tocado sem screenshot ≠ sucesso"
WD5=$(new_workdir t5)
write_spec "$WD5/spec.md"
export FAKE_CALLS="$WORK/t5-calls.txt"
rc=0
PATH="$WORK/shim:$PATH" DISPATCH_RUNNER="$FAKE_RUNNER" DISPATCH_TIERS="test/fake" \
  LOG_DIR="$WORK/t5-logs" DISPATCH_CRITIC_TIMEOUT=10 \
  bash "$REPO_ROOT/bin/dispatch-escalate.sh" "$WD5/spec.md" t5 --workdir "$WD5" --max-per-tier 2 \
  > "$WORK/t5-out.txt" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then ok "run NÃO terminou em sucesso (rc=$rc)"; else not "gate visual decorativo: exit 0 com tela sem render"; fi
if grep -q 'VISION GATE REJECTED' "$WORK/t5-logs/t5-tier-1.visual.log" 2>/dev/null; then
  ok "veredito visual gravado no log da tentativa"
else not "sem VISION GATE REJECTED no visual.log"; fi
if grep -q 'VISION GATE REJECTED' "$WORK/t5-logs/t5.gauntlet-feedback.md" 2>/dev/null; then
  ok "gap visual transportado ao feedback do gauntlet"
else not "gap não chegou ao accum de feedback"; fi
if ! grep -q '"result":"success"' "$WORK/t5-logs/escalate-ledger.jsonl" 2>/dev/null; then
  ok "ledger sem sucesso fantasma"
else not "ledger registrou success com gate visual vermelho"; fi

# ── T6: GAUNTLET_VISUAL_GLOBS="" desliga deliberadamente ─────────────────────
echo "T6: escalate — gate visual desligado por globs vazio fecha verde"
WD6=$(new_workdir t6)
write_spec "$WD6/spec.md"
export FAKE_CALLS="$WORK/t6-calls.txt"
rc=0
GAUNTLET_VISUAL_GLOBS="" DISPATCH_RUNNER="$FAKE_RUNNER" DISPATCH_TIERS="test/fake" \
  LOG_DIR="$WORK/t6-logs" \
  bash "$REPO_ROOT/bin/dispatch-escalate.sh" "$WD6/spec.md" t6 --workdir "$WD6" --max-per-tier 1 \
  >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "sucesso com gate desligado (opt-out explícito)"; else not "esperava exit 0, veio $rc"; fi

# ── T7: screenshot presente satisfaz o gate (paridade com o ring) ────────────
echo "T7: escalate — >=1 screenshot em GAUNTLET_SCREENS_DIR fecha verde"
WD7=$(new_workdir t7)
write_spec "$WD7/spec.md"
mkdir -p "$WORK/t7-screens" && echo png > "$WORK/t7-screens/tela.png"
export FAKE_CALLS="$WORK/t7-calls.txt"
rc=0
GAUNTLET_SCREENS_DIR="$WORK/t7-screens" DISPATCH_RUNNER="$FAKE_RUNNER" DISPATCH_TIERS="test/fake" \
  LOG_DIR="$WORK/t7-logs" \
  bash "$REPO_ROOT/bin/dispatch-escalate.sh" "$WD7/spec.md" t7 --workdir "$WD7" --max-per-tier 1 \
  >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "sucesso com evidência visual presente"; else not "esperava exit 0, veio $rc"; fi

# ── T8: gap evasivo do critic cai para vazio (contrato canônico) ─────────────
echo "T8: critic P3 — biggest_gap evasivo rejeitado pelo vocabulário canônico"
T8_EVASIVE=$(bash -c '
source "'"$REPO_ROOT"'/bin/lib-oracfit-gauntlet.sh"
oracfit_gauntlet_parse_critic_json "{\"biggest_gap\":\"none\",\"must_fix\":[\"x\"],\"pick\":\"oracle\"}"
')
if printf '%s' "$T8_EVASIVE" | grep -q '"biggest_gap": *""'; then
  ok "gap 'none' virou vazio (heurística do oracle log prevalece)"
else not "gap evasivo passou: [$T8_EVASIVE]"; fi
T8_REAL=$(bash -c '
source "'"$REPO_ROOT"'/bin/lib-oracfit-gauntlet.sh"
oracfit_gauntlet_parse_critic_json "{\"biggest_gap\":\"CTA sem contraste no mobile\",\"must_fix\":[],\"pick\":\"bar\"}"
')
if printf '%s' "$T8_REAL" | grep -q 'CTA sem contraste'; then
  ok "gap real passa intacto"
else not "gap real perdido: [$T8_REAL]"; fi

echo ""
echo "── resultado: $pass PASS, $fail FAIL ──"
[ "$fail" -eq 0 ]
