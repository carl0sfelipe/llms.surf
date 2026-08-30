#!/bin/bash
# dispatch-vision-ui-qa.sh — Vision QA sobre screenshots de storefront + gauntlet P2
#
# Fase map: findings JSONL (foto quebrada, CSS, layout).
# Fase gauntlet (opcional): blind A/B vs ## Barra / --bar DIR até ours ganhar
# ou safety_ceiling; escreve report + revise brief.
#
# Uso:
#   ./bin/dispatch-vision-ui-qa.sh <dir_pngs> <output.jsonl> \
#       [--bar DIR] [--gauntlet] [--ceiling N] [--interval N]
#
# Modelo default: google/gemma-4-26b-a4b-it:free (vision free via OpenRouter)
# Override: VISION_MODEL=...
#
# Exit: 0 = map ok e (sem gauntlet | gauntlet APPROVED)
#       1 = gauntlet REVISIONS_REQUIRED
#       2 = uso inválido
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DIR_SHOTS=""
OUT=""
BAR_DIR=""
GAUNTLET=false
CEILING="${GAUNTLET_CEILING:-4}"
INTERVALO="${INTERVALO:-12}"
MODEL="${VISION_MODEL:-google/gemma-4-26b-a4b-it:free}"

usage() {
  cat <<EOF
Usage: $0 <dir_screenshots> <output.jsonl> [options]

Options:
  --bar DIR       Reference screenshots (basename-paired with ours) — gauntlet bar
  --gauntlet      After map, run blind A/B loop until ours wins or --ceiling
  --ceiling N     Safety ceiling for A/B rounds per pair (default $CEILING)
  --interval N    Seconds between vision calls (default $INTERVALO)
  --help          This help

Env: VISION_MODEL, INTERVALO, GAUNTLET_CEILING
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --bar)
      shift
      BAR_DIR="${1:?--bar requires DIR}"
      shift
      ;;
    --gauntlet) GAUNTLET=true; shift ;;
    --ceiling)
      shift
      CEILING="${1:?--ceiling requires N}"
      shift
      ;;
    --interval)
      shift
      INTERVALO="${1:?--interval requires N}"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -z "$DIR_SHOTS" ]; then DIR_SHOTS="$1"
      elif [ -z "$OUT" ]; then OUT="$1"
      else
        echo "ERROR: unexpected arg: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$DIR_SHOTS" ] || [ -z "$OUT" ]; then
  usage >&2
  exit 2
fi
if [ ! -d "$DIR_SHOTS" ]; then
  echo "ERROR: shots dir not found: $DIR_SHOTS" >&2
  exit 2
fi
if $GAUNTLET && [ -z "$BAR_DIR" ]; then
  echo "ERROR: --gauntlet requires --bar DIR (named fetchable bar)" >&2
  exit 2
fi
if [ -n "$BAR_DIR" ] && [ ! -d "$BAR_DIR" ]; then
  echo "ERROR: bar dir not found: $BAR_DIR" >&2
  exit 2
fi

KEY=$(jq -r '.openrouter.key' "$HOME/.local/share/opencode/auth.json")
TMP_BASE=$(mktemp -d)
trap 'rm -rf "$TMP_BASE"' EXIT
mkdir -p "$(dirname "$OUT")"
: >"$OUT"

# VISION_QA_PROMPT (env) sobrepoe o prompt default: repos nao-e-commerce
# (ex.: scrollytelling/app) precisam de criterio de dominio proprio — prompt de
# storefront faz o modelo free alucinar major do tipo "sem elementos de
# e-commerce" (descoberto 2026-08-10 no tripcstory overnight).
if [ -n "${VISION_QA_PROMPT:-}" ]; then
  PROMPT="$VISION_QA_PROMPT"
else
PROMPT='Voce e um QA visual de e-commerce. Analise ESTE screenshot de storefront.
Responda APENAS um objeto JSON valido (sem markdown), com estes campos:
{
  "page_guess": "pdp|catalog|blog|blog_search|other",
  "broken_images": [{"selector_hint":"descricao da area","reason":"404|empty|placeholder|stretched|other"}],
  "css_issues": [{"severity":"critical|major|minor","area":"...","problem":"...","evidence":"o que se ve"}],
  "layout_issues": [{"severity":"critical|major|minor","problem":"..."}],
  "blog_search_ui": {"present": true, "looks_functional": true, "notes": "... ou null se nao for blog"},
  "overall_severity": "ok|minor|major|critical",
  "summary_pt": "1-2 frases em portugues"
}
Regras: nao invente bugs invisíveis; se a foto do produto aparece nitida, broken_images=[].
Se houver icone quebrado / alt text / area cinza tipica de img morta, registre em broken_images.
Seja harsh: major/critical so quando o bug e evidente e afeta compra/confianca.'
fi

extrair_json() { # stdin texto bruto -> stdout JSON de 1 linha (ou nada)
  local conteudo="$1" limpo
  limpo=$(echo "$conteudo" | tr -d '\r' | sed -n '/^[[:space:]]*```json/,/```/p; /^[[:space:]]*```/,/```/p' | sed '1d;$d')
  [ -z "$limpo" ] && limpo=$(echo "$conteudo" | sed -n 's/.*\({.*}\).*/\1/p')
  [ -z "$limpo" ] && limpo="$conteudo"
  if echo "$limpo" | jq -e . >/dev/null 2>&1; then echo "$limpo"; return 0; fi
  return 1
}

