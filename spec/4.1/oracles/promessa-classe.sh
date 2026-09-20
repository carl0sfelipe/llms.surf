#!/usr/bin/env bash
# Oráculo 41-08 (decisão do dono): a promessa de 1e9 tokens tem unidade, pesos por classe,
# condição de crédito e validade em data/lineup-points.json, e o site explica a unidade.
. "$(dirname "$0")/_lib.sh"
command -v jq >/dev/null || { echo "jq ausente" >&2; exit 2; }
F=data/lineup-points.json
passa "JSON válido" jq -e . "$F"
passa "pledge.total_tokens = 1e9" jq -e '.pledge.total_tokens == 1000000000' "$F"
passa "pledge.unit = class-S-equivalent" jq -e '.pledge.unit == "class-S-equivalent"' "$F"
passa "pesos S=1, M>=4, L>=8" jq -e '.pledge.class_weights.S == 1 and .pledge.class_weights.M >= 4 and .pledge.class_weights.L >= 8' "$F"
passa "credited_when é texto" jq -e '.pledge.credited_when | strings | length > 20' "$F"
passa "expires_months é número" jq -e '.pledge.expires_months | numbers' "$F"
exige_grep 'class-S-equivalent' site/llms.txt "llms.txt explica a unidade"
exige_grep 'class-S' site/index.html "index.html explica a unidade"
veredito
