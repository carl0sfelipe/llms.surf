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
points_doc = json.load(open(points_f, encoding="utf-8"))
points = points_doc["points"]
export = json.load(open(export_f, encoding="utf-8"))
contrib = {str(c["handle"]).lstrip("@"): int(c.get("points", 0))
           for c in export.get("contributors", [])}

# E6 4.5: janela de conversão de referral atrás de dial. Modo default
# (any_contribution) = comportamento v0 da S13. Modo proposed pelo Fable
# (first_signed_run_within): converte só se o 1º signed run do indicado
# ocorrer em <= window_days da criação da conta. Determinístico: compara
# só timestamps que VÊM dos inputs (nada de relógio aqui).
conv = points_doc.get("referral_conversion") or {}
conv_mode = str(conv.get("mode", "any_contribution"))
conv_window = conv.get("window_days")
timeline = {str(x["handle"]).lstrip("@").lower(): x
            for x in export.get("timeline") or []}


def _referral_converts(referred_handle):
    origin = by_handle.get(referred_handle)
    if origin is None or origin["contribution_points"] <= 0:
        # v0: indicado precisa existir na fila E ter contribuído
        return False, "no-origin"
    if conv_mode == "first_signed_run_within" and conv_window:
        t = timeline.get(referred_handle)
        if not t or not t.get("first_signed_run_at") or not t.get("account_created_at"):
            return False, "no-signed-run"
        from datetime import datetime

        def _ts(v):
            return datetime.fromisoformat(str(v).replace("Z", "+00:00"))
        delta_days = (_ts(t["first_signed_run_at"]) - _ts(t["account_created_at"])).total_seconds() / 86400
        if delta_days <= float(conv_window):
            return True, f"signed run em {delta_days:.1f}d"
        return False, f"signed run fora da janela ({delta_days:.1f}d > {conv_window}d)"
    return True, "any contribution"

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
        # anti-sockpuppet: o indicado precisa existir E ter contribuído
        # (e, com o dial first_signed_run_within, dentro da janela)
        converted, reason = _referral_converts(ref)
        e["referral_converted"] = converted
        e["referral_note"] = reason
        if converted:
            total += ref_p
    else:
        e["referral_converted"] = None
    e["points_total"] = total

# ── tier + fatia do pool (E7 2026-08-31) ────────────────────────────────
# Tier sai SO de threshold_points. O campo "requires" da tabela ("1+ signed
# run", "3+ reproductions") e intencao declarada e NAO e verificavel aqui: o
# export traz pontos AGREGADOS, nao o detalhe por tipo de contribuicao. Por
# isso a saida declara tier_basis="points_only" -- a maquina nao finge
# conferir o que nao ve. No dia em que o export trouxer o detalhe, isto passa
# a checar de verdade e o tier_basis muda junto.
#
# A fatia e proporcional ao peso do tier: pool * peso / soma_dos_pesos, em
# inteiros. Ninguem recebe numero fixo prometido -- numero fixo quebra se
# aparecer gente demais. O resto da divisao fica DECLARADO em
# token_pool.unallocated em vez de sumir num arredondamento.
tiers_doc = points_doc.get("tiers") or {}
pool_doc = points_doc.get("token_pool") or {}
journey = [str(x) for x in (tiers_doc.get("journey") or [])]


def _tier_key(name):
    return name.lower().replace(" ", "_")


# ordem decrescente de corte: ganha o tier mais alto que a pessoa alcanca
ladder = []
for name in journey:
    conf = tiers_doc.get(_tier_key(name))
    if isinstance(conf, dict) and conf.get("threshold_points") is not None:
        ladder.append((int(conf["threshold_points"]), name, _tier_key(name)))
ladder.sort(key=lambda x: -x[0])

weights = pool_doc.get("weights") or {}
total_pool = int(pool_doc.get("total_tokens") or 0)

for e in entries:
    e["tier"] = None
    e["tier_weight"] = 0
    for threshold, name, key in ladder:
        if e["points_total"] >= threshold:
            e["tier"] = name
            e["tier_weight"] = int(weights.get(key, 0))
            break

weight_sum = sum(e["tier_weight"] for e in entries)
allocated = 0
for e in entries:
    share = (total_pool * e["tier_weight"]) // weight_sum if weight_sum else 0
    e["token_share"] = share
    allocated += share

doc = {
    # byte-determinismo: nada de relógio — a proveniência é o fingerprint
    # dos inputs (git history do lineup.json é a auditoria inteira)
    "inputs_sha256": {
        "issues": __import__("hashlib").sha256(open(issues_f, "rb").read()).hexdigest(),
        "export": __import__("hashlib").sha256(open(export_f, "rb").read()).hexdigest(),
        "points": __import__("hashlib").sha256(open(points_f, "rb").read()).hexdigest(),
    },
    "machine": "bin/lineup-build.sh",
    "points_table_dial": points_doc.get("dial", "unknown"),
    "tier_basis": "points_only",
    "token_pool": {
        "total_tokens": total_pool,
        "allocated": allocated,
        "unallocated": total_pool - allocated if weight_sum else total_pool,
        "weight_sum": weight_sum,
    },
    "entries": entries,
}
with open(out_f, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
print(f"lineup-build: {len(entries)} entrada(s) → {out_f}")
PY
