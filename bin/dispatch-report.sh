#!/bin/bash
# dispatch-report.sh — declared sources (rule 38) + ledger summary
#
# Uso: bin/dispatch-report.sh [--since YYYY-MM-DD] [--workdir DIR]
# Exit: 0 always for report (missing sources are listed, not silent)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
LEDGER="${LEDGER_FILE:-$REPO_ROOT/ledger/ledger.jsonl}"
SINCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:?}"; shift 2 ;;
    --workdir) WORKDIR="${2:?}"; shift 2 ;;
    *) echo "usage: dispatch-report.sh [--since YYYY-MM-DD] [--workdir DIR]" >&2; exit 3 ;;
  esac
done

WORKDIR="$(cd "$WORKDIR" 2>/dev/null && pwd -P)" || WORKDIR="$PWD"

echo "── Declared sources (rule 38) ──"
echo "workdir: $WORKDIR"

declare_source() {
  local name="$1" path="$2"
  if [ -f "$path" ]; then
    local lines
    lines=$(wc -l < "$path" | tr -d ' ')
    printf "  ✅ %-22s present  %s  (%s lines)\n" "$name" "$path" "$lines"
  elif [ -d "$path" ]; then
    printf "  ✅ %-22s present  %s  (dir)\n" "$name" "$path"
  else
    printf "  ❌ %-22s MISSING  %s\n" "$name" "$path"
  fi
}

# Canonical Oracfit + brownfield ledgers
declare_source "events"            "$WORKDIR/.dispatch/logs/events.jsonl"
declare_source "mode_ledger"       "$WORKDIR/.dispatch/ledger/mode.jsonl"
declare_source "escalate_ledger"   "$REPO_ROOT/ledger/ledger.jsonl"
declare_source "batch_ledger"      "$REPO_ROOT/ledger/batch-ledger.jsonl"
declare_source "usage"             "$WORKDIR/.dispatch/usage/usage.jsonl"

# Optional alternate env override
if [ -n "${LEDGER_FILE:-}" ]; then
  declare_source "LEDGER_FILE" "$LEDGER_FILE"
fi

echo ""
echo "── Legacy model report (escalate ledger) ──"

LEDGER="$LEDGER"
if [ ! -f "$LEDGER" ]; then
  echo "escalate ledger MISSING: $LEDGER (declared above)"
  echo "(no silent skip)"
  exit 0
fi

SINCE="$SINCE" LEDGER="$LEDGER" python3 <<'PY'
import json, os
from collections import defaultdict

ledger = os.environ["LEDGER"]
since = os.environ.get("SINCE", "")

rows = []
for line in open(ledger):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if since and d.get("started_at", "") < since:
        continue
    rows.append(d)

if not rows:
    print("Nenhum dispatch no período.")
    raise SystemExit

# Só registros com oracle são mensuráveis. Os antigos ficam separados para
# não inflar a estatística com dados de antes do mecanismo existir.
com_oraculo = [d for d in rows if d.get("oracle_status") not in (None, "", "sem-oraculo")]
sem_oraculo = [d for d in rows if d.get("oracle_status") in (None, "", "sem-oraculo")]

print(f"── Ledger: {len(rows)} dispatch(es) no período ──")
print(f"   com oráculo declarado: {len(com_oraculo)}")
print(f"   sem oráculo (cego):    {len(sem_oraculo)}")
print()

if com_oraculo:
    por_modelo = defaultdict(lambda: {"passou": 0, "falhou": 0, "killed": 0,
                                      "custo": 0.0, "seg": 0})
    for d in com_oraculo:
        mid = d.get("model", {}).get("id", "?")
        st = por_modelo[mid]
        if d.get("runner_exit") == "killed":
            st["killed"] += 1
        elif d.get("oracle_status") == "passou":
            st["passou"] += 1
        else:
            st["falhou"] += 1
        st["custo"] += float(d.get("cost_usd") or 0)
        st["seg"] += int(d.get("duration_seconds") or 0)

    print("── Resolveu de verdade? (oráculo, não log não-vazio) ──")
    print(f"{'modelo':<34}{'passou':>7}{'falhou':>7}{'morto':>7}{'US$':>9}{'seg':>7}")
    for mid, st in sorted(por_modelo.items(), key=lambda kv: -kv[1]["passou"]):
        print(f"{mid:<34}{st['passou']:>7}{st['falhou']:>7}{st['killed']:>7}"
              f"{st['custo']:>9.4f}{st['seg']:>7}")
    print()

    print("── Detalhe por dispatch ──")
    for d in com_oraculo:
        mid = d.get("model", {}).get("id", "?")
        marca = {"passou": "✅", "falhou": "❌"}.get(d.get("oracle_status"), "⚠️")
        if d.get("runner_exit") == "killed":
            marca = "⏱️"
        print(f"  {marca} {d.get('task_name','?'):<22} {mid:<32} "
              f"runner={d.get('runner_exit','?'):<7} oracle={d.get('oracle_exit','?')}")

if sem_oraculo:
    print()
    print(f"── {len(sem_oraculo)} dispatch(es) sem oráculo — não medem nada ──")
    print("   Estes registros só provam que o modelo rodou, não que resolveu.")
    print("   bin/check-spec.sh agora reprova spec sem seção ## Oráculo.")
PY

