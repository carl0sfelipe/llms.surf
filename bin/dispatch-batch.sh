#!/bin/bash
# dispatch-batch.sh — Modo 2.2: LOOP horizontal de despachos com checkpoint/rollback
#
# Uso: bin/dispatch-batch.sh <batch_file> [--mode 1|2|3] [--allow-dirty] [--gate-only]
#
# batch_file: uma linha por item, formato `<spec_file>|<task_name>|<workdir>`
#             ou `<spec_file>|<task_name>|<workdir>|<model_ref>` (4º campo
#             opcional: model_ref para tier único deste item).
#             (# inicia comentário; linhas vazias ignoradas)
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUE ESTE MODO EXISTE (e não é dispatch-escalate.sh com um `for` em volta)
#
# O 2.1 (dispatch-escalate.sh) escala UM item VERTICALMENTE: flash → pro →
# opus, até o oráculo passar. Ele é correto nisso e este script NÃO o
# reimplementa: delega. O que falta no 2.1 para rodar um lote são quatro
# coisas medidas, não supostas:
#
#   1. Não existe laço horizontal. `parallel-dispatch.sh` tem laço, mas é
#      anterior ao 2.0: não tem oráculo nem escalonamento. Usar um dos dois
#      obriga a escolher entre laço e gate.
#
#   2. Não existe rollback. Quando um tier falha, as edições PARCIAIS do modelo
#      ficam na árvore. O 2.1 tenta de novo POR CIMA do lixo — e num lote o
#      item 2 herda a sujeira do item 1. Sem checkpoint, um lote de 3 itens tem
#      3 chances de contaminar o repo e nenhuma de voltar.
#
#   3. O gate roda tarde ou não roda. `dispatch-escalate.sh` só confere que
#      existe a linha `- comando:`; nunca chama `check-spec.sh`. Num lote isso
#      significa gastar tier inteiro no item 1 para descobrir que o item 3
#      estava sem cláusula anti-invenção. Aqui TODAS as specs passam pelo
#      check-spec.sh ANTES de qualquer modelo ser chamado — falha cara na
#      frente, de graça.
#
#   4. `$SPEC_FILE.escalate` é acumulativo. O 2.1 faz
#      `SPEC_FILE="$SPEC_FILE.escalate"` e na tentativa seguinte anexa ao
#      arquivo JÁ anexado. Num lote isso deixa `.escalate`, `.escalate.escalate`
#      espalhados pelo specs/. Aqui cada item roda numa cópia descartável.
#
#   5. O gate não distinguia "oráculo falha porque falta trabalho" de "oráculo
#      falha porque o comando está quebrado" — as duas dão exit≠0. Um oráculo
#      que não pode passar em nenhum estado do repo era lido como trabalho
#      pendente e liberava o dispatch. Quem decide isso agora é
#      `bin/check-oracle.py` (incidents/2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca.md).
#
# O princípio é o do incidente 2026-07-29 (mecanismo, não artefato): quem
# precisa de exit code chama quem já captura certo. Este script não decide se
# um item passou — pergunta ao oráculo via 2.1 e registra o que voltou.
# ─────────────────────────────────────────────────────────────────────────────
#
# Exit: 0=todos passaram, 1=algum falhou, 3=erro de uso/gate

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BATCH_FILE="${1:?Uso: dispatch-batch.sh <batch_file> [--mode 1|2|3] [--allow-dirty] [--gate-only]}"
shift

