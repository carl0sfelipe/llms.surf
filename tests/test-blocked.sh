#!/bin/bash
# tests/test-blocked.sh — Testa se artefato fica com status: blocked quando watchdog mata por silêncio.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/dispatch-test-blocked.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

LOG_DIR="$TMPDIR/logs"
PID_DIR="$TMPDIR/pids"
ARTEFATO="$TMPDIR/artefato.md"
FAKE_RUNNER="$TMPDIR/fake-runner.sh"
SPEC_FILE="$TMPDIR/spec.md"

mkdir -p "$LOG_DIR" "$PID_DIR"

cat > "$ARTEFATO" << 'EOF'
---
id: "test-artefact"
schema: 1
status: in-progress
owner: "test"
modelo: "test-model"
tentativas: 1
bloqueio: false
evidencia: ""
---

## Objetivo

Teste de bloqueio por watchdog.

## Passos

- Passo 1

## Resultado

Esperado: artefato com status blocked.
EOF

cat > "$FAKE_RUNNER" << 'EOF'
#!/bin/bash
sleep 300
EOF
chmod +x "$FAKE_RUNNER"

# Desde 2026-08-13 (fase 5 do v4) o dispatch.sh roda oracfit_preflight ANTES
# de despachar: a spec tem de passar check-spec + facts + check-oracle, e o
# oráculo tem de FALHAR pelo motivo certo no workdir. A fixture antiga
# ("# spec de teste") era recusada no gate e o watchdog nunca nascia.
echo "not yet" > "$TMPDIR/alvo.txt"
cat > "$SPEC_FILE" << 'EOF'
# Task: marcar alvo (fixture do teste de watchdog)

Nao invente numero, prazo ou fonte alem dos listados.
NUNCA use declare const como workaround — importe de verdade.

## Dados verificados
- alvo.txt existe no workdir (verificado)

## Verificacao
VERIFICACAO: grep -q done alvo.txt

## Oráculo
- comando: grep -q done alvo.txt
EOF

( cd "$TMPDIR" && DISPATCH_RUNNER="$FAKE_RUNNER" \
  LOG_DIR="$LOG_DIR" \
  PID_DIR="$PID_DIR" \
  DISPATCH_ARTEFATO="$ARTEFATO" \
  DISPATCH_SILENT_LIMIT=10 \
  bash "$REPO_ROOT/bin/dispatch.sh" "test-model" "$SPEC_FILE" "test-blocked" ) || true

echo "=== Aguardando watchdog detectar silêncio (sleep 25) ==="
sleep 25

echo "=== Conteúdo do artefato ==="
cat "$ARTEFATO"

if ! grep -q "^status: blocked" "$ARTEFATO"; then
  echo "FAIL: artefato não tem status: blocked"
  exit 1
fi

if ! grep -q "^bloqueio: watchdog: silêncio" "$ARTEFATO"; then
  echo "FAIL: artefato não tem bloqueio com motivo de silêncio"
  exit 1
fi

echo "PASS: artefato corretamente marcado como blocked após watchdog matar por silêncio."