descrever_opencode() { # engine v3: modelos opencode-go via CLI local (sem OpenRouter)
  local pequena="$1" nome="$2"
  local tentativa conteudo limpo
  # ARMADILHA (incident 2026-08-11-opencode-run-f-engole-o-prompt-como-caminho):
  # -f e array variadico — prompt posicional PRIMEIRO, arquivo por ultimo.
  for tentativa in 1 2 3; do
    conteudo=$(opencode run -m "$MODEL" "$PROMPT" -f "$pequena" 2>/dev/null || true)
    if limpo=$(extrair_json "$conteudo"); then
      # Schema vision_gate v3 ({verdict,...}) nao tem overall_severity — mapear
      # pra vqa-oracle.sh contar: REJECTED=major, APPROVED=ok.
      echo "$limpo" | jq -c --arg arq "$nome" '
        (if type=="array" then .[0] else . end)
        | (if .verdict? then .overall_severity = (if (.verdict|ascii_upcase)=="APPROVED" then "ok" else "major" end) else . end)
        | . + {arquivo:$arq}' >> "$OUT"
      echo "  [$idx] ok ($nome, engine=opencode)" >&2
      return 0
    fi
    sleep 10
  done
  jq -nc --arg arq "$nome" '{arquivo:$arq, overall_severity:"critical", summary_pt:"FALHOU_3_TENTATIVAS_OPENCODE"}' >> "$OUT"
}

descrever() {
  local shot="$1" idx="$2"
  local pequena="$TMP_BASE/img_${idx}.jpg"
  sips -Z 1024 "$shot" --out "$pequena" >/dev/null 2>&1 || cp "$shot" "$pequena"
  local nome
  nome=$(basename "$shot")

  case "$MODEL" in
    opencode/*)
      descrever_opencode "$pequena" "$nome"
      return 0
      ;;
  esac

  local b64
  # BSD base64: -b 0 -i file; GNU: sem -b (wrap 76) — stdin + tr é portátil
  b64=$(base64 <"$pequena" | tr -d '\n')
  local req="$TMP_BASE/req_${idx}.json"
  jq -n --arg prompt "$PROMPT" --arg b64 "$b64" --arg model "$MODEL" '{
    model: $model,
    messages: [{ role: "user", content: [
      {type:"text", text:$prompt},
      {type:"image_url", image_url:{url:("data:image/jpeg;base64," + $b64)}}
    ]}]
  }' > "$req"

  local tentativa resp conteudo cod limpo
  for tentativa in 1 2 3 4 5; do
    resp=$(curl -s --max-time 120 https://openrouter.ai/api/v1/chat/completions \
      -H "Authorization: Bearer $KEY" \
      -H "Content-Type: application/json" \
      -d @"$req" 2>/dev/null || true)
    conteudo=$(echo "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    cod=$(echo "$resp" | jq -r '.error.code // empty' 2>/dev/null)
    if [ -n "$conteudo" ]; then
      limpo=$(echo "$conteudo" | tr -d '\r' | sed -n '/^[[:space:]]*```json/,/```/p; /^[[:space:]]*```/,/```/p' | sed '1d;$d')
      [ -z "$limpo" ] && limpo=$(echo "$conteudo" | sed -n 's/.*\({.*}\).*/\1/p')
      [ -z "$limpo" ] && limpo="$conteudo"
      if echo "$limpo" | jq -e . >/dev/null 2>&1; then
        echo "$limpo" | jq -c --arg arq "$nome" 'if type=="array" then .[0] else . end | . + {arquivo:$arq}' >> "$OUT"
        echo "  [$idx] ok ($nome)" >&2
        return 0
      fi
      jq -nc --arg raw "$conteudo" --arg arq "$nome" \
        '{arquivo:$arq, overall_severity:"critical", summary_pt:"RESPOSTA_NAO_JSON", detalhes:$raw}' >> "$OUT"
      echo "  [$idx] NAO-JSON ($nome)" >&2
      return 0
    fi
    if [ "$cod" = "429" ]; then
      sleep $((60 * tentativa))
      continue
    fi
    sleep 5
  done
  jq -nc --arg arq "$nome" '{arquivo:$arq, overall_severity:"critical", summary_pt:"FALHOU_5_TENTATIVAS"}' >> "$OUT"
}

TOTAL=$(find "$DIR_SHOTS" -maxdepth 1 \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | wc -l | tr -d ' ')
echo "UI-QA vision map: $TOTAL shots, model=$MODEL, interval=${INTERVALO}s → $OUT" >&2
i=0
while IFS= read -r shot; do
  i=$((i+1))
  descrever "$shot" "$i"
  [ "$i" -lt "$TOTAL" ] && sleep "$INTERVALO"
done < <(find "$DIR_SHOTS" -maxdepth 1 \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort)
echo "UI-QA map concluido: $(grep -c . "$OUT" 2>/dev/null || echo 0) linhas" >&2

if ! $GAUNTLET; then
  # Sem gauntlet: exit 0 mesmo com findings (caller decide). Report rollup no stderr.
  rollup=$(python3 "$SCRIPT_DIR/vision-gauntlet-loop.py" rollup "$OUT" 2>/dev/null || echo "?")
  echo "map rollup severity=$rollup (gauntlet off)" >&2
  exit 0
fi

REPORT="${OUT%.jsonl}.gauntlet.json"
BRIEF="${OUT%.jsonl}.revise.md"
echo "UI-QA gauntlet A/B: bar=$BAR_DIR ceiling=$CEILING → $REPORT" >&2
set +e
python3 "$SCRIPT_DIR/vision-gauntlet-loop.py" ab-loop \
  --findings "$OUT" \
  --ours "$DIR_SHOTS" \
  --bar "$BAR_DIR" \
  --report "$REPORT" \
  --brief "$BRIEF" \
  --ceiling "$CEILING" \
  --interval "$INTERVALO" \
  --model "$MODEL"
ab_rc=$?
set -e
echo "gauntlet exit=$ab_rc report=$REPORT brief=$BRIEF" >&2
exit "$ab_rc"
