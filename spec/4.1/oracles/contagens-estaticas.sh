#!/usr/bin/env bash
# Oráculo 41-01: os números estáticos do site (fallback sem JS, llms.txt, incidents.html,
# readme.html) são iguais a DATA.stats, e o test-site-honesty passa a vigiar esses lugares.
. "$(dirname "$0")/_lib.sh"
V=$(stat_js version); N=$(stat_js incidents); M=$(stat_js models); K=$(stat_js modes); A=$(stat_js adapters); S=$(stat_js suites)
[ "$V" = "$(tr -d ' \n' < VERSION)" ] && ok "app.js version = VERSION ($V)" || falha "app.js version ($V) != VERSION"
[ "$N" = "$(n_incidents)" ] && ok "app.js incidents = árvore ($N)" || falha "app.js incidents ($N) != árvore ($(n_incidents))"
# site/llms.txt
exige_grep "^- version: $V\$" site/llms.txt "llms.txt version $V"
exige_grep "^- incidents: $N\b" site/llms.txt "llms.txt incidents $N"
exige_grep "^- models in registry: $M\$" site/llms.txt "llms.txt models $M sem vírgula sobrando"
exige_grep "^- modes: $K\$" site/llms.txt "llms.txt modes $K"
exige_grep "^- adapters: $A \+ 1 stub\$" site/llms.txt "llms.txt adapters $A + 1 stub"
exige_grep "^- test suites: $S\$" site/llms.txt "llms.txt suites $S"
exige_grep "the ledger; $N postmortems" site/llms.txt "llms.txt: 'the ledger; $N postmortems'"
proibe_grep '106 postmortems|3\.5\.0' site/llms.txt "llms.txt sem 106/3.5.0"
# site/index.html (fallback estático dos data-stat e do wipe-count)
exige_grep "id=\"wipe-count\">$N<" site/index.html "index.html wipe-count = $N"
exige_grep "data-stat=\"incidents\">$N<" site/index.html "index.html data-stat incidents = $N"
exige_grep "data-stat=\"version\">$V<" site/index.html "index.html data-stat version = $V"
proibe_grep 'data-stat="[a-z]+">(106|3\.5\.0)<|wipe-count">106<' site/index.html "index.html sem fallback 106/3.5.0"
# site/incidents.html e site/readme.html
exige_grep "id=\"wipe-count\">$N<" site/incidents.html "incidents.html wipe-count = $N"
exige_grep "content=\"[^\"]*\b$N incidents" site/incidents.html "incidents.html meta description = $N"
proibe_grep '\b106 incidents|wipe-count">106<' site/incidents.html "incidents.html sem 106"
exige_grep "public cut v$V" site/readme.html "readme.html public cut v$V"
proibe_grep 'v3\.5\.0' site/readme.html "readme.html sem 3.5.0"
# O gate precisa vigiar estes lugares daqui em diante.
passa "tests/test-site-honesty.sh" bash tests/test-site-honesty.sh
mutacao_deve_falhar "llms.txt adulterado" site/llms.txt "s/^- incidents: [0-9]+/- incidents: 9999/" tests/test-site-honesty.sh
mutacao_deve_falhar "index.html wipe-count adulterado" site/index.html 's/id="wipe-count">[0-9]+</id="wipe-count">9999</' tests/test-site-honesty.sh
mutacao_deve_falhar "readme.html versão adulterada" site/readme.html 's/public cut v[0-9.]+/public cut v0.0.0/' tests/test-site-honesty.sh
veredito
