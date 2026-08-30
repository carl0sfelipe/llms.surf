#!/bin/bash
# test-tuned-measure.sh — S10: a máquina de medição before/after no stub.
# Prova: roda os 2 lados das 5 specs, tudo no ledger com run_id; recusa
# rodada fantasma; relatório nomeia os run_ids. Sem rede.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ORACFIT_ROOT="$ROOT"
export DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh"
BASE_ID="deepseek-v4-flash-free"
TUNED_ID="tuned/teste-dominio-flash"

fail() { echo "FAIL: $*" >&2; exit 1; }

WD="$(mktemp -d /tmp/tuned-measure.XXXXXX)"
trap 'rm -rf "$WD"' EXIT
git -C "$WD" init -q
git -C "$WD" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

# 5 specs fixture: o molde da smoke normal (preflight-validado), oráculo
# de proof por rodada (o harness remove o proof antes de cada medição)
for i in 1 2 3 4 5; do
  cat > "$WD/spec-$i.md" <<'EOF'
# spec: tuned-measure-fixture — medição before/after (stub)

Fixture da S10: mede o CAMINHO (spec → runner → artefato → oráculo), não
capacidade de modelo. Bloco de fatos deliberadamente mínimo: só afirma o
que todo workdir de dispatch tem.

## Tarefa

Crie o arquivo `.dispatch/stub-proof` com exatamente 3 linhas:

    stub_ok
    model_id=<o identificador do modelo com que você foi lançado>
    spec=<o nome desta spec>

## Regras

Nao invente outro caminho, numero, prazo ou fato alem do listado abaixo.
Nao use declare const como workaround — artefato inexistente nao se
declara, se cria.

## Dados verificados

- Existe `.dispatch` no workdir — o dispatcher cria o diretório antes de
  qualquer preflight, em todo run.

## Oráculo

- comando: test -f .dispatch/stub-proof && grep -q stub_ok .dispatch/stub-proof
- exit esperado: 0 — antes do run, exit 1 sem stderr é o estado correto.

## Verificação

O oráculo precisa falhar pelo motivo certo em workdir vazio.

VERIFICACAO: grep -q "stub_ok" tests/test-tuned-measure.sh

## Barra

Referência nomeada: adapters/stub/runner.sh grava o MESMO artefato que o
modelo real deve gravar — stub e real julgados pelo mesmo oráculo.
EOF
done

# ═══ T1: as 10 rodadas existem e estão no ledger ═══
echo "=== T1: 5 specs × 2 lados, tudo no ledger ==="
if ! bash "$ROOT/bin/tuned-measure.sh" --base "$BASE_ID" --tuned "$TUNED_ID" \
      --mode normal --workdir "$WD" \
      --spec "$WD/spec-1.md" --spec "$WD/spec-2.md" --spec "$WD/spec-3.md" \
      --spec "$WD/spec-4.md" --spec "$WD/spec-5.md" >"$WD/.t1.out" 2>"$WD/.t1.err"; then
  fail "harness reprovou com tudo em ordem (stderr: $(tail -2 "$WD/.t1.err"))"
fi
REPORT="$(ls "$WD"/.dispatch/tuned-measure/*.json | head -1)"
[ -n "$REPORT" ] || fail "relatório não foi escrito"
[ "$(grep -c '"run_id": ""' "$REPORT")" = "0" ] || fail "relatório tem rodada sem run_id"
[ "$(grep -o '"ledger_ok": true' "$REPORT" | wc -l)" = "10" ] || fail "esperava 10 ledger_ok"
grep -q '"all_ledgered": true' "$REPORT" || fail "all_ledgered deveria ser true"
# run_ids distintos entre os lados (10 rodadas reais, não eco)
[ "$(grep -o '"run_id": "[a-f0-9-]*"' "$REPORT" | sort -u | wc -l)" = "10" ] \
  || fail "esperava 10 run_ids distintos"
# o ledger guarda o model_id certo em cada lado
[ "$(grep -c "\"model_id\": \"$BASE_ID\"" "$WD/.dispatch/ledger/mode.jsonl")" -ge 5 ] \
  || fail "ledger não tem as 5 rodadas do lado base"
[ "$(grep -c "\"model_id\": \"$TUNED_ID\"" "$WD/.dispatch/ledger/mode.jsonl")" -ge 5 ] \
  || fail "ledger não tem as 5 rodadas do lado tuned"
echo "ok: 10 rodadas, 10 run_ids distintos, model_id por lado no ledger"

# ═══ T2: rodada que não chega ao ledger = reprova (run fantasma) ═══
echo "=== T2: spec que falha no preflight vira run fantasma e reprova ==="
WD2="$(mktemp -d /tmp/tuned-measure2.XXXXXX)"
trap 'rm -rf "$WD" "$WD2"' EXIT
git -C "$WD2" init -q
git -C "$WD2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cp "$WD/spec-1.md" "$WD/spec-2.md" "$WD/spec-3.md" "$WD/spec-4.md" "$WD2/"
# a 5ª tem oráculo sempre-verde: preflight recusa (already-passes) →
# nenhuma linha no ledger → o harness tem que reprovar nomeando
for i in 1 2 3 4; do sed -i "s/spec-$i.md/spec-$i.md/" "$WD2/spec-$i.md" 2>/dev/null; done
cat > "$WD2/spec-5.md" <<'EOF'
# spec: tuned-measure-ghost — oráculo sempre verde reprova no preflight

## Tarefa

Nada a fazer: o oráculo abaixo já passa antes de qualquer run.

## Regras

Nao invente fato alem do listado abaixo.

## Dados verificados

- Existe `.dispatch` no workdir de dispatch.

## Oráculo

- comando: true
- exit esperado: 0 (sempre) — isto É a falha sob teste.

## Verificação

VERIFICACAO: grep -q "stub_ok" tests/test-tuned-measure.sh

## Barra

Referência nomeada: bin/tuned-measure.sh reprova run fantasma.
EOF
if bash "$ROOT/bin/tuned-measure.sh" --base "$BASE_ID" --tuned "$TUNED_ID" \
    --mode normal --workdir "$WD2" \
    --spec "$WD2/spec-1.md" --spec "$WD2/spec-2.md" --spec "$WD2/spec-3.md" \
    --spec "$WD2/spec-4.md" --spec "$WD2/spec-5.md" >"$WD2/.t2.out" 2>"$WD2/.t2.err"; then
  fail "harness passou com rodada fantasma (ledger faltando)"
fi
grep -q "SEM ledger" "$WD2/.t2.err" || fail "reprova mas não diz 'SEM ledger'"
echo "ok: run fantasma reprovado com aviso de ledger faltando"

# ═══ T3: N != 5 reprova no argumento ═══
echo "=== T3: N de specs é exatamente 5 (E2-D1) ==="
if bash "$ROOT/bin/tuned-measure.sh" --base "$BASE_ID" --tuned "$TUNED_ID" \
    --mode normal --workdir "$WD2" --spec "$WD2/spec-1.md" >/dev/null 2>&1; then
  fail "aceitou 1 spec (devia exigir 5)"
fi
echo "ok: N=5 exigido"

echo "test-tuned-measure: ok (3 casos)"
exit 0
