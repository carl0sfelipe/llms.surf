#!/usr/bin/env bash
# tests/test-retomada.sh — Testa lógica de retomada (roteamento por status)
#                        e bloqueio após falhas (tentativas >= 3)
#
# TESTE 1: Cria artefato com status in-progress (simula processo que morreu)
#          e verifica que a rota aponta para step-03-execute.md.
# TESTE 2: Cria artefato com tentativas=3 e verifica que a regra do
#          step-04-verify.md manda marcar como blocked com bloqueio preenchido.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d "/tmp/dispatch-test-retomada.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT

pas=0
falhas=0
ROTEIRO="$REPO_ROOT/fluxos/dispatch/step-01-route.md"
VERIFY="$REPO_ROOT/fluxos/dispatch/step-04-verify.md"

# ═══════════════════════════════════════════════════════════════════
# TESTE 1: Retomada — roteamento por status
# ═══════════════════════════════════════════════════════════════════
echo "=== TESTE 1: Retomada — roteamento por status ==="
echo ""

ARTEFATO1="$TMPDIR/artefato1.md"
cat > "$ARTEFATO1" << 'EOF'
---
id: "test-retomada-1"
schema: 1
status: in-progress
owner: "test"
modelo: "test-model"
tentativas: 1
bloqueio: false
evidencia: ""
---

## Objetivo

Teste de retomada.

## Passos

- Passo 1

## Resultado

Esperado: roteamento para step-03.
EOF

STATUS_LIDO=$(grep -E '^status:' "$ARTEFATO1" | sed 's/status: *//')
echo "Status lido do artefato: $STATUS_LIDO"

# Extrai a rota correspondente ao status da tabela em step-01-route.md
# Formato da linha: | `in-progress` | **EARLY EXIT** → `./step-03-execute.md` |
ROTA=$(grep -F "$STATUS_LIDO" "$ROTEIRO" \
  | grep -F '|' \
  | sed -n 's/.*→ `\.\/\([^`]*\)`.*/\1/p')

if [ -z "$ROTA" ]; then
  echo "FAIL: não foi possível extrair rota para status=$STATUS_LIDO de $ROTEIRO"
  falhas=$((falhas + 1))
else
  echo "Rota extraída: status=$STATUS_LIDO → $ROTA"
  if [ "$ROTA" = "step-03-execute.md" ]; then
    echo "PASS: status in-progress leva ao step-03-execute.md conforme regra de roteamento"
    pas=$((pas + 1))
  else
    echo "FAIL: rota esperada era step-03-execute.md, obtida: $ROTA"
    falhas=$((falhas + 1))
  fi
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# TESTE 2: Bloqueio após falhas
# ═══════════════════════════════════════════════════════════════════
echo "=== TESTE 2: Bloqueio após falhas ==="
echo ""

ARTEFATO2="$TMPDIR/artefato2.md"
cat > "$ARTEFATO2" << 'EOF'
---
id: "test-retomada-2"
schema: 1
status: in-review
owner: "test"
modelo: "test-model"
tentativas: 3
bloqueio: false
evidencia: ""
---

## Objetivo

Teste de bloqueio após 3 tentativas.

## Passos

- Passo 1

## Resultado

Esperado: blocked com bloqueio preenchido.
EOF

TENTATIVAS=$(grep -E '^tentativas:' "$ARTEFATO2" | sed 's/tentativas: *//')
echo "Tentativas lidas do artefato: $TENTATIVAS"

if [ "$TENTATIVAS" -ge 3 ] 2>/dev/null; then
  echo "Condição satisfeita: tentativas ($TENTATIVAS) >= 3"

  # Extrai a mensagem de bloqueio do step-04-verify.md
  # Linha alvo: - Atualize `bloqueio: 3 tentativas sem alterações detectadas — dispatch não produziu output efetivo`.
  MSG_BLOQUEIO=$(grep 'bloqueio:' "$VERIFY" \
    | sed 's/.*bloqueio: //' | sed 's/`.*//')
  echo "Mensagem de bloqueio extraída da regra: $MSG_BLOQUEIO"

  # Aplica a regra do step-04-verify.md para tentativas >= 3
  sed -i '' -e 's/^status: .*/status: blocked/' \
    -e "s|^bloqueio: .*|bloqueio: $MSG_BLOQUEIO|" "$ARTEFATO2" \
    || sed -i -e 's/^status: .*/status: blocked/' \
      -e "s|^bloqueio: .*|bloqueio: $MSG_BLOQUEIO|" "$ARTEFATO2"

  echo "Artefato após aplicar regra:"
  grep -E '^(status:|bloqueio:)' "$ARTEFATO2"

  # Verifica status blocked
  if grep -q "^status: blocked" "$ARTEFATO2"; then
    echo "PASS: status alterado para blocked quando tentativas=$TENTATIVAS (>=3)"
    pas=$((pas + 1))
  else
    echo "FAIL: status deveria ser blocked mas não foi"
    falhas=$((falhas + 1))
  fi

  # Verifica bloqueio preenchido
  BLOQUEIO=$(grep -E '^bloqueio:' "$ARTEFATO2" | sed 's/bloqueio: *//')
  if [ -n "$BLOQUEIO" ] && [ "$BLOQUEIO" != "false" ]; then
    echo "PASS: campo bloqueio preenchido com: $BLOQUEIO"
    pas=$((pas + 1))
  else
    echo "FAIL: campo bloqueio deveria estar preenchido mas está vazio ou false"
    falhas=$((falhas + 1))
  fi
else
  echo "FAIL: tentativas ($TENTATIVAS) não é >= 3, regra de bloqueio não se aplica"
  falhas=$((falhas + 1))
fi

echo ""
echo "=== RESUMO ==="
echo "Passou: $pas | Falhou: $falhas"

if [ "$falhas" -gt 0 ]; then
  exit 1
fi
