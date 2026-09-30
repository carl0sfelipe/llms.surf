#!/usr/bin/env bash
# stub-cloudflared.sh — cloudflared falso pro oráculo do gui-tunnel.
#
# Grava o argv recebido (uma linha por arg + linha em branco separando
# invocações) em $STUB_CF_ARGV_LOG, se setado. Imprime um banner parecido
# com o do cloudflared real com uma URL https://*.trycloudflare.com única
# (rótulo com o próprio PID, pra dar pra notar troca de processo em teste
# de restart). Fica vivo até receber INT/TERM — como o cloudflared real
# num quick tunnel em foreground.
set -uo pipefail

if [ -n "${STUB_CF_ARGV_LOG:-}" ]; then
  for a in "$@"; do printf '%s\n' "$a" >> "$STUB_CF_ARGV_LOG"; done
  printf '\n' >> "$STUB_CF_ARGV_LOG"
fi

label="${STUB_CF_LABEL:-stub}-$$"
echo "$(date -u +%FT%TZ) INF Thank you for trying Cloudflare Tunnel."
echo "$(date -u +%FT%TZ) INF +--------------------------------------------------------------------------------------------+"
echo "$(date -u +%FT%TZ) INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |"
echo "$(date -u +%FT%TZ) INF |  https://${label}.trycloudflare.com                                                          |"
echo "$(date -u +%FT%TZ) INF +--------------------------------------------------------------------------------------------+"

trap 'exit 0' INT TERM
while :; do sleep 1; done
