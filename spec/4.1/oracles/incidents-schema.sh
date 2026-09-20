#!/usr/bin/env bash
# Oráculo 41-03: todo incidente tem o frontmatter completo e existe um gate que impede regressão.
. "$(dirname "$0")/_lib.sh"
RUINS=0
for f in incidents/*.md; do
  case "$f" in */README.md) continue;; esac
  FM=$(awk 'NR==1&&/^---/{p=1;next} p&&/^---/{exit} p' "$f")
  for k in id titulo data recorrivel regra status interage_com; do
    echo "$FM" | grep -qE "^$k:" || { echo "sem '$k:': $f" >&2; RUINS=$((RUINS+1)); }
  done
done
[ "$RUINS" -eq 0 ] && ok "todos os incidentes têm as 7 chaves" || falha "$RUINS chave(s) faltando"
exige_arquivo tests/test-incidents-schema.sh
[ -x tests/test-incidents-schema.sh ] && ok "teste executável" || falha "tests/test-incidents-schema.sh sem +x"
passa "tests/test-incidents-schema.sh" bash tests/test-incidents-schema.sh
TMP=$(mktemp); printf -- '---\nid: x\n---\n# x\n' > "$TMP"; cp "$TMP" incidents/zz-oraculo-tmp.md
if bash tests/test-incidents-schema.sh >/dev/null 2>&1; then falha "o teste NÃO reprova incidente sem chaves"; else ok "o teste reprova incidente sem chaves"; fi
rm -f incidents/zz-oraculo-tmp.md "$TMP"
contagens_publicas_batem
veredito
