#!/bin/bash
# tests/test-spec-multi-oraculo.sh — 1 arquivo = 1 história + dados verificados EN.
#
# Incidente 2026-09-20-spec-com-n-oraculos-despacha-so-o-primei: spec com N
# seções ## Oráculo despachava só a primeira em silêncio (extração
# first-match em gauntlet/preflight/check-oracle.py). Agora o preflight e o
# check-oracle.py RECUSAM antes de gastar token, e o check-spec avisa sem
# reprovar.
#
# Incidente 2026-09-20-heuristica-de-dados-verificados-so-casa-: a heurística
# de dados verificados só casava em português. Agora "Verified data" (EN)
# passa no gate e na extração de ground-truth.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/oracfit-multiorac.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$TMPDIR/work"; mkdir -p "$WORK"

# Spec EN mínima, 1 história — os dois idiomas da heurística no mesmo fixture.
cat >"$TMPDIR/single-en.md" <<'EOF'
## Goal
Ship the thing.

## Verified data (what the model MAY use — checked in-tree)

- target file: out.txt (to be created by the work)

Do not invent number, path or name beyond those listed above.
NEVER use declare const as a workaround — import for real.

## Oráculo

- comando: test -f out.txt && grep -q ok out.txt
- exit esperado: 0
EOF

# (1) check-spec aceita "## Verified data" (EN).
if bash "$REPO_ROOT/bin/check-spec.sh" "$TMPDIR/single-en.md" >/dev/null 2>&1; then
  ok "check-spec aceita seção 'Verified data' (EN)"
else
  bad "check-spec reprova '## Verified data' — heurística continua só-PT"
fi

# (2) extração de ground-truth acha a seção EN (compose P4).
GT="$(bash -c "source '$REPO_ROOT/bin/lib-oracfit-gauntlet.sh'; oracfit_gauntlet_extract_ground_truth '$TMPDIR/single-en.md'")"
if printf '%s' "$GT" | grep -q 'out.txt'; then
  ok "extração de ground-truth acha a seção 'Verified data' (EN)"
else
  bad "extração de ground-truth NÃO achou a seção EN (vazia: '$GT')"
fi

# (3) spec de 1 história segue despachável: check-oracle julga "falha pelo
#     motivo certo" (out.txt não existe — é o trabalho a fazer).
set +e
python3 "$REPO_ROOT/bin/check-oracle.py" "$TMPDIR/single-en.md" "$WORK" --quiet
RC_SINGLE=$?
set -e
if [ "$RC_SINGLE" = "0" ]; then
  ok "spec com 1 oráculo segue despachável (check-oracle exit 0)"
else
  bad "spec com 1 oráculo reprovada no check-oracle (exit $RC_SINGLE) — recusa nova está larga demais"
fi

# Spec com DUAS histórias: dois blocos ## Oráculo completos.
cat >"$TMPDIR/two-stories.md" <<'EOF'
## Verified data
- out.txt to be created

Nao invente alem do listado. NUNCA use declare const como workaround.

## Oráculo

- comando: test -f out.txt
- exit esperado: 0

## Objetivo da segunda história

Texto da segunda história.

## Oráculo

- comando: test -f out2.txt
- exit esperado: 0
EOF

# (4) check-oracle RECUSA a spec com 2 oráculos (exit 3, mensagem explícita).
set +e
python3 "$REPO_ROOT/bin/check-oracle.py" "$TMPDIR/two-stories.md" "$WORK" --quiet 2>"$TMPDIR/two-stderr.txt"
RC_TWO=$?
set -e
if [ "$RC_TWO" = "3" ] && grep -q "1 arquivo = 1 história" "$TMPDIR/two-stderr.txt"; then
  ok "check-oracle recusa 2 oráculos com aviso explícito (exit 3)"
else
  bad "check-oracle não recusou 2 oráculos como esperado (exit $RC_TWO)"
fi

# (5) preflight também recusa (é a porta do dispatch, antes de gastar token).
set +e
bash -c "source '$REPO_ROOT/bin/lib-oracfit-events.sh' 2>/dev/null || true; source '$REPO_ROOT/bin/lib-oracfit-preflight.sh'; oracfit_preflight '$TMPDIR/two-stories.md' '$WORK'" >"$TMPDIR/pf-stderr.txt" 2>&1
RC_PF=$?
set -e
if [ "$RC_PF" = "1" ] && grep -q "1 arquivo = 1 história" "$TMPDIR/pf-stderr.txt"; then
  ok "preflight recusa spec com 2 oráculos antes do modelo (exit 1 + hint)"
else
  bad "preflight não recusou 2 oráculos como esperado (exit $RC_PF)"
fi

# (6) check-spec não reprova a spec de 2 histórias — só avisa (autoria).
set +e
bash "$REPO_ROOT/bin/check-spec.sh" "$TMPDIR/two-stories.md" >"$TMPDIR/cs-out.txt" 2>&1
RC_CS=$?
set -e
if [ "$RC_CS" = "0" ] && grep -q "1 arquivo = 1 história" "$TMPDIR/cs-out.txt"; then
  ok "check-spec avisa (sem reprovar) spec com 2 oráculos"
else
  bad "check-spec deveria só avisar (exit $RC_CS, sem hint de N histórias)"
fi

echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
