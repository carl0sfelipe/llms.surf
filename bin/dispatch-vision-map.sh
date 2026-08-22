#!/bin/bash
# dispatch-vision-map.sh — Fase 1 (MAP) do dispatch visão→texto
#
# Redimensiona cada foto pra 768px e pede ao gemma-4-26b (visão, free) uma
# descrição estruturada JSON. Saída: JSONL com uma linha por foto.
#
# Lições embutidas (medidas no smoke test 2026-07-30):
#  - Chave em .openrouter.key (NÃO .openrouter — é objeto)
#  - base64 em linha única (-b 0); com newlines o provider fallback rejeita
#  - MONTAR JSON COM jq -n, NUNCA printf com escapes manuais (printf quebra \\\" )
#  - Google primário fica 429; o fallback Darkbloom cobre. Retry com backoff.
#  - Redimensionar pra 768px: ~10x menos tokens, modelo descreve bem nesse tamanho
#  - FREE TIER TEM TETO POR-MINUTO (free-models-per-min): paralelo>1 estoura. Default
#    paralelismo=1 com 12s entre fotos. 55 fotos ~ 11 min. Backoff de 429 paciente.
#
# Uso: ./bin/dispatch-vision-map.sh <dir_fotos> <output.jsonl> [paralelismo]
set -euo pipefail

DIR_FOTOS="${1:?uso: $0 <dir_fotos> <output.jsonl> [paralelismo]}"
OUT="${2:?output jsonl}"
PARALELO="${3:-1}"
INTERVALO="${INTERVALO:-12}"  # segundos entre fotos (teto por-min do free tier)

KEY=$(jq -r '.openrouter.key' "$HOME/.local/share/opencode/auth.json")
TMP_BASE=$(mktemp -d)
LOCK="${OUT}.lockdir"
# LOCK robusto com stale-detection: previne 2 instancias no mesmo output.
# Escreve o PID no lockdir; se o lock existir mas o PID morreu, assume (stale).
# NUNCA apagar o lockdir por fora — deixa o trap limpar, ou use --unlock.
if [ -d "$LOCK" ]; then
  PID_VELHO=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [ -n "$PID_VELHO" ] && kill -0 "$PID_VELHO" 2>/dev/null; then
    echo "ABORT: instancia $PID_VELHO ja roda no output $OUT. Para forcar: rm -rf $LOCK (so se tiver certeza que morreu)" >&2
    exit 1
  fi
  echo "WARN: lock stale (PID $PID_VELHO morto). Assumindo." >&2
  rm -rf "$LOCK"
fi
mkdir "$LOCK"
echo $$ > "$LOCK/pid"
trap 'rm -rf "$TMP_BASE" "$LOCK"' EXIT

mkdir -p "$(dirname "$OUT")"
# MODO RESUME: se o output ja existe com fotos validas, NAO zera — pula as ja
# feitas. Torna re-runs seguros apos interrupcao (sem duplicar trabalho).
# Bug real 2026-07-30: o jq -c gera "arquivo": "x" COM espaco apos :, e o grep
# antigo procurava sem espaco -> nao achava -> exit 1 -> set -e matava o script
# ANTES do laco (ficava estagnado). Regex tolerante a espaco + || true.
touch "$OUT"
JA_FEITOS=$(grep -c . "$OUT" 2>/dev/null || echo 0)
JA_ARQUIVOS=$(grep -oE '"arquivo" *: *"[^"]*"' "$OUT" 2>/dev/null | sed -E 's/.*"arquivo" *: *"//; s/".*//' | sort -u || true)
echo "RESUME: $JA_FEITOS fotos ja descritas em $OUT (serao puladas)" >&2

PROMPT='Você é um analista de catálogo de uma loja brasileira de couro (marcenaria/couro). Analise esta ÚNICA foto com precisão de comerciante. Responda APENAS um objeto JSON válido, sem markdown nem texto antes/depois, com ESTES campos exatos:
{
  "tipo_produto": "categoria específica (ex: bolsa tote, bolsa transversal/crossbody, clutch, satchel executiva, carteira masculina, carteira feminina, cinto, mochila, portfolio/sacola)",
  "subtipo_formato": "formato/shape (ex: retangular alta, quadrada, cilindrica, horizontal alongada)",
  "cor_exata": "cor precisa observada (ex: caramelo, marrom cafe, preto fosco, vinho/bordô, nude)",
  "textura_material": "couro liso/couro granulado/couro croco/camurca/tecido+couro/peek/sintetico — seja especifico na textura",
  "ferragens": "cor e tipo de metais (ex: dourado, prateado, rose gold; fivela, zipper, mosquetao)",
  "alca_ou_corrente": "tipo de alça (ex: alca curta rigida, corrente de ombro media, alca longa transversal, sem alca)",
  "tamanho_estimado_cm": "ESTIMATIVA de altura x largura x profundidade em cm, inferida por referencia visual (mao/mesa/livro na foto). Ex: 30x25x12. Bolsas grandes 35-45cm, medias 25-35cm, pequenas/clutch 15-22cm, carteiras 10-20cm.",
  "estimativa_preco_brl": "numero inteiro. Estimativa de preço em Reais para item de couro full-grain brasileiro: bolsa grande 500-950, media 350-600, pequena/clutch 180-350, carteira 150-280, cinto 120-200, mochila 600-1100.",
  "angulo_foto": "frontal | lateral | superior | detalhe(close) | costas | modelo-em-uso",
  "sinais_distintivos": "1-2 marcas visuais unicas que distinguem ESTE item de outro parecido (ex: costura visivel branca, tassel, fecho com clic, alca dourada entrelacada)",
  "provavel_mesmo_produto_de": "se esta foto aparenta ser o MESMO item fisico que outro angulo, descreva em 4-6 palavras o conjunto (ex: tote caramelo costura branca) — chave pra agrupar depois",
  "nivel_confianca": "alta|media|baixa (baixa se foto escura/fora de foco/ambiguo)",
  "obs": "NAO_PRODUTO se nao houver item de couro na foto; senao vazio ou nota curta"
}'

