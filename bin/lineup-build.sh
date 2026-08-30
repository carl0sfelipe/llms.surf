#!/bin/bash
# lineup-build.sh — S13: o medidor do The Lineup ($0, auditável por git).
# Entradas: issues da waitlist (formato gh api) + export por-contribuidor
# do bestmodel + tabela de pontos (data/lineup-points.json, dial do dono).
# Saída: data/lineup.json, determinística — mesmas entradas, mesmo byte.
# Anti-sockpuppet do plano: indicação SÓ converte se o indicado existe na
# lista E contribuiu (contribution_points > 0).
#
# Uso (live):  gh api 'repos/carl0sfelipe/llms.surf/issues?labels=waitlist&state=all&per_page=200' > /tmp/issues.json
#              bash bin/lineup-build.sh --issues /tmp/issues.json --export contrib.json
# Uso (teste): --issues fixture.json --export fixture.json --out /tmp/out.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISSUES="" EXPORT="" POINTS="" OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --issues) ISSUES="${2:?}"; shift 2 ;;
    --export) EXPORT="${2:?}"; shift 2 ;;
    --points) POINTS="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    *) echo "lineup-build: argumento desconhecido: $1" >&2; exit 3 ;;
  esac
done
[ -n "$ISSUES" ] && [ -f "$ISSUES" ] || { echo "lineup-build: --issues obrigatório" >&2; exit 3; }
[ -n "$EXPORT" ] && [ -f "$EXPORT" ] || { echo "lineup-build: --export obrigatório" >&2; exit 3; }
[ -n "$POINTS" ] || POINTS="$ROOT/data/lineup-points.json"
[ -f "$POINTS" ] || { echo "lineup-build: tabela de pontos não encontrada: $POINTS" >&2; exit 3; }
[ -n "$OUT" ] || OUT="$ROOT/data/lineup.json"

python3 - "$ISSUES" "$EXPORT" "$POINTS" "$OUT" <<'PY'
import json, re, sys

issues_f, export_f, points_f, out_f = sys.argv[1:5]
points = json.load(open(points_f, encoding="utf-8"))["points"]
export = json.load(open(export_f, encoding="utf-8"))
contrib = {str(c["handle"]).lstrip("@"): int(c.get("points", 0))
           for c in export.get("contributors", [])}

REF_RE = re.compile(r"referred by:\s*@([A-Za-z0-9-]+)", re.I)
entries = []
for it in json.load(open(issues_f, encoding="utf-8")):
    body = it.get("body") or ""
    handle = str((it.get("user") or {}).get("login", ""))
    if not handle:
        continue
    referred = REF_RE.search(body)
    referred = referred.group(1).lower() if referred else None
    contributions = contrib.get(handle.lower(), 0)
    entries.append({
        "handle": handle,
        "issue": int(it["number"]),
        "joined_at": it["created_at"],
        "referred_by": referred,
        "contribution_points": contributions,
    })

# determinismo: ordem de fila = created_at do issue (empate: número);
# issue duplicado na resposta da API entra UMA vez (primeiro ganha)
entries.sort(key=lambda e: (e["joined_at"], e["issue"]))
seen = set()
unique = []
for e in entries:
    if e["issue"] in seen:
        continue
    seen.add(e["issue"])
    unique.append(e)
entries = unique
by_handle = {e["handle"].lower(): e for e in entries}

join_p = int(points["join_issue"])
ref_p = int(points["referral_converted"])
for e in entries:
    total = join_p + e["contribution_points"]
    ref = e.get("referred_by")
    if ref and ref != e["handle"].lower():
        origin = by_handle.get(ref)
        # anti-sockpuppet: o indicado precisa existir E ter contribuído
        if origin and origin["contribution_points"] > 0:
            total += ref_p
            e["referral_converted"] = True
        else:
            e["referral_converted"] = False
    else:
        e["referral_converted"] = None
    e["points_total"] = total

doc = {
    # byte-determinismo: nada de relógio — a proveniência é o fingerprint
    # dos inputs (git history do lineup.json é a auditoria inteira)
    "inputs_sha256": {
        "issues": __import__("hashlib").sha256(open(issues_f, "rb").read()).hexdigest(),
        "export": __import__("hashlib").sha256(open(export_f, "rb").read()).hexdigest(),
        "points": __import__("hashlib").sha256(open(points_f, "rb").read()).hexdigest(),
    },
    "machine": "bin/lineup-build.sh",
    "points_table_dial": json.load(open(points_f, encoding="utf-8")).get("dial", "unknown"),
    "entries": entries,
}
with open(out_f, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
print(f"lineup-build: {len(entries)} entrada(s) → {out_f}")
PY
