#!/usr/bin/env bash
# Oráculo 41-04: nenhum número não medido sobre a cloud fora do bloco de estimativa, e um gate
# novo (tests/test-no-unmeasured-claims.sh) mantém isso.
. "$(dirname "$0")/_lib.sh"
PADRAO='(tok/s|tokens/s|\$/M\b|\$ ?[0-9]+(\.[0-9]+)? ?/ ?M\b|tokens per month|tokens/m[eê]s|goes live on|launch(es|ing)? on (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec))'
SEM_EST=$(awk '/<section[^>]*id="(assumed-rates|estimate)"/{skip=1} skip&&/<\/section>/{skip=0;next} !skip' site/index.html)
if echo "$SEM_EST" | grep -qE "$PADRAO"; then falha "index.html tem claim não medido fora de #assumed-rates/#estimate:"; echo "$SEM_EST" | grep -nE "$PADRAO" | head -n 5 >&2; else ok "index.html limpo fora do estimador"; fi
proibe_grep "$PADRAO" site/llms.txt "llms.txt sem claims"
proibe_grep "$PADRAO" site/readme.html "readme.html sem claims"
for f in site/blog/posts/*.md; do [ -f "$f" ] && proibe_grep "$PADRAO" "$f" "$(basename "$f") sem claims"; done
exige_grep 'until measured' site/llms.txt "llms.txt mantém 'until measured'"
exige_arquivo tests/test-no-unmeasured-claims.sh
passa "tests/test-no-unmeasured-claims.sh" bash tests/test-no-unmeasured-claims.sh
mutacao_deve_falhar "claim injetado no llms.txt" site/llms.txt 's/^## Contract$/## Contract\n\nWe serve 9999 tok\/s at $0.01\/M./' tests/test-no-unmeasured-claims.sh
contagens_publicas_batem
veredito