descrever_uma() {
  local foto="$1" idx="$2"
  local pequena="$TMP_BASE/img_${idx}.jpg"
  sips -Z 768 "$foto" --out "$pequena" >/dev/null 2>&1 || return 1
  local b64 nome
  b64=$(base64 -b 0 -i "$pequena")
  nome=$(basename "$foto")
  local req="$TMP_BASE/req_${idx}.json"
  # MONTA JSON COM jq -n (seguro contra escapes); data-url inline
  jq -n --arg prompt "$PROMPT" --arg b64 "$b64" --arg nome "$nome" '{
    model: "google/gemma-4-26b-a4b-it:free",
    messages: [{ role: "user", content: [
      {type:"text", text:$prompt},
      {type:"image_url", image_url:{url:("data:image/jpeg;base64," + $b64)}}
    ]}]
  }' > "$req"

  local tentativa resp conteudo cod
  for tentativa in 1 2 3 4 5; do
    resp=$(curl -s --max-time 120 https://openrouter.ai/api/v1/chat/completions \
      -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -d @"$req" 2>/dev/null || true)
    conteudo=$(echo "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    cod=$(echo "$resp" | jq -r '.error.code // empty' 2>/dev/null)
    if [ -n "$conteudo" ]; then
      # EXTRAÇÃO TOLERANTE: o Gemma frequentemente embrulha o JSON em fences
      # ```json ... ``` ou precede com texto. Tenta vários graus de limpeza
      # antes de desistir. Bug real 2026-07-30: ~40% das respostas vinham
      # marcadas RESPOSTA_NAO_JSON quando o JSON estava intacto dentro de fence.
      limpo=$(echo "$conteudo" | tr -d '\r' | sed -n '/^[[:space:]]*```json/,/```/p; /^[[:space:]]*```/,/```/p' | sed '1d;$d')
      # se nao achou fence, tenta achar a 1a substring {...} valida (greedy { ate ultimo })
      if [ -z "$limpo" ]; then
        limpo=$(echo "$conteudo" | sed -n 's/.*\({.*}\).*/\1/p')
      fi
      # se ainda vazio, usa o conteudo cru (talvez seja JSON puro sem fence)
      [ -z "$limpo" ] && limpo="$conteudo"
      # valida + anexa arquivo; se conseguir, OK. Senao embrulha como nao-json.
      # Caso array: o Gemma às vezes devolve [{...}] em vez de {...}. Pega .[0].
      if echo "$limpo" | jq -e . >/dev/null 2>&1; then
        echo "$limpo" | jq -c --arg arq "$nome" '
          if type == "array" then .[0] else . end
          | . + {arquivo:$arq}
        ' >> "$OUT"
        echo "  [$idx] ok (tentativa $tentativa)" >&2
        return 0
      else
        jq -nc --arg raw "$conteudo" --arg arq "$nome" \
          '{arquivo:$arq, tipo_produto:"RESPOSTA_NAO_JSON", detalhes:$raw}' >> "$OUT"
        echo "  [$idx] ok mas NAO-JSON (tentativa $tentativa) — guardado cru" >&2
        return 0
      fi
    fi
    # 429 = teto por-min do free tier (comum). Backoff paciente e crescente.
    if [ "$cod" = "429" ]; then
      local wait=$(( 60 * tentativa ))
      echo "  [$idx] 429 (free tier), backoff ${wait}s..." >&2
      sleep "$wait"
      continue
    fi
    echo "  [$idx] sem conteudo (cod=$cod), retry $tentativa" >&2
    sleep 5
  done
  jq -nc --arg arq "$nome" '{arquivo:$arq, tipo_produto:"FALHOU_5_TENTATIVAS"}' >> "$OUT"
  echo "  [$idx] FALHOU apos 5 tentativas" >&2
  return 0
}
export -f descrever_uma
export KEY TMP_BASE OUT PROMPT

TOTAL_FOTOS=$(find "$DIR_FOTOS" -maxdepth 1 -name '*.jpg' | wc -l | tr -d ' ')
echo "MAP: $TOTAL_FOTOS fotos, paralelismo=$PARALELO, intervalo=${INTERVALO}s" >&2
i=0
while IFS= read -r foto; do
  i=$((i+1))
  nome_foto=$(basename "$foto")
  # RESUME: pula fotos ja descritas (evita duplicar trabalho em re-run)
  if echo "$JA_ARQUIVOS" | grep -qxF "$nome_foto"; then
    echo "  [$i] skip (ja descrita): $nome_foto" >&2
    continue
  fi
  descrever_uma "$foto" "$i"
  # intervalo entre fotos só entre chamadas (nao apos a ultima)
  [ "$i" -lt "$TOTAL_FOTOS" ] && sleep "$INTERVALO"
done < <(find "$DIR_FOTOS" -maxdepth 1 -name '*.jpg' | sort)

# dedup final defensiva: se houver duplicatas (corrida antiga), fica a 1a
total_antes=$(grep -c . "$OUT")
sort -u -t'"' -k4 "$OUT" -o "$OUT" 2>/dev/null || true
total=$(grep -c . "$OUT")
echo "MAP concluido: $total linhas em $OUT (dedup de $total_antes)" >&2