MODE=2
ALLOW_DIRTY=0
GATE_ONLY=0
MAX_PER_TIER=""
# Teto por item. O 2.1 não põe teto em `opencode run` nem em `claude -p`: um
# modelo que trava segura o lote inteiro sem sinal. Foram 52min perdidos assim
# em 2026-07-24 (lessons/2026-07-24-dispatch-travado.md); a regra do repo é
# nunca chamar rede/modelo sem teto.
ITEM_TIMEOUT=1200
# Teto do oráculo no gate. Ele roda `tsc`/`vitest` e, ao contrário do item, não
# tem modelo nenhum atrás: se estourar, o problema é o oráculo.
ORACLE_TIMEOUT=600
FACTS_ALSO=()

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:?--mode requer 1|2|3}"; shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --gate-only) GATE_ONLY=1; shift ;;
    --max-per-tier) MAX_PER_TIER="${2:?--max-per-tier requer n}"; shift 2 ;;
    --item-timeout) ITEM_TIMEOUT="${2:?--item-timeout requer segundos}"; shift 2 ;;
    --oracle-timeout) ORACLE_TIMEOUT="${2:?--oracle-timeout requer segundos}"; shift 2 ;;
    # Repo extra onde uma citação legítima da spec pode viver (ex.: comparar o
    # arquivo local com o fonte do framework). Repetível.
    --facts-also) FACTS_ALSO+=("--also" "${2:?--facts-also requer DIR}"); shift 2 ;;
    *) echo "flag desconhecida: $1" >&2; exit 3 ;;
  esac
done

[ -f "$BATCH_FILE" ] || { echo "batch file não encontrado: $BATCH_FILE" >&2; exit 3; }

LOG_DIR="${LOG_DIR:-$REPO_ROOT/.dispatch/logs}"
mkdir -p "$LOG_DIR"
BATCH_LEDGER="$LOG_DIR/batch-ledger.jsonl"
RUN_ID="batch-$(date +%Y%m%d-%H%M%S)"
WORK_TMP="$(mktemp -d)"
trap 'rm -rf "$WORK_TMP"' EXIT