# ── 2.1 e 2.2 ───────────────────────────────────────────────────────────────
# Lacuna medida em 2026-07-29: `dispatch.sh` grava em ledger/ledger.jsonl, mas
# `dispatch-escalate.sh` (2.1) e `dispatch-batch.sh` (2.2) gravam em
# .dispatch/logs/*.jsonl. Este relatório existia desde o 2.0 e NUNCA tinha
# mostrado um único run de escalonamento ou de lote — a placa de "3 passou / 1
# falhou" descrevia só o dispatch simples. Escalada e lote eram invisíveis.
LOG_DIR="${LOG_DIR:-$REPO_ROOT/.dispatch/logs}"
ESC_LEDGER="$LOG_DIR/escalate-ledger.jsonl"
BATCH_LEDGER="$LOG_DIR/batch-ledger.jsonl"

ESC_LEDGER="$ESC_LEDGER" BATCH_LEDGER="$BATCH_LEDGER" python3 <<'PY'
import json, os
from collections import defaultdict


def load(path):
    if not path or not os.path.isfile(path):
        return []
    out = []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except Exception:
            continue
    return out


esc = load(os.environ.get("ESC_LEDGER"))
bat = load(os.environ.get("BATCH_LEDGER"))

if esc:
    print()
    print(f"── 2.1 escalonamento: {len(esc)} run(s) ──")
    por_tier = defaultdict(lambda: defaultdict(int))
    for d in esc:
        por_tier[d.get("result", "?")][d.get("tier", "-")] += 1
    print(f"{'resultado':<16}{'tier que resolveu':<20}{'n':>4}")
    for res, tiers in sorted(por_tier.items()):
        for tier, n in sorted(tiers.items(), key=lambda kv: -kv[1]):
            print(f"{res:<16}{tier:<20}{n:>4}")
    # blocked sem causa é o defeito que o fix de 2026-07-29 endereçou
    cegos = [d for d in esc
             if d.get("result") == "blocked" and not d.get("last_error")]
    if cegos:
        print(f"   ⚠️  {len(cegos)} 'blocked' com last_error vazio — anteriores ao fix "
              f"da assinatura de erro (incidents/2026-07-29-detector-de-travamento-"
              f"cego-a-oraculo-si.md)")

if bat:
    print()
    print(f"── 2.2 lotes: {len(bat)} run(s) ──")
    print(f"{'run_id':<26}{'mode':>5}{'ok':>4}{'falhou':>7}{'seg':>6}")
    for d in bat:
        print(f"{d.get('run_id','?'):<26}{d.get('mode','?'):>5}"
              f"{d.get('ok',0):>4}{d.get('failed',0):>7}{d.get('total_s',0):>6}")
    itens = [i for d in bat for i in d.get("items", [])]
    if itens:
        por_res = defaultdict(int)
        for i in itens:
            por_res[i.get("result", "?")] += 1
        print(f"   itens: " + " | ".join(f"{k}={v}" for k, v in sorted(por_res.items())))
        print(f"{'   item':<28}{'resultado':<16}{'seg':>5}")
        for i in itens:
            marca = "✅" if i.get("result") == "success" else "❌"
            print(f"   {marca} {i.get('task','?'):<24}{i.get('result','?'):<16}"
                  f"{i.get('duration_s',0):>5}")

if not esc and not bat:
    print()
    print("── nenhum run de 2.1/2.2 registrado em .dispatch/logs ──")
PY

# ── modo Oracfit (v2, fluxo principal) ──────────────────────────────────────
# Achado 2026-08-01 (docs-findings/audit-funcionalidades-meio-plugadas.md):
# "mode_ledger" era declarado como fonte na linha 42 mas NUNCA agregado aqui —
# mesma classe de lacuna que 2.1/2.2 tinham antes do fix de 2026-07-29, só que
# no modo que é o produto principal da v2 (bin/dispatch-mode.sh / oracfit run).
MODE_LEDGER="$WORKDIR/.dispatch/ledger/mode.jsonl"

MODE_LEDGER="$MODE_LEDGER" python3 <<'PY'
import json, os
from collections import defaultdict

path = os.environ.get("MODE_LEDGER")
rows = []
if path and os.path.isfile(path):
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except Exception:
            continue

if rows:
    print()
    print(f"── modo Oracfit (mode.jsonl): {len(rows)} run(s) ──")
    por_modelo = defaultdict(lambda: {"passou": 0, "falhou": 0, "custo": 0.0, "seg": 0.0})
    for d in rows:
        mid = d.get("model_id", "?")
        st = por_modelo[mid]
        if d.get("status") == "pass":
            st["passou"] += 1
        else:
            st["falhou"] += 1
        st["custo"] += float(d.get("estimated_cost") or 0)
        st["seg"] += float(d.get("flash_work_s") or 0)
    print(f"{'modelo':<34}{'passou':>7}{'falhou':>7}{'US$':>9}{'seg':>8}")
    for mid, st in sorted(por_modelo.items(), key=lambda kv: -kv[1]["passou"]):
        print(f"{mid:<34}{st['passou']:>7}{st['falhou']:>7}{st['custo']:>9.4f}{st['seg']:>8.1f}")
else:
    print()
    print("── nenhum run do modo Oracfit registrado (mode.jsonl vazio/ausente) ──")
PY
