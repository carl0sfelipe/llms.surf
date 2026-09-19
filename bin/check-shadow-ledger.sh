#!/usr/bin/env bash
# check-shadow-ledger.sh — D-NEXT-3: o medidor que decide o cutover LLMS_KERNEL=on.
#
# Lê o ledger de dispatch e resume as linhas gravadas em LLMS_KERNEL=shadow
# (campo `kernel_shadow_diff`, escrito por bin/ledger-finalize.sh a partir do
# sidecar de bin/run-with-fallback.sh — T18). Exit:
#   0  nenhuma linha em shadow (kernel ainda não observou tráfego) — informa
#   0  todas as linhas em shadow têm diff 0
#   1  alguma linha tem diff != 0 — lista task/started_at/diff (até 10)
#   3  uso / ledger ilegível
#
# O cutover (PR de uma linha em run-with-fallback.sh) leva a saída deste
# script no corpo. Não decide o N de runs — o dono lê "dias cobertos" e o
# ciclo de Lineup (D6.6) e decide.
#
# Uso: bin/check-shadow-ledger.sh [ledger.jsonl] [--json]
#      LEDGER_DIR=<dir> sobrepõe o default (repo/ledger).

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER=""
JSON=0
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) LEDGER="$a" ;;
  esac
done
[ -n "$LEDGER" ] || LEDGER="${LEDGER_DIR:-$ROOT/ledger}/ledger.jsonl"

if [ ! -f "$LEDGER" ]; then
  echo "check-shadow-ledger: ledger não encontrado: $LEDGER" >&2
  exit 3
fi

LEDGER="$LEDGER" JSON="$JSON" python3 - <<'PY'
import json, os, sys
path = os.environ["LEDGER"]
as_json = os.environ["JSON"] == "1"
rows, bad = [], 0
with open(path, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            bad += 1
            continue
        if isinstance(r, dict) and "kernel_shadow_diff" in r:
            rows.append(r)

def is_zero(v):
    return str(v).strip() == "0"

diffs = [r for r in rows if not is_zero(r.get("kernel_shadow_diff"))]
dates = sorted(str(r.get("started_at", ""))[:10] for r in rows if r.get("started_at"))
crates = sorted({str((r.get("policy_version") or {}).get("crate", "")) for r in rows} - {""})
shas = sorted({str((r.get("policy_version") or {}).get("kernel_sha", ""))[:12] for r in rows} - {""})
out = {
    "ledger": path,
    "shadow_rows": len(rows),
    "diff_rows": len(diffs),
    "diff_sum": sum(1 for _ in diffs),
    "first": dates[0] if dates else None,
    "last": dates[-1] if dates else None,
    "days_covered": len(set(dates)),
    "policy_version_crates": crates,
    "kernel_shas": shas,
    "malformed_lines_skipped": bad,
    "verdict": "no-shadow-traffic" if not rows else ("diff-zero" if not diffs else "diff-nonzero"),
    "diffs": [
        {"task_name": r.get("task_name"), "started_at": r.get("started_at"),
         "kernel_shadow_diff": r.get("kernel_shadow_diff"),
         "provider_efetivo_ref": r.get("provider_efetivo_ref")}
        for r in diffs[:10]
    ],
}
if as_json:
    print(json.dumps(out, ensure_ascii=False))
else:
    print(f"ledger: {path}")
    if not rows:
        print("shadow: 0 linhas — o kernel ainda não observou tráfego (LLMS_KERNEL=shadow no env.sh do adapter).")
    else:
        print(f"shadow: {len(rows)} linhas · diff!=0: {len(diffs)} · dias cobertos: {out['days_covered']} ({out['first']} → {out['last']})")
        if crates or shas:
            print(f"policy_version: crate {', '.join(crates) or '?'} · kernel_sha {', '.join(shas) or '?'}")
        for d in out["diffs"]:
            print(f"  DIFF task={d['task_name']} started_at={d['started_at']} kernel_shadow_diff={d['kernel_shadow_diff']} ref={d['provider_efetivo_ref']}")
        if len(diffs) > 10:
            print(f"  … e mais {len(diffs) - 10}")
    if bad:
        print(f"(linhas malformadas puladas: {bad})")
    print(f"veredito: {out['verdict']}")
sys.exit(1 if diffs else 0)
PY
