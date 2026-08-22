#!/bin/bash
# runner.sh — implementação qwen-code do contrato core/runner-contract.md
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
#
# ⚠️ ADAPTER EXPERIMENTAL — a CLI `qwen` NÃO existe neste host.
# Ver adapters/qwen-code/DISCOVERY.md (Passo 0: `command -v qwen` sem saída).
#
# Como não há `--help` real, nenhuma flag pode ser documentada nem chutada
# (PRD seção 11, regras 1 e 5). Este runner falha explicitamente em vez de
# inventar sintaxe. O caminho suportado hoje para modelos Qwen é o opencode,
# via cli_hints.opencode do model-registry.json (PRD seção 4.4: qwen code é
# orquestrador; o executor delega ao opencode).
#
# Exit codes (RNF-04): 0=ok, 1=erro, 2=rate-limit, 3=erro de uso, 4=quota exausta

set -uo pipefail

MODEL_ID="${1:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
SPEC_FILE="${2:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"

# Incidente 2026-08-12-runner-herda-cwd-do-lancador: mesmo bloco dos outros
# adapters — quando a CLI qwen existir, o cwd do run já é o contrato.
SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
if [ -n "${ORACFIT_WORKDIR:-}" ]; then
  cd "$ORACFIT_WORKDIR" || { echo "runner.sh (qwen-code): workdir inexistente: $ORACFIT_WORKDIR" >&2; exit 3; }
fi

QWEN_BIN="${QWEN_BIN:-qwen}"

if ! command -v "$QWEN_BIN" >/dev/null 2>&1; then
  cat >&2 <<EOF
runner.sh (qwen-code): CLI '$QWEN_BIN' não encontrada — adapter experimental.

Confirmado em adapters/qwen-code/DISCOVERY.md. Sem \`qwen --help\` real, este
adapter não pode montar linha de comando sem violar a regra 11.1 do PRD.

Alternativa suportada hoje (PRD seção 4.4):
  source adapters/opencode/env.sh   # modelos Qwen via cli_hints.opencode
EOF
  exit 3
fi

# TODO-VERIFICAR: quando a CLI `qwen` estiver disponível, rodar o Passo 0
# (`qwen --help` → DISCOVERY.md), preencher capabilities.env e só então
# implementar a tradução abaixo. Enquanto isso, falhar é o comportamento correto.
echo "runner.sh (qwen-code): CLI presente, mas tradução não implementada — rode o Passo 0 (DISCOVERY) antes de usar." >&2
exit 3
