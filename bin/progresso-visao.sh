#!/bin/bash
# progresso-visao.sh — barra de progresso animada para o dispatch de visão
#
# Lê o JSONL de saída do dispatch-vision-map.sh e mostra uma barra de progresso
# com porcentagem, atualizando em tempo real. Roda em qualquer terminal.
#
# Uso: ./bin/progresso-visao.sh [jsonl] [total] [intervalo_seg]
#   jsonl       default: /tmp/leadher-descriptions.jsonl
#   total       default: 55
#   intervalo   default: 2 (segundos entre atualizações)
set -euo pipefail

JSONL="${1:-/tmp/leadher-descriptions.jsonl}"
TOTAL="${2:-55}"
INTERVALO="${3:-2}"
LOCKDIR="${JSONL}.lockdir"

LARGURA=40  # largura da barra em caracteres

while true; do
  # contagem: conta linhas NAO-VAZIAS (a ultima pode nao ter newline)
  ATUAL=$(grep -c . "$JSONL" 2>/dev/null || echo 0)
  PCT=$(( ATUAL * 100 / TOTAL ))
  [ "$PCT" -gt 100 ] && PCT=100
  PREENCHIDO=$(( PCT * LARGURA / 100 ))
  VAZIO=$(( LARGURA - PREENCHIDO ))

  # monta a barra: █ cheio, ░ vazio
  BARRA=""
  for ((i=0; i<PREENCHIDO; i++)); do BARRA+="█"; done
  for ((i=0; i<VAZIO; i++)); do BARRA+="░"; done

  # estado do processo
  if [ -d "$LOCKDIR" ]; then
    ESTADO="🔄 processando"
  elif [ "$ATUAL" -ge "$TOTAL" ]; then
    ESTADO="✅ concluído"
  else
    ESTADO="⚠️  parado (lock livre, $ATUAL/$TOTAL)"
  fi

  # cursor pro inicio da linha (sem clear, pra nao piscar)
  printf "\r%s [%s] %3d%%  %d/%d fotos  %s        " \
    "$ESTADO" "$BARRA" "$PCT" "$ATUAL" "$TOTAL" "$(date +%H:%M:%S)"

  # terminou? imprime newline e sai
  if [ "$ATUAL" -ge "$TOTAL" ] || { [ ! -d "$LOCKDIR" ] && [ "$PCT" -ge 100 ]; }; then
    echo ""
    echo "Done: $ATUAL de $TOTAL fotos descritas."
    exit 0
  fi

  sleep "$INTERVALO"
done
