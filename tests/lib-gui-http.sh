#!/usr/bin/env bash
# lib-gui-http.sh — helpers para suítes que sobem a GUI local e a consultam.
#
# Incidente incidents/2026-09-19-suites-de-gui-falham-no-runner-do-ci-em-.md:
# no runner do GitHub, um `curl -sf` num estático falhava 10 ms depois de outra
# request passar no MESMO servidor; local 18/18 verde. Causa não determinada.
# Mecanismo: (1) toda leitura de asserção tenta 5× com recuo, (2) a falha
# final imprime rc/http e o log do servidor — a próxima ocorrência deixa
# evidência em vez de um FAIL seco.
#
# Uso: source "$REPO_ROOT/tests/lib-gui-http.sh"
#   gui_get <url>            → corpo no stdout; exit 1 após 5 tentativas
#   gui_wait_port <log> <path> → imprime a porta efêmera quando <path> responde
#   gui_dump_log <log>       → log do servidor no stderr (só chame em FAIL)

gui_get() {
  local url="$1" i body rc=1 code
  for i in 1 2 3 4 5; do
    body=$(curl -s -f --max-time 5 "$url" 2>/dev/null); rc=$?
    if [ "$rc" -eq 0 ]; then printf '%s' "$body"; return 0; fi
    sleep 0.3
  done
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)
  echo "  gui_get: $url falhou 5x (curl rc=$rc http=${code:-?})" >&2
  return 1
}

gui_wait_port() { # <server log> <path a sondar>
  local log="$1" path="$2" port="" _
  for _ in $(seq 1 50); do
    port=$(grep -oE 'http://127\.0\.0\.1:[0-9]+' "$log" 2>/dev/null | head -1 | grep -oE '[0-9]+$' || true)
    if [ -n "$port" ] && curl -sf --max-time 5 "http://127.0.0.1:$port/$path" >/dev/null 2>&1; then
      printf '%s' "$port"; return 0
    fi
    sleep 0.2
  done
  return 1
}

gui_dump_log() {
  [ -f "$1" ] || return 0
  echo "  --- log do servidor ($1) ---" >&2
  sed 's/^/    /' "$1" >&2
}
