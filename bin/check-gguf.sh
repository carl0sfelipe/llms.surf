#!/bin/bash
# check-gguf.sh — valida arquivo GGUF SEGUINDO o symlink.
#
# Existe porque `ls -la` num symlink devolve o tamanho do LINK, não do alvo:
# 104 bytes era o comprimento do caminho `~/.ollama/models/blobs/sha256-...`,
# e isso virou "GGUF truncado, sem tensores" em três documentos. O arquivo tinha
# 5,6 GB e magic válido. Modelo local instalado por ollama ou huggingface-cli é
# symlink por padrão — a armadilha é o caminho comum, não a exceção.
# Incidente: incidents/2026-07-27-ls-la-em-symlink-reportou-tamanho-do-lin.md
#
# Uso: bin/check-gguf.sh <arquivo.gguf> [arquivo.gguf...]
# Exit: 0=todos válidos, 1=algum inválido, 3=erro de uso

set -uo pipefail

MIN_BYTES=$((1024 * 1024))   # abaixo de 1 MB não é peso de modelo, é stub

[ $# -ge 1 ] || { echo "Uso: bin/check-gguf.sh <arquivo.gguf> [...]" >&2; exit 3; }

FALHAS=0

for F in "$@"; do
  if [ ! -e "$F" ]; then
    printf "❌ %-58s não existe\n" "$(basename "$F")"
    FALHAS=$((FALHAS + 1)); continue
  fi

  # -L: segue o link. Sem isso mede o link, não o modelo.
  if [ ! -f "$F" ] && [ ! -L "$F" ]; then
    printf "❌ %-58s não é arquivo nem link\n" "$(basename "$F")"
    FALHAS=$((FALHAS + 1)); continue
  fi

  ALVO="$F"
  if [ -L "$F" ]; then
    ALVO=$(readlink "$F")
    if [ ! -e "$ALVO" ]; then
      printf "❌ %-58s link quebrado -> %s\n" "$(basename "$F")" "$ALVO"
      FALHAS=$((FALHAS + 1)); continue
    fi
  fi

  TAM=$(stat -L -f%z "$F" 2>/dev/null || stat -L -c%s "$F" 2>/dev/null || echo 0)
  MAGIC=$(head -c 4 "$F" 2>/dev/null)

  if [ "$MAGIC" != "GGUF" ]; then
    printf "❌ %-58s magic '%s' (esperado GGUF)\n" "$(basename "$F")" "$MAGIC"
    FALHAS=$((FALHAS + 1)); continue
  fi
  if [ "$TAM" -lt "$MIN_BYTES" ]; then
    printf "❌ %-58s %s bytes — pequeno demais para ter tensores\n" "$(basename "$F")" "$TAM"
    FALHAS=$((FALHAS + 1)); continue
  fi

  GB=$(echo "$TAM" | awk '{printf "%.1f", $1/1073741824}')
  LINK=""
  [ -L "$F" ] && LINK=" (symlink)"
  printf "✅ %-58s %s GB · magic GGUF%s\n" "$(basename "$F")" "$GB" "$LINK"
done

[ "$FALHAS" -eq 0 ] || { echo "$FALHAS arquivo(s) inválido(s)."; exit 1; }
exit 0
