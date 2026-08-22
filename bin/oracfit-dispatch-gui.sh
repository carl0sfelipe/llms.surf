#!/usr/bin/env bash
# oracfit-dispatch-gui.sh — ponte do POST /api/dispatch para o dispatch REAL.
#
# Uso: oracfit-dispatch-gui.sh <adapter> <mode> <spec_abs> <task>
#
# Quem chama é o panel server (via `oracfit daemon start`, double-fork+setsid
# — imune à morte da GUI/sessão, incidente 2026-08-12). Este script NÃO
# implementa dispatch: sourceia o adapter pedido e executa o mesmo
# `oracfit run` do terminal — um caminho só, zero implementação paralela.
#
# O servidor já validou mode/spec/task/adapter (fail-closed); aqui a checagem
# é de defesa em profundidade: se algo escapar, recusa ANTES de rodar modelo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ADAPTER="${1:?uso: oracfit-dispatch-gui.sh <adapter> <mode> <spec_abs> <task>}"
MODE="${2:?uso: oracfit-dispatch-gui.sh <adapter> <mode> <spec_abs> <task>}"
SPEC="${3:?uso: oracfit-dispatch-gui.sh <adapter> <mode> <spec_abs> <task>}"
TASK="${4:?uso: oracfit-dispatch-gui.sh <adapter> <mode> <spec_abs> <task>}"

case "$ADAPTER" in
  ""|*[!a-z0-9_-]*) echo "ERROR: adapter inválido: $ADAPTER" >&2; exit 3 ;;
esac
ENV_SH="$ROOT/adapters/$ADAPTER/env.sh"
if [ ! -f "$ENV_SH" ]; then
  echo "ERROR: adapter sem env.sh: $ADAPTER (procurado em $ENV_SH)" >&2
  exit 3
fi
[ -f "$SPEC" ] || { echo "ERROR: spec não existe: $SPEC" >&2; exit 3; }

# shellcheck disable=SC1090
source "$ENV_SH"
export ORACFIT_ROOT="${ORACFIT_ROOT:-$ROOT}"
cd "${ORACFIT_WORKDIR:-$PWD}"

echo "[gui-dispatch] $(date -u +%FT%TZ) adapter=$ADAPTER mode=$MODE task=$TASK"
echo "[gui-dispatch] workdir=$PWD · runner=$DISPATCH_RUNNER_NAME · spec=$SPEC"
exec "$SCRIPT_DIR/oracfit" run "$MODE" "$SPEC" "$TASK"
