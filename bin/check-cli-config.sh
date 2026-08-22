#!/bin/bash
# check-cli-config.sh — valida a CONFIG do próprio CLI antes de usá-lo.
# Uso: bin/check-cli-config.sh <cli>        (ex.: hermes, opencode)
#
# Diferente de pre-dispatch-check.sh, que olha quota/concorrência do provider:
# aqui o alvo é a configuração local do CLI — o tipo de falha que só aparece na
# primeira chamada real, depois de o agente já ter gastado minutos.
#
# Caso que originou o script (2026-07-26): `hermes -z` abortava com
#   "Auxiliary compression model meta/llama-3.1-8b-instruct has a context window
#    of 16,000 tokens, which is below the minimum 64,000 required"
# porque o modelo default apontava para http://localhost:8080/v1 (fora do ar) e
# a cadeia caía num fallback de 16k. Nada disso é visível em `--help` nem no
# registry: só a config do CLI sabe.
#
# Contrato: cada adapter PODE ter adapters/<cli>/preflight.sh. Sem ele, este
# script devolve 0 com aviso — ausência de check nunca bloqueia o dispatch.
#
# Exit codes (RNF-04): 0=ok, 1=config quebrada, 3=erro de uso

set -uo pipefail

CLI="${1:?Uso: check-cli-config.sh <cli>  (ex.: hermes, opencode)}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADAPTER_DIR="$REPO_ROOT/adapters/$CLI"

[ -d "$ADAPTER_DIR" ] || { echo "❌ adapter desconhecido: $CLI (veja $REPO_ROOT/adapters/)" >&2; exit 3; }

PREFLIGHT="$ADAPTER_DIR/preflight.sh"
if [ ! -f "$PREFLIGHT" ]; then
  echo "⚠️  $CLI não tem preflight.sh — nenhuma checagem de config disponível."
  exit 0
fi

bash "$PREFLIGHT"
RC=$?
[ "$RC" = "0" ] && echo "✅ config de $CLI OK"
exit "$RC"