# ── parse ──────────────────────────────────────────────────────────────────
# Incidente 2026-08-11-dispatch-batch-v2-2-hardcoded-tiers-open: aceita 4º
# campo opcional model_ref por item (tier único via DISPATCH_TIERS só p/ ele).
SPECS=(); TASKS=(); DIRS=(); MODEL_REFS=()
LINENO_=0
while IFS= read -r line || [ -n "$line" ]; do
  LINENO_=$((LINENO_ + 1))
  line="${line%%#*}"
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$line" ] && continue

  IFS='|' read -r spec task dir mref <<< "$line"
  spec="$(printf '%s' "${spec:-}" | sed 's/[[:space:]]*$//')"
  task="$(printf '%s' "${task:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  dir="$(printf '%s' "${dir:-}" | sed 's/^[[:space:]]*//')"
  mref="$(printf '%s' "${mref:-}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  [ -n "$spec" ] && [ -n "$task" ] && [ -n "$dir" ] \
    || { echo "linha $LINENO_ malformada (esperado spec|task|workdir ou spec|task|workdir|model_ref): $line" >&2; exit 3; }
  SPECS+=("$spec"); TASKS+=("$task"); DIRS+=("$dir"); MODEL_REFS+=("$mref")
done < "$BATCH_FILE"

TOTAL=${#SPECS[@]}
[ "$TOTAL" -gt 0 ] || { echo "batch file sem itens" >&2; exit 3; }

# ── GATE: todas as specs, antes de gastar um centavo ───────────────────────
echo "══════════════════════════════════════════════════════════"
echo " dispatch-batch $RUN_ID | itens=$TOTAL | mode=$MODE"
echo "══════════════════════════════════════════════════════════"
echo ""
echo "── Gate (check-spec.sh em TODAS as specs antes de despachar) ──"

GATE_FAIL=0
for i in $(seq 0 $((TOTAL - 1))); do
  spec="${SPECS[$i]}"; task="${TASKS[$i]}"; dir="${DIRS[$i]}"

  if [ ! -f "$spec" ]; then
    echo "  ❌ $task — spec não existe: $spec"; GATE_FAIL=1; continue
  fi
  if [ ! -d "$dir/.git" ]; then
    echo "  ❌ $task — workdir não é repo git: $dir"; GATE_FAIL=1; continue
  fi
  if ! bash "$REPO_ROOT/bin/check-spec.sh" "$spec" > "$WORK_TMP/gate-$i.txt" 2>&1; then
    echo "  ❌ $task — check-spec reprovou:"; sed 's/^/       /' "$WORK_TMP/gate-$i.txt"
    GATE_FAIL=1; continue
  fi

  # check-spec.sh prova que a spec PROÍBE o modelo de inventar. Não prova que o
  # ORQUESTRADOR não inventou. Medido em 2026-07-29: a spec
  # dedupe-observability-leadher.md passou nos 5 checks afirmando um glob de
  # vitest.config.ts que existe em OUTRO repo — e foi despachada. O modelo foi
  # olhar, não achou, e reportou; o gate não olhou nada.
  if ! python3 "$REPO_ROOT/bin/check-spec-facts.py" "$spec" "$dir" \
        ${FACTS_ALSO[@]+"${FACTS_ALSO[@]}"} --quiet > "$WORK_TMP/facts-$i.txt" 2>&1; then
    echo "  ❌ $task — dado afirmado como verificado que não existe:"
    sed 's/^/       /' "$WORK_TMP/facts-$i.txt"
    GATE_FAIL=1; continue
  fi

  # O oráculo tem de FALHAR agora, e falhar pelo MOTIVO CERTO. Duas perguntas
  # diferentes, e até 2026-07-29 este gate só fazia a primeira: `eval` do
  # oráculo e exit≠0 bastava. Mas exit≠0 tem duas causas — falta trabalho, ou o
  # comando está quebrado — e um oráculo que não pode passar em nenhum estado do
  # repo também dá exit≠0. Custou 1204s de modelo, 3 tentativas, uma escalada
  # para o tier pago e um rollback de trabalho provavelmente bom, porque o padrão
  # trazia um pipe escapado (em ERE, literal). Quem decide isso agora é o
  # check-oracle.py, que separa os três casos por exit code.
  python3 "$REPO_ROOT/bin/check-oracle.py" "$spec" "$dir" \
          --timeout "$ORACLE_TIMEOUT" --quiet > "$WORK_TMP/oracle-$i.txt" 2>&1
  case $? in
    0) : ;;
    1) echo "  ❌ $task — oráculo JÁ PASSA antes do dispatch (não mede nada)"
       GATE_FAIL=1; continue ;;
    2) echo "  ❌ $task — oráculo QUEBRADO (falha em qualquer estado do repo):"
       sed 's/^/       /' "$WORK_TMP/oracle-$i.txt"
       GATE_FAIL=1; continue ;;
    *) echo "  ❌ $task — check-oracle não pôde julgar:"
       sed 's/^/       /' "$WORK_TMP/oracle-$i.txt"
       GATE_FAIL=1; continue ;;
  esac
  echo "  ✅ $task — spec OK, oráculo falha como deve e pelo motivo certo"
done

echo ""
if [ "$GATE_FAIL" -ne 0 ]; then
  echo "❌ gate reprovou. Nenhum modelo foi chamado, nenhum token gasto." >&2
  exit 3
fi
echo "✅ gate passou nos $TOTAL itens."
echo ""

if [ "$GATE_ONLY" -eq 1 ]; then
  echo "--gate-only: parando aqui."
  exit 0
fi

# ── checkpoint / rollback ──────────────────────────────────────────────────
# Nunca `reset --hard` cego: a árvore pode ter trabalho não commitado do
# usuário. O snapshot é um objeto de stash criado COM -u (inclui não
# rastreados) e imediatamente devolvido à árvore com `pop`. O ref morre, o
# objeto commit sobrevive — e `git stash apply <sha>` aceita sha cru.
checkpoint() {
  local dir="$1" out
  ( cd "$dir" && git rev-parse HEAD )
  if [ -n "$(cd "$dir" && git status --porcelain)" ]; then
    if [ "$ALLOW_DIRTY" -ne 1 ]; then
      echo "DIRTY"; return 0
    fi
    out=$(cd "$dir" && git stash push -u -q -m "dispatch-batch:$RUN_ID" && git rev-parse "stash@{0}")
    ( cd "$dir" && git stash pop -q ) >/dev/null 2>&1
    echo "$out"
  else
    echo ""
  fi
}

