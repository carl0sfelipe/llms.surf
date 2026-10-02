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
# Uso: bin/check-shadow-ledger.sh [ledger.jsonl ...] [--json]
#      Sem argumento lê os DOIS ledgers que recebem shadow: repo/ledger/ledger.jsonl
#      (dispatch.sh → ledger-finalize, campo policy_version objeto) e
#      <workdir>/.dispatch/ledger/mode.jsonl (dispatch-mode/stages, chaves
#      planas policy_version_crate/sha). LEDGER_DIR / ORACFIT_WORKDIR sobrepõem.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGERS=()
JSON=0
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) LEDGERS+=("$a") ;;
  esac
done
if [ "${#LEDGERS[@]}" -eq 0 ]; then
  central="${LEDGER_DIR:-$ROOT/ledger}/ledger.jsonl"
  mode="${ORACFIT_WORKDIR:-$ROOT}/.dispatch/ledger/mode.jsonl"
  [ -f "$central" ] && LEDGERS+=("$central")
  [ -f "$mode" ] && LEDGERS+=("$mode")
  if [ "${#LEDGERS[@]}" -eq 0 ]; then
    echo "check-shadow-ledger: nenhum ledger encontrado ($central, $mode)" >&2
    exit 3
  fi
else
  for l in "${LEDGERS[@]}"; do
    if [ ! -f "$l" ]; then
      echo "check-shadow-ledger: ledger não encontrado: $l" >&2
      exit 3
    fi
  done
fi

LEDGERS_NL="$(printf '%s\n' "${LEDGERS[@]}")" JSON="$JSON" python3 - <<'PY'
import json, os, sys
paths = [p for p in os.environ["LEDGERS_NL"].split("\n") if p]
as_json = os.environ["JSON"] == "1"
rows, bad = [], 0
for path in paths:
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
                r["_ledger"] = path
                rows.append(r)

def is_zero(v):
    return str(v).strip() == "0"

def pv(r, key, flat):
    obj = r.get("policy_version")
    if isinstance(obj, dict) and obj.get(key):
        return str(obj[key])
    return str(r.get(flat, "") or "")

def when(r):
    return str(r.get("started_at") or r.get("ts") or "")[:10]

diffs = [r for r in rows if not is_zero(r.get("kernel_shadow_diff"))]
dates = sorted(when(r) for r in rows if when(r))
crates = sorted({pv(r, "crate", "policy_version_crate") for r in rows} - {""})
shas = sorted({pv(r, "kernel_sha", "policy_version_sha")[:12] for r in rows} - {""})
path = ", ".join(paths)
out = {
    "ledgers": paths,
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
        {"task_name": r.get("task_name") or r.get("task"), "started_at": r.get("started_at") or r.get("ts"),
         "kernel_shadow_diff": r.get("kernel_shadow_diff"),
         "provider_efetivo_ref": r.get("provider_efetivo_ref"), "ledger": r.get("_ledger")}
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
