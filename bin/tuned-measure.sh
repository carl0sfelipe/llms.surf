#!/bin/bash
# tuned-measure.sh — S10: registro e medição before/after de modelo tunado.
# E2-D1: o claim "fine-tune" só existe com before/after medido; E2-D4: o
# dogfood É a medição. Este harness roda as MESMAS specs contra o modelo
# base e o tuned/<dominio>-<base> (mesmo modo, mesmo protocolo — só o
# model_ref muda via DISPATCH_MODEL_REF), e confere que TODA medição está
# no ledger com run_id. Medição sem ledger = run fantasma = reprova.
#
# Uso:
#   bin/tuned-measure.sh --base <id> --tuned <tuned/<dominio>-<base>> \
#     --mode <mode_id> --spec <path.md> ... (EXATAMENTE 5) [--workdir DIR]
#
# Saída: relatório JSON em $WORKDIR/.dispatch/tuned-measure/ + stdout.
# Exit 0 só se as 10 rodadas (5 specs × 2 lados) estão no ledger.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="normal"
WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
BASE=""
TUNED=""
SPECS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:?--base precisa de id}"; shift 2 ;;
    --tuned) TUNED="${2:?--tuned precisa de id}"; shift 2 ;;
    --mode) MODE="${2:?--mode precisa de id}"; shift 2 ;;
    --spec) SPECS+=("${2:?--spec precisa de path}"); shift 2 ;;
    --workdir) WORKDIR="${2:?--workdir precisa de dir}"; shift 2 ;;
    *) echo "tuned-measure: argumento desconhecido: $1" >&2; exit 3 ;;
  esac
done

[ -n "$BASE" ] || { echo "tuned-measure: --base é obrigatório" >&2; exit 3; }
case "$TUNED" in
  tuned/*) : ;;
  "") echo "tuned-measure: --tuned é obrigatório" >&2; exit 3 ;;
  *) echo "tuned-measure: --tuned deve seguir tuned/<dominio>-<base>, veio '$TUNED' (E2-D2)" >&2; exit 3 ;;
esac
[ ${#SPECS[@]} -eq 5 ] || { echo "tuned-measure: são EXATAMENTE 5 specs (E2-D1: N=5), vieram ${#SPECS[@]}" >&2; exit 3; }
for s in "${SPECS[@]}"; do
  [ -f "$s" ] || { echo "tuned-measure: spec não encontrada: $s" >&2; exit 3; }
done

WORKDIR="$(cd "$WORKDIR" && pwd -P)"
export ORACFIT_WORKDIR="$WORKDIR"
LEDGER="$WORKDIR/.dispatch/ledger/mode.jsonl"
OUT_DIR="$WORKDIR/.dispatch/tuned-measure"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

declare -A RUN_ID BY_RC
n=0
for side in base tuned; do
  if [ "$side" = "base" ]; then side_id="$BASE"; else side_id="$TUNED"; fi
  i=0
  for spec in "${SPECS[@]}"; do
    i=$((i + 1))
    n=$((n + 1))
    name="$(basename "$spec" .md)"
    task="tuned-measure-${side}-${i}-${name}"
    # cada medição começa de oráculo vermelho: o proof da rodada anterior
    # cita OUTRO model_id — deixar lá seria medir o passado (o veredito
    # real vem do ledger, escrito pelo dispatch, não deste arquivo)
    rm -f "$WORKDIR/.dispatch/stub-proof"
    out="$OUT_DIR/.run-${n}.out"
    set +e
    ORACFIT_WORKDIR="$WORKDIR" DISPATCH_MODEL_REF="$side_id" \
      bash "$ROOT/bin/dispatch-mode.sh" "$MODE" "$spec" "$task" >"$out" 2>&1
    rc=$?
    set -e
    BY_RC["$side/$task"]="$rc"
    rid="$(grep -oE 'run_id: [a-f0-9-]+' "$out" | head -1 | cut -d' ' -f2 || true)"
    RUN_ID["$side/$task"]="$rid"
  done
done

# ── verificação de ledger: 10 rodadas, cada uma com run_id, model_id do
#    seu lado e oracle_exit registrados. O que não está no ledger não
#    aconteceu (regra da casa) ──
report="$OUT_DIR/${STAMP}-${TUNED//\//-}.json"
{
  echo "{"
  echo "  \"generated_at\": \"$STAMP\","
  echo "  \"base\": \"$BASE\","
  echo "  \"tuned\": \"$TUNED\","
  echo "  \"mode\": \"$MODE\","
  echo "  \"n_specs\": 5,"
  echo "  \"tasks\": ["
  first=1
  missing=0
  for side in base tuned; do
    if [ "$side" = "base" ]; then side_id="$BASE"; else side_id="$TUNED"; fi
    i=0
    for spec in "${SPECS[@]}"; do
      i=$((i + 1))
      name="$(basename "$spec" .md)"
      task="tuned-measure-${side}-${i}-${name}"
      rid="${RUN_ID["$side/$task"]:-}"
      rc="${BY_RC["$side/$task"]:-}"
      row=""
      oracle_exit="missing"
      if [ -n "$rid" ] && [ -f "$LEDGER" ]; then
        row="$(grep -F "\"$rid\"" "$LEDGER" | grep -F "\"model_id\": \"$side_id\"" | tail -1 || true)"
        [ -n "$row" ] && oracle_exit="$(printf '%s' "$row" | python3 -c "import json,sys; print(json.load(sys.stdin).get('oracle_exit','missing'))" 2>/dev/null || echo missing)"
      fi
      ledger_ok="false"
      [ -n "$rid" ] && [ -n "$row" ] && ledger_ok="true"
      [ "$ledger_ok" = "true" ] || missing=$((missing + 1))
      [ $first -eq 1 ] || echo ","
      first=0
      printf '    {"side": "%s", "spec": "%s", "task": "%s", "dispatch_rc": "%s", "run_id": "%s", "ledger_ok": %s, "oracle_exit": "%s"}' \
        "$side" "$name" "$task" "$rc" "${rid:-}" "$ledger_ok" "$oracle_exit"
    done
  done
  echo ""
  echo "  ],"
  echo "  \"all_ledgered\": $([ $missing -eq 0 ] && echo true || echo false),"
  echo "  \"missing_count\": $missing"
  echo "}"
} > "$report"

if [ "$missing" -gt 0 ]; then
  echo "tuned-measure: FALHA — $missing rodada(s) SEM ledger (run fantasma): relatório em $report" >&2
  grep -o '"task": "[^"]*", "dispatch_rc": "[^"]*", "run_id": "[^"]*", "ledger_ok": false' "$report" >&2 || true
  exit 1
fi
echo "tuned-measure: 10/10 rodadas no ledger — relatório: $report"
cat "$report"
exit 0
