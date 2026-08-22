#!/bin/bash
# vision-gate-slices.sh — juiz visual por fatias ≤1800px (evita downscale full-page)
# Uso: vision-gate-slices.sh <screenshots_dir> [--url <post_url>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORACFIT_ROOT="${ORACFIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
MODEL="openrouter/google/gemma-4-26b-a4b-it:free"
MAX_SLICE_H=1800
MIN_LAST_SLICE_H=200
JUDGE_TIMEOUT=120

usage() {
  echo "Uso: $(basename "$0") <screenshots_dir> [--url <post_url>]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
SCREENSHOTS_DIR="$(cd "$1" && pwd)"
shift

POST_URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      [[ $# -ge 2 ]] || usage
      POST_URL="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

for required in desktop-full.png mobile-full.png; do
  if [[ ! -f "$SCREENSHOTS_DIR/$required" ]]; then
    echo "ERROR: falta $SCREENSHOTS_DIR/$required" >&2
    exit 1
  fi
done

SLICES_DIR="$SCREENSHOTS_DIR/slices"
rm -rf "$SLICES_DIR"
mkdir -p "$SLICES_DIR"

SLICE_NAMES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && SLICE_NAMES+=("$line")
done < <(
  python3 - "$SLICES_DIR" "$MAX_SLICE_H" "$MIN_LAST_SLICE_H" \
    "$SCREENSHOTS_DIR/desktop-full.png" desktop \
    "$SCREENSHOTS_DIR/mobile-full.png" mobile <<'PY'
import os
import sys
from PIL import Image

out_dir = sys.argv[1]
max_h = int(sys.argv[2])
min_last = int(sys.argv[3])
args = sys.argv[4:]

def slice_image(path: str, prefix: str) -> list[str]:
    img = Image.open(path)
    w, total_h = img.size
    bounds: list[tuple[int, int]] = []
    y = 0
    while y < total_h:
        remaining = total_h - y
        if remaining <= max_h:
            bounds.append((y, total_h))
            break
        bounds.append((y, y + max_h))
        y += max_h

    if len(bounds) > 1:
        last_start, last_end = bounds[-1]
        if (last_end - last_start) < min_last:
            prev_start, _prev_end = bounds[-2]
            bounds[-2] = (prev_start, last_end)
            bounds.pop()

    names: list[str] = []
    for i, (y0, y1) in enumerate(bounds, 1):
        crop = img.crop((0, y0, w, y1))
        name = f"{prefix}-{i:02d}.png"
        crop.save(os.path.join(out_dir, name))
        names.append(name)
    return names

all_names: list[str] = []
for i in range(0, len(args), 2):
    all_names.extend(slice_image(args[i], args[i + 1]))

for name in all_names:
    print(name)
PY
)

VERDICT_FILE="$SCREENSHOTS_DIR/vision-verdict.txt"
: >"$VERDICT_FILE"

slice_position() {
  local name="$1"
  local base="${name%.png}"
  local device="${base%-*}"
  local num="${base##*-}"
  num=$((10#$num))

  local last=0
  local n
  for n in "${SLICE_NAMES[@]}"; do
    case "$n" in
      ${device}-*) last=$((last + 1)) ;;
    esac
  done

  if (( num == 1 )); then
    echo "top slice"
  elif (( num == last )); then
    echo "bottom slice"
  else
    echo "middle slice"
  fi
}

parse_judge_response() {
  local raw="$1"
  python3 - "$raw" <<'PY'
import json, re, sys
raw = sys.argv[1].strip()
if not raw:
    sys.exit(1)
candidates = [raw]
m = re.search(r'\{[^{}]*"verdict"[^{}]*\}', raw, re.S)
if m:
    candidates.insert(0, m.group(0))
for c in candidates:
    try:
        obj = json.loads(c)
    except json.JSONDecodeError:
        continue
    verdict = obj.get("verdict")
    gap = obj.get("biggest_gap", "")
    if verdict:
        print(verdict)
        print(gap if gap is not None else "")
        sys.exit(0)
sys.exit(1)
PY
}

judge_slice() {
  local slice_path="$1"
  local position="$2"
  local prompt
  # Contexto anti-falso-positivo (run DC8B7FBF, mobile-17): fatia com footer +
  # área de respiro em cor sólida foi rejeitada 2x como "blank/empty grey area".
  # Fatia é corte de página longa: cor sólida e texto cortado na borda são design
  # normal, não erro. Sem esse aviso o juiz free confabula defeito estável.
  prompt="Visual QA of a BLOG POST screenshot (${position} of a longer page). IMPORTANT context: this image is ONE slice cut from a taller page, so text/images cut off at the very top or bottom edge are EXPECTED, and large solid-color regions (page background, whitespace between sections, a dark footer band with logo and link lists) are NORMAL page design — none of these are defects. Checklist: (1) raw markdown/code fences/HTML tags visible as text? (2) horizontal overflow/broken layout? (3) an actual error page or loading spinner (visible error message or spinner graphic)? (4) broken image placeholders or images that failed to load? (5) clear typography hierarchy?"
  if [[ "$position" == "top slice" ]]; then
    prompt="${prompt} (6) does the page show a real article with prose paragraphs? A page consisting mostly of raw code blocks or JSON instead of article text is a FAIL."
  fi
  prompt="${prompt} If ALL pass, verdict APPROVED, else REJECTED. Respond ONLY JSON with verdict and biggest_gap."

  local raw=""
  local attempt
  for attempt in 1 2; do
    raw=""
    raw="$(bash "$ORACFIT_ROOT/bin/with-timeout.sh" "$JUDGE_TIMEOUT" \
      opencode run -m "$MODEL" "$prompt" -f "$slice_path" 2>&1)" || true
    if parse_judge_response "$raw" >/dev/null 2>&1; then
      parse_judge_response "$raw"
      return 0
    fi
  done
  echo "vision judge sem resposta" >&2
  exit 1
}

FIRST_REJECT_NAME=""
FIRST_REJECT_GAP=""
TOTAL_SLICES=${#SLICE_NAMES[@]}

for name in "${SLICE_NAMES[@]}"; do
  slice_path="$SLICES_DIR/$name"
  position="$(slice_position "$name")"
  parsed=()
  while IFS= read -r line; do
    parsed+=("$line")
  done < <(judge_slice "$slice_path" "$position")
  verdict="${parsed[0]}"
  gap="${parsed[1]:-}"
  gap_one_line="$(printf '%s' "$gap" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"

  # Gemma free confabula defeito ocasionalmente (ex.: "'Sabel...' repetido"
  # numa fatia limpa, run 177DA27B loop 2). Confabulação é estocástica;
  # defeito real é estável. REJECTED só vale se repetir na 2ª julgada da
  # MESMA fatia — senão conta como aprovada (flaky).
  if [[ "$verdict" != "APPROVED" ]]; then
    parsed2=()
    while IFS= read -r line; do
      parsed2+=("$line")
    done < <(judge_slice "$slice_path" "$position")
    verdict2="${parsed2[0]}"
    gap2="${parsed2[1]:-}"
    if [[ "$verdict2" == "APPROVED" ]]; then
      verdict="APPROVED"
      gap_one_line="(flaky reject na 1a julgada: ${gap_one_line:0:120})"
    else
      verdict="$verdict2"
      gap_one_line="$(printf '%s' "$gap2" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    fi
  fi
  echo "$name $verdict $gap_one_line" >>"$VERDICT_FILE"
  # Progresso no stdout: alimenta o mech-N.log (painel "Log do stage") ao
  # vivo — sem isso o stage fica 20 min mudo e o painel marca "abandonado".
  echo "slice ${name}: ${verdict}${gap_one_line:+ — ${gap_one_line:0:100}}"

  if [[ "$verdict" == "APPROVED" ]]; then
    :
  elif [[ -z "$FIRST_REJECT_NAME" ]]; then
    FIRST_REJECT_NAME="$name"
    FIRST_REJECT_GAP="$gap_one_line"
  fi
done

if [[ -n "$FIRST_REJECT_NAME" ]]; then
  trunc_gap="${FIRST_REJECT_GAP:0:240}"
  echo "VISION GATE REJECTED: ${FIRST_REJECT_NAME}: ${trunc_gap}"
  exit 1
fi

if [[ -n "$POST_URL" ]]; then
  html="$(curl -s --max-time 30 "$POST_URL")" || {
    echo "VISION GATE REJECTED: curl falhou para $POST_URL" >&2
    exit 1
  }
  if ! printf '%s' "$html" | rg -q 'href="[^"]*/produtos/'; then
    echo "VISION GATE REJECTED: nenhum CTA /produtos/ no HTML"
    exit 1
  fi
fi

echo "VISION GATE APPROVED (${TOTAL_SLICES} slices)"
exit 0
