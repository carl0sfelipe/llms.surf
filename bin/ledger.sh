#!/bin/bash
# ledger.sh — Consulta o ledger permanente de dispatches
# Uso: bash bin/ledger.sh [task_name]
# Sem args: tabela resumo (mais recente primeiro)
# Com task_name: registro completo + comando para voltar na sessao

set -euo pipefail

LEDGER_FILE="$(cd "$(dirname "$0")/.." && pwd)/ledger/ledger.jsonl"

if [ ! -f "$LEDGER_FILE" ] || [ ! -s "$LEDGER_FILE" ]; then
  echo "Ledger vazio — nenhum dispatch registrado ainda."
  exit 0
fi

if [ $# -eq 0 ]; then
  python3 -c '
import json, sys

records = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            records.append(json.loads(line))

records.reverse()

hdr = "{:<25} {:<30} {:<10} {:<10} {:<10} {:<10} {:<38}".format(
    "TASK", "MODEL", "DURACAO", "TOK_IN", "TOK_OUT", "CUSTO", "SESSION_ID")
sep = "-" * len(hdr)
print(hdr)
print(sep)

for r in records:
    task = r["task_name"][:24]
    model = (r["model"].get("id", "") or "")[:29]
    dur = str(r["duration_seconds"]) + "s"
    tin = r["tokens_input"]
    tout = r["tokens_output"]
    cost = "${:.4f}".format(r["cost_usd"]) if r["cost_usd"] else "0"
    sid = r["session_id"][:37] if r["session_id"] else "-"
    print("{:<25} {:<30} {:<10} {:<10} {:<10} {:<10} {:<38}".format(
        task, model, dur, tin, tout, cost, sid))
' "$LEDGER_FILE"
else
  TASK_NAME="$1"
  python3 -c '
import json, sys

task_name = sys.argv[2]
with open(sys.argv[1]) as f:
    records = [json.loads(l) for l in f if l.strip()]
    records.reverse()
    for r in records:
        if r["task_name"] == task_name:
            print(json.dumps(r, indent=2, ensure_ascii=False))
            sid = r.get("session_id", "")
            if sid:
                print(f"\nPara voltar nessa sessao: opencode -s {sid}")
            sys.exit(0)
    print(f"Task nao encontrada: {task_name}")
    sys.exit(1)
' "$LEDGER_FILE" "$TASK_NAME"
fi
