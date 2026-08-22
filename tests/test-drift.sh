#!/usr/bin/env bash

# Testa se todos os scripts mencionados nos arquivos .md dentro de fluxos/ existem e são executáveis.
# Busca por padrões "bin/algumaCoisa.sh" nos markdowns.

missing=0

# Encontrar todos os arquivos .md em fluxos/
while IFS= read -r md_file; do
  # Extrair caminhos de script mencionados
  while IFS= read -r script; do
    # Remover possíveis caracteres de pontuação final (.,;:?)
    script="${script%[.,;:] }"
    if [[ ! -f "$script" || ! -x "$script" ]]; then
      echo "Aviso: script '$script' não encontrado ou não é executável."
      missing=1
    fi
  done < <(grep -hoE "bin/[^[:space:]]+\\.sh" "$md_file" | sort -u)
done < <(find fluxos -type f -name "*.md" 2>/dev/null)

exit $missing