rollback() {
  local dir="$1" head="$2" stash="$3"
  ( cd "$dir" && git reset --hard -q "$head" && git clean -fdq )
  # -fd sem -x: arquivos ignorados (node_modules, dist) ficam. Só o que o
  # modelo criou e não está no snapshot é removido.
  if [ -n "$stash" ]; then
    ( cd "$dir" && git stash apply -q "$stash" ) >/dev/null 2>&1 \
      || echo "     ⚠️  stash $stash não aplicou limpo — inspecione manualmente" >&2
  fi
}

# ── laço ───────────────────────────────────────────────────────────────────
BATCH_START=$(date +%s)
N_OK=0; N_FAIL=0
declare -a VERDICTS=()

for i in $(seq 0 $((TOTAL - 1))); do
  spec="${SPECS[$i]}"; task="${TASKS[$i]}"; dir="${DIRS[$i]}"; mref="${MODEL_REFS[$i]}"
  echo "══ [$((i+1))/$TOTAL] $task ══"

  CP=$(checkpoint "$dir")
  SNAP_HEAD=$(printf '%s' "$CP" | sed -n 1p)
  SNAP_STASH=$(printf '%s' "$CP" | sed -n 2p)

  if [ "$SNAP_STASH" = "DIRTY" ]; then
    echo "  ⏭️  pulado — workdir sujo e sem --allow-dirty: $dir"
    VERDICTS+=("$task|skipped-dirty|0")
    N_FAIL=$((N_FAIL + 1))
    echo ""; continue
  fi
  echo "  📌 checkpoint: ${SNAP_HEAD:0:8}${SNAP_STASH:+ + stash ${SNAP_STASH:0:8}}"

  # cópia descartável: o 2.1 anexa contexto de falha na spec e reaponta
  # SPEC_FILE pro .escalate. Isolando aqui, specs/ não acumula lixo.
  RUN_SPEC="$WORK_TMP/$task.md"
  cp "$spec" "$RUN_SPEC"

  ESC_ARGS=(--mode "$MODE" --workdir "$dir")
  [ -n "$MAX_PER_TIER" ] && ESC_ARGS+=(--max-per-tier "$MAX_PER_TIER")

  ITEM_START=$(date +%s)
  set +e
  # Incidente 2026-08-11-dispatch-batch-v2-2-hardcoded-tiers-open: model_ref
  # por item vira tier único via DISPATCH_TIERS só p/ este escalate; `env` só
  # afeta o filho, a próxima iteração não herda. O array NUNCA fica vazio:
  # "${a[@]}" com array vazio sob set -u aborta no bash 3.2 do macOS.
  ESC_ENV=(env)
  [ -n "$mref" ] && ESC_ENV+=("DISPATCH_TIERS=$mref")
  bash "$REPO_ROOT/bin/with-timeout.sh" "$ITEM_TIMEOUT" \
       "${ESC_ENV[@]}" \
       bash "$REPO_ROOT/bin/dispatch-escalate.sh" "$RUN_SPEC" "$task" \
       "${ESC_ARGS[@]}" 2>&1 | sed 's/^/  │ /'
  ESC_EXIT=${PIPESTATUS[0]}
  set -e
  ITEM_DUR=$(( $(date +%s) - ITEM_START ))

  if [ "$ESC_EXIT" -eq 124 ]; then
    echo "  ⏱️  $task estourou o teto de ${ITEM_TIMEOUT}s — ROLLBACK"
    # v3.5 (triagem fábrica-agentic §A3): item pendurado é sinal de provider,
    # não só de item — registra no usage-hub p/ o trail do pick. `hang` NÃO
    # está em BLOCK_KINDS (registra, não veta; o abort por transporte repetido
    # — melhoria 1.2 — decidirá com dados). Só quando o model_ref do item é
    # conhecido: atribuir hang a provider chutado é pior que não registrar.
    if [ -n "$mref" ]; then
      python3 "$REPO_ROOT/bin/usage-hub.py" observe --kind hang \
        --model-ref "$mref" --message "item ${task} estourou ${ITEM_TIMEOUT}s" \
        --source dispatch-batch >/dev/null 2>&1 || true
    fi
    rollback "$dir" "$SNAP_HEAD" "$SNAP_STASH"
    VERDICTS+=("$task|timeout|$ITEM_DUR")
    N_FAIL=$((N_FAIL + 1))
    echo ""; continue
  fi

  if [ "$ESC_EXIT" -eq 0 ]; then
    echo "  ✅ $task passou o oráculo em ${ITEM_DUR}s — mudanças MANTIDAS"
    VERDICTS+=("$task|success|$ITEM_DUR")
    N_OK=$((N_OK + 1))
  else
    echo "  ❌ $task falhou (escalate exit $ESC_EXIT) — ROLLBACK pro checkpoint"
    rollback "$dir" "$SNAP_HEAD" "$SNAP_STASH"
    echo "  ↩️  árvore restaurada; item $((i+2)) começa limpo"
    VERDICTS+=("$task|failed|$ITEM_DUR")
    N_FAIL=$((N_FAIL + 1))
  fi
  echo ""
