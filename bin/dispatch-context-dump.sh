#!/bin/bash
# dispatch-context-dump.sh — dispara um dump de contexto de sessão no Mode 2 (duo flash→pro).
#
# Um "dispatch de dump de contexto" serializa o contexto de uma sessão para arquivos .md,
# tornando-o harness-agnóstico: qualquer IA/harness lê e continua o trabalho. Diferente do
# `opencode --continue` (que só retoma dentro do opencode), o dump vive no repo e sobrevive
# a troca de ferramenta.
#
# Uso:
#   bin/dispatch-context-dump.sh <spec_preenchida> <workdir> [--mode 1|2|3] [--bg]
#
# Fluxo:
#   1. Valida a spec no gate (check-spec.sh) — reprova se faltar oráculo/anti-fantasma/etc.
#   2. Testa o oráculo contra o estado atual (deve falhar — o dump ainda não existe).
#   3. Dispara via dispatch-escalate.sh no modo escolhido (default Mode 2: flash→pro).
#
# A spec deve ser baseada em specs/context-dump-template.md com a NARRATIVA da sessão
# preenchida (o contexto que não está nos arquivos). O duo lê os arquivos-fonte + a narrativa
# e produz os 8 .md de continuidade.
#
# Exemplo:
#   # preencha o template com a narrativa da sessão
#   cp specs/context-dump-template.md /tmp/dump-sessao.md
#   $EDITOR /tmp/dump-sessao.md
#   bin/dispatch-context-dump.sh /tmp/dump-sessao.md /caminho/do/repo --bg

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${1:?Uso: dispatch-context-dump.sh <spec_preenchida> <workdir> [--mode 1|2|3] [--bg]}"
WORKDIR="${2:?Uso: dispatch-context-dump.sh <spec_preenchida> <workdir> [--mode 1|2|3] [--bg]}"
shift 2

MODE=2
BG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:?--mode requer 1|2|3}"; shift 2 ;;
    --bg) BG=1; shift ;;
    *) echo "flag desconhecida: $1" >&2; exit 3 ;;
  esac
done

[ -f "$SPEC" ] || { echo "spec não encontrada: $SPEC" >&2; exit 3; }
[ -d "$WORKDIR" ] || { echo "workdir não encontrado: $WORKDIR" >&2; exit 3; }

echo "── Gate: validando spec ──"
"$REPO_ROOT/bin/check-spec.sh" "$SPEC" || { echo "spec reprovada no gate." >&2; exit 1; }

echo ""
echo "── Dispatch de context dump | mode=$MODE | workdir=$WORKDIR ──"
TASK="context-dump-$(date +%Y%m%d-%H%M%S)"

if [ "$BG" = "1" ]; then
  LOG="/tmp/${TASK}.log"
  nohup "$REPO_ROOT/bin/dispatch-escalate.sh" "$SPEC" "$TASK" --mode "$MODE" --workdir "$WORKDIR" > "$LOG" 2>&1 &
  echo "rodando em background | PID=$! | log=$LOG"
  echo "acompanhe: tail -f $LOG"
else
  "$REPO_ROOT/bin/dispatch-escalate.sh" "$SPEC" "$TASK" --mode "$MODE" --workdir "$WORKDIR"
fi
