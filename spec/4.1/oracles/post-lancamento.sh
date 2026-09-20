#!/usr/bin/env bash
# Oráculo 41-06: existe o post de lançamento 4.1.0, com frontmatter igual ao do post existente,
# sem claims não medidos, e o build do blog o publica.
. "$(dirname "$0")/_lib.sh"
V=$(tr -d ' \n' < VERSION); N=$(n_incidents)
POST=$(ls site/blog/posts/*4-1-0*.md 2>/dev/null | head -n1)
[ -n "$POST" ] && ok "post: $POST" || { falha "nenhum site/blog/posts/*4-1-0*.md"; veredito; }
for k in title description date slug lang author tags canonical; do exige_grep "^$k:" "$POST" "frontmatter tem $k"; done
exige_grep '^date: 20[0-9]{2}-[0-9]{2}-[0-9]{2}$' "$POST" "date em ISO"
SLUG=$(grep -E '^slug:' "$POST" | sed -E 's/^slug: *//; s/"//g')
exige_grep "^canonical: https://llms\.surf/blog/$SLUG\$" "$POST" "canonical bate com o slug"
exige_grep "\b$V\b" "$POST" "cita $V"
exige_grep '[Oo]r(a|á)cul|oracle' "$POST" "fala do oráculo"
exige_grep 'whitelist|lineup' "$POST" "fala da whitelist/lineup"
exige_grep "\b$N\b" "$POST" "cita os $N incidentes"
proibe_grep '(tok/s|\$/M|tokens/m[eê]s|goes live on|launch(es|ing)? on (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec))' "$POST" "sem claims não medidos"
proibe_grep '\[A DEFINIR\]' "$POST" "sem [A DEFINIR] sobrando"
WC=$(awk '/^---/{c++; next} c>=2' "$POST" | wc -w | tr -d ' '); [ "$WC" -ge 250 ] && [ "$WC" -le 1200 ] && ok "corpo com $WC palavras" || falha "corpo com $WC palavras (fora de 250–1200)"
passa "python3 site/blog/build.py" python3 site/blog/build.py
exige_arquivo "site/blog/$SLUG/index.html"
exige_grep "$SLUG" site/blog/index.html "índice do blog lista o post"
veredito