done

BATCH_DUR=$(( $(date +%s) - BATCH_START ))

# ── resumo + ledger ────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════════════════"
printf " %-38s %-14s %6s\n" "item" "resultado" "seg"
for v in "${VERDICTS[@]}"; do
  IFS='|' read -r t r d <<< "$v"
  printf " %-38s %-14s %6s\n" "$t" "$r" "$d"
done
echo "──────────────────────────────────────────────────────────"
echo " $N_OK ok | $N_FAIL falhou | total ${BATCH_DUR}s"
echo "══════════════════════════════════════════════════════════"

ITEMS_JSON=""
for v in "${VERDICTS[@]}"; do
  IFS='|' read -r t r d <<< "$v"
  ITEMS_JSON="$ITEMS_JSON{\"task\":\"$t\",\"result\":\"$r\",\"duration_s\":$d},"
done
ITEMS_JSON="[${ITEMS_JSON%,}]"
printf '{"run_id":"%s","mode":%s,"total":%s,"ok":%s,"failed":%s,"total_s":%s,"items":%s}\n' \
  "$RUN_ID" "$MODE" "$TOTAL" "$N_OK" "$N_FAIL" "$BATCH_DUR" "$ITEMS_JSON" >> "$BATCH_LEDGER"

# Regra 41: telemetria + incidente de uso do lote (além dos emits por item do escalate)
BATCH_RESULT="success"
[ "$N_FAIL" -eq 0 ] || BATCH_RESULT="failed"
bash "$REPO_ROOT/bin/emit-usage-feedback.sh" \
  --source batch \
  --task "batch-${RUN_ID}" \
  --result "$BATCH_RESULT" \
  --mode "$MODE" \
  --exit-code "$([ "$N_FAIL" -eq 0 ] && echo 0 || echo 1)" \
  --extra-json "{\"run_id\":\"$RUN_ID\",\"total\":$TOTAL,\"ok\":$N_OK,\"failed\":$N_FAIL,\"total_s\":$BATCH_DUR,\"items\":$ITEMS_JSON}" \
  2>/dev/null || true

[ "$N_FAIL" -eq 0 ] || exit 1
exit 0
