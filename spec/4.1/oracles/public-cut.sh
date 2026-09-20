#!/usr/bin/env bash
# Oráculo 41-02: docs/PUBLIC-CUT.md descreve o corte 4.1.0 com os números da árvore.
. "$(dirname "$0")/_lib.sh"
V=$(tr -d ' \n' < VERSION); N=$(n_incidents); S=$(n_suites); M=$(stat_js models); K=$(stat_js modes)
F=docs/PUBLIC-CUT.md
exige_grep "^# Public Cut — llms\.surf v$V\$" "$F" "título com v$V"
exige_grep "\b$N postmortems" "$F" "$N postmortems"
proibe_grep '3\.5\.0|\b106 postmortems' "$F" "sem 3.5.0 / 106"
exige_grep '^## What changed since 3\.5\.0' "$F" "seção 'What changed since 3.5.0'"
SEC=$(awk '/^## What changed since 3\.5\.0/{p=1;next} /^## /{p=0} p' "$F")
echo "$SEC" | grep -qE "106 → $N|106 to $N" && ok "delta de incidentes 106 → $N" || falha "delta de incidentes 106 → $N ausente"
echo "$SEC" | grep -qE "34 → $S|34 to $S" && ok "delta de suítes 34 → $S" || falha "delta de suítes 34 → $S ausente"
echo "$SEC" | grep -qE "23 → $M|23 to $M" && ok "delta de modelos 23 → $M" || falha "delta de modelos 23 → $M ausente"
echo "$SEC" | grep -qE "20 → $K|20 to $K" && ok "delta de modos 20 → $K" || falha "delta de modos 20 → $K ausente"
proibe_grep '(tok/s|\$/M|tokens/m[eê]s|goes live on)' "$F" "sem claims não medidos"
passa "bin/check-docs.sh" bash bin/check-docs.sh
veredito
