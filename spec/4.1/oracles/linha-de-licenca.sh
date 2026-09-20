#!/usr/bin/env bash
# Oráculo 41-07 (decisão do dono): a mesma frase de uso permitido está em LICENSE (fonte),
# site/llms.txt, site/index.html e README.md.
. "$(dirname "$0")/_lib.sh"
LINHA=$(grep -E '^Permitted use summary: ' LICENSE | head -n1 | sed -E 's/^Permitted use summary: //')
[ -n "$LINHA" ] && ok "LICENSE tem 'Permitted use summary:'" || { falha "LICENSE sem linha 'Permitted use summary: ...'"; veredito; }
echo "$LINHA" | grep -qE '^Permitted: .*Not permitted: ' && ok "frase tem 'Permitted:' e 'Not permitted:'" || falha "frase fora do formato 'Permitted: ... Not permitted: ...'"
L=${#LINHA}; [ "$L" -ge 60 ] && [ "$L" -le 320 ] && ok "frase com $L caracteres" || falha "frase com $L caracteres (fora de 60–320)"
for f in site/llms.txt site/index.html README.md; do grep -qF -- "$LINHA" "$f" && ok "$f repete a frase" || falha "$f não repete a frase exata"; done
veredito
