#!/bin/bash
# runner.sh — implementação claude-code do contrato core/runner-contract.md
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
#
# ATENÇÃO (PRD seções 4.3/4.4): claude CLI só roda modelos Anthropic. Se o
# <model_id> não tiver cli_hints.claude no model-registry.json, FALHA com
# exit 3 — nunca traduz modelo free para claude.
#
# Sintaxe verificada em adapters/claude-code/DISCOVERY.md (`claude --help`).
# Exit codes (RNF-04): 0=ok, 1=erro, 2=rate-limit, 3=erro de uso, 4=quota exausta

set -uo pipefail

MODEL_ID="${1:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
SPEC_FILE="${2:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
shift 2

# Incidente 2026-08-12-runner-herda-cwd-do-lancador: o CLI edita arquivos
# relativos ao CWD do LANÇADOR — com workdir apontando pra outro lugar, o
# modelo despachado edita o repo errado. O workdir do run é o contrato:
# cd nele antes de subir o modelo. Spec canonicalizada ANTES do cd.
SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
if [ -n "${ORACFIT_WORKDIR:-}" ]; then
  cd "$ORACFIT_WORKDIR" || { echo "runner.sh (claude-code): workdir inexistente: $ORACFIT_WORKDIR" >&2; exit 3; }
fi

SESSION_ID=""
FORK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      SESSION_ID="${2:?--session requer ID}"
      shift 2
      ;;
    --fork)
      FORK=1
      shift
      ;;
    *)
      echo "runner.sh (claude-code): flag desconhecida: $1" >&2
      exit 3
      ;;
  esac
done

if [ ! -f "$SPEC_FILE" ]; then
  echo "runner.sh (claude-code): spec_file não encontrado: $SPEC_FILE" >&2
  exit 1
fi

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
MODEL_REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"

if [ ! -f "$MODEL_REGISTRY" ]; then
  echo "runner.sh (claude-code): model-registry.json não encontrado: $MODEL_REGISTRY" >&2
  exit 3
fi

CLAUDE_HINT=$(python3 -c "
import json
d = json.load(open('$MODEL_REGISTRY'))
for m in d.get('models', []):
    if m.get('id') == '$MODEL_ID':
        print(m.get('cli_hints', {}).get('claude', ''))
        break
" 2>/dev/null)

if [ -z "$CLAUDE_HINT" ]; then
  echo "claude-code não executa $MODEL_ID; use o runner do opencode (adapters/opencode/runner.sh)" >&2
  exit 3
fi

if [ "$FORK" = "1" ] && [ -z "$SESSION_ID" ]; then
  echo "runner.sh (claude-code): --fork requer --session ID (ver core/runner-contract.md)" >&2
  exit 3
fi

CLAUDE_BIN="${CLAUDE_BIN:-claude}"

ARGS=(-p --model "$CLAUDE_HINT")
if [ -n "$SESSION_ID" ]; then
  ARGS+=(--resume "$SESSION_ID")
  [ "$FORK" = "1" ] && ARGS+=(--fork-session)
fi

[ "${DISPATCH_RUNNER_FORMAT_JSON:-0}" = "1" ] && ARGS+=(--output-format json)

# SEGURANÇA (RF-01.1): --dangerously-skip-permissions só é usado se
# DISPATCH_UNSAFE=1. Por default, permissões seguem allowlist do projeto
# (.claude/settings.local.json) — ver adapters/claude-code/CLAUDE.md.
#
# Entre "nega tudo" e "libera tudo" faltava o meio: DISPATCH_ALLOWED_TOOLS passa
# uma allowlist ESTREITA, específica da tarefa, via --allowed-tools. Sem isso, um
# dispatch honesto que precise rodar `python3` para no meio pedindo aprovação que
# ninguém vai dar — foi o que aconteceu em 2026-07-27 com a spec de resolve-hints,
# e a saída fácil (ligar DISPATCH_UNSAFE) concede muito mais do que a tarefa pede.
# Formato: "Read,Write,Edit,Bash(python3:*),Bash(git:*)" — lista separada por vírgula.
#
# `--allowed-tools` é VARIÁDICO (`<tools...>`) e vai depois do prompt, nunca antes:
# posto antes, ele engole o próprio prompt como se fosse mais uma ferramenta e o
# claude aborta com "Input must be provided either through stdin or as a prompt
# argument when using --print" — vírgula no valor não evita isso. Provado em
# 2026-07-27: `claude -p --model sonnet --allowed-tools "Read,Write" "<prompt>"`
# falha; `claude -p --model sonnet "<prompt>" --allowed-tools "Read,Write"` responde.
ARGS_POS=()
if [ "${DISPATCH_UNSAFE:-0}" = "1" ]; then
  ARGS+=(--dangerously-skip-permissions)
elif [ -n "${DISPATCH_ALLOWED_TOOLS:-}" ]; then
  ARGS_POS+=(--allowed-tools "$(printf '%s' "$DISPATCH_ALLOWED_TOOLS" | tr ' ' ',')")
fi

# ARGS_POS vai DEPOIS do prompt (ver bloco acima). `${ARGS_POS[@]+...}`:
# array vazio sob `set -u` aborta no bash 3.2 do macOS.
OUTPUT=$("$CLAUDE_BIN" "${ARGS[@]}" "$(cat "$SPEC_FILE")" ${ARGS_POS[@]+"${ARGS_POS[@]}"} 2>&1)
EXIT_CODE=$?

echo "$OUTPUT"

if [ $EXIT_CODE -ne 0 ]; then
  if echo "$OUTPUT" | grep -qiE '429|rate.?limit'; then
    exit 2
  fi
  if echo "$OUTPUT" | grep -qiE 'OAuth session expired|Failed to authenticate|not logged in|authentication'; then
    echo "runner.sh (claude-code): auth — rode \`claude login\` / \`claude auth\`" >&2
    exit 3
  fi
  exit 1
fi

if echo "$OUTPUT" | grep -qiE '429|rate.?limit'; then
  exit 2
fi

exit 0
