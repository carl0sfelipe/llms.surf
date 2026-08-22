#!/bin/bash
# smoke-test.sh — Verifica disponibilidade de um modelo antes de despachar
# Uso: bin/smoke-test.sh [model_id]
# Sem model_id: usa env MODEL_ID; sem MODEL_ID: usa o primeiro modelo de $MODEL_REGISTRY.
#
# Env obrigatória: DISPATCH_RUNNER
# Env opcional: MODEL_ID, MODEL_REGISTRY (default: model-registry.json na raiz do repo)

set -uo pipefail

: "${DISPATCH_RUNNER:?Erro: env DISPATCH_RUNNER não definida. Aponte para adapters/<cli>/runner.sh.}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"

MODEL="${1:-${MODEL_ID:-}}"

if [ -z "$MODEL" ]; then
  if [ ! -f "$MODEL_REGISTRY" ]; then
    echo "❌ Erro: sem model_id (arg/env MODEL_ID) e MODEL_REGISTRY não encontrado: $MODEL_REGISTRY"
    exit 3
  fi
  MODEL=$(python3 -c "
import json
d = json.load(open('$MODEL_REGISTRY'))
models = d.get('models', [])
print(models[0]['id'] if models else '')
")
  if [ -z "$MODEL" ]; then
    echo "❌ Erro: $MODEL_REGISTRY não contém nenhum modelo"
    exit 3
  fi
fi

SPEC_FILE=$(mktemp)
printf 'responda apenas OK' > "$SPEC_FILE"

echo "🔍 Smoke test: $MODEL"

START=$(date +%s)
RESULT=$("$DISPATCH_RUNNER" "$MODEL" "$SPEC_FILE" 2>&1)
RUNNER_EXIT=$?
END=$(date +%s)
ELAPSED=$((END - START))
rm -f "$SPEC_FILE"

case "$RUNNER_EXIT" in
  2)
    echo "🚫 RATE LIMITED / SWITCH — modelo indisponível agora (exit runner=2)"
    exit 1
    ;;
  3)
    echo "❌ Erro de uso do runner (exit 3)"
    echo "   Output: $(echo "$RESULT" | tail -3)"
    exit 1
    ;;
  4)
    echo "🚫 Quota exausta (exit runner=4)"
    exit 1
    ;;
  1)
    echo "❌ FALHOU (${ELAPSED}s, exit runner=1)"
    echo "   Output: $(echo "$RESULT" | tail -3)"
    exit 1
    ;;
esac

if echo "$RESULT" | grep -qi "OK"; then
  if [ "$ELAPSED" -gt 10 ]; then
    echo "⚠️  OK mas LENTO (${ELAPSED}s) — rate limit provável, esperar 3min antes de despachar"
    exit 2
  else
    echo "✅ OK (${ELAPSED}s) — disponível"
    exit 0
  fi
else
  echo "❌ FALHOU (${ELAPSED}s) — output sem 'OK'"
  echo "   Output: $(echo "$RESULT" | tail -3)"
  exit 1
fi
