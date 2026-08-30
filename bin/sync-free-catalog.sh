#!/bin/bash
# sync-free-catalog.sh — regenera data/free-catalog.json do feed estruturado
# dos providers (E5-M1/D2/D3/R2).
#
# Fontes (D2 = JSON estruturado, NUNCA scraping de README/tabela):
#   1. OpenRouter — GET https://openrouter.ai/api/v1/models (keyless READ);
#      free = pricing.prompt == 0 E pricing.completion == 0 medido no feed.
#      É por este critério que deepseek-v4-flash e gpt-oss-120b SAÍRAM do
#      catálogo: viraram pagos no feed (a própria classe do incidente E5).
#   2. Perna keyless — modelos tier=free do registry cujo cli_hint opencode
#      é `opencode/...` e que constam do `opencode models` LOCAL (catálogo
#      do CLI = verdade da perna zero-key, sem HTTP).
#   Providers com feed atrás de chave (Groq, NVIDIA…) entram aqui quando o
#   dono armazenar a credencial (lib-free-credentials.sh) — nunca antes.
#
# R2 — sync nunca sobrescreve bom com ruim: escreve em TEMP, valida
# (schema + contagem mínima + ref ∈ registry + free medido no feed), e só
# então move por cima. Qualquer falha = mantém o último snapshot bom,
# grita e exit 1. Um feed quebrado NUNCA mata o caminho default inteiro.
#
# Uso: bin/sync-free-catalog.sh
# Exit: 0 = catálogo regenerado; 1 = falha (snapshot anterior intacto)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"
CATALOG="$REPO_ROOT/data/free-catalog.json"
# Override só para teste (fixture de feed quebrado no D5): OR_FEED_ENDPOINT.
OR_ENDPOINT="${OR_FEED_ENDPOINT:-https://openrouter.ai/api/v1/models}"
MIN_MODELS=3   # a régua do D5: menos que isso, o caminho free está morto

fail() { echo "❌ sync-free-catalog: $*" >&2; exit 1; }

[ -f "$REGISTRY" ] || fail "registry ausente: $REGISTRY"

TMP_FEED=$(mktemp /tmp/free-catalog-feed-XXXXXX.json)
TMP_OUT=$(mktemp "$REPO_ROOT/data/free-catalog-XXXXXX.json")
trap 'rm -f "$TMP_FEED" "$TMP_OUT"' EXIT

# ── 1. Feed OpenRouter (JSON estruturado) ────────────────────────────────────
if ! bash "$REPO_ROOT/bin/with-timeout.sh" 25 curl -sf "$OR_ENDPOINT" -o "$TMP_FEED"; then
  fail "feed OpenRouter inacessível — snapshot anterior MANTIDO (R2)"
fi
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP_FEED" \
  || fail "feed OpenRouter não é JSON válido — snapshot anterior MANTIDO (R2)"

# ── 2. Catálogo local do opencode (perna keyless, sem HTTP) ─────────────────
OC_MODELS=$(bash "$REPO_ROOT/bin/with-timeout.sh" 25 opencode models 2>/dev/null) \
  || OC_MODELS=""
[ -n "$OC_MODELS" ] || echo "ⓘ opencode models indisponível — perna keyless fica vazia neste sync" >&2

# ── 3. Monta o novo catálogo ────────────────────────────────────────────────
STAMPED=$(OC_MODELS="$OC_MODELS" python3 - "$REGISTRY" "$TMP_FEED" <<'PYBUILD'
import json, os, sys
from datetime import datetime, timezone

reg = json.load(open(sys.argv[1], encoding="utf-8"))["models"]
feed = {m["id"]: m for m in json.load(open(sys.argv[2], encoding="utf-8"))["data"]}
oc_models = set(os.environ.get("OC_MODELS", "").split())

stamped_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
models, skipped = [], []

for m in reg:
    if m.get("tier") != "free":
        continue
    ref = m.get("id", "")
    hint = (m.get("cli_hints") or {}).get("opencode", "")
    if hint.startswith("opencode/"):
        if hint in oc_models:
            models.append({"ref": ref, "provider": "opencode", "keyless": True,
                           "context_length": None, "limits": {"rpm": None, "rpd": None}})
        else:
            skipped.append(f"{ref}: hint {hint} sumiu do catálogo local do opencode")
    elif hint.startswith("openrouter/"):
        native = hint[len("openrouter/"):]
        fm = feed.get(native)
        if fm is None:
            skipped.append(f"{ref}: {native} não está mais no feed OpenRouter")
            continue
        p = fm.get("pricing") or {}
        if str(p.get("prompt")) != "0" or str(p.get("completion")) != "0":
            skipped.append(f"{ref}: {native} NÃO é mais free no feed (pricing {p.get('prompt')}/{p.get('completion')}) — fora")
            continue
        models.append({"ref": ref, "provider": "openrouter", "keyless": False,
                       "context_length": fm.get("context_length"),
                       "limits": {"rpm": None, "rpd": None}})
    else:
        skipped.append(f"{ref}: sem hint opencode/openrouter — fora do escopo do sync")

keyless_total = sum(1 for m in models if m["keyless"])
catalog = {
    "stamped_at": stamped_at,
    "kind": "free-catalog/1",
    "source": {
        "kind": "sync-free-catalog.sh",
        "providers": [
            {"provider": "opencode", "keyless": True,
             "endpoint": "local: `opencode models`",
             "synced_at": stamped_at, "models_total": keyless_total},
            {"provider": "openrouter", "keyless": False,
             "endpoint": "https://openrouter.ai/api/v1/models",
             "synced_at": stamped_at,
             "models_total": len(models) - keyless_total,
             "free_criterion": "pricing.prompt == 0 and pricing.completion == 0 medido no feed"},
        ],
        "skipped": skipped,
    },
    "models": models,
}
json.dump(catalog, sys.stdout, indent=2, ensure_ascii=False)
PYBUILD
) || fail "montagem do catálogo falhou — snapshot anterior MANTIDO (R2)"

printf '%s' "$STAMPED" > "$TMP_OUT"

# ── 4. Validação antes do move (R2) ─────────────────────────────────────────
python3 - "$TMP_OUT" "$REGISTRY" "$MIN_MODELS" <<'PYVALIDATE'
import json, sys

cat_path, reg_path, min_models = sys.argv[1], sys.argv[2], int(sys.argv[3])
cat = json.load(open(cat_path, encoding="utf-8"))

assert cat.get("kind") == "free-catalog/1", "kind errado"
assert isinstance(cat.get("stamped_at"), str) and cat["stamped_at"], "stamped_at ausente"
assert isinstance(cat.get("source"), dict) and cat["source"].get("providers"), "source ausente"
models = cat.get("models")
assert isinstance(models, list), "models não é lista"

refs = [m.get("ref") for m in models]
assert all(refs), "entrada sem ref"
assert len(refs) == len(set(refs)), "ref duplicado no catálogo"
assert len(refs) >= min_models, f"catálogo com {len(refs)} refs (< {min_models}) — caminho free morto, snapshot anterior vale mais"

reg_ids = {m.get("id") for m in json.load(open(reg_path, encoding="utf-8"))["models"]}
fora = [r for r in refs if r not in reg_ids]
assert not fora, f"refs fora do registry (verdade do runner): {fora}"

for m in models:
    assert m.get("provider") in ("opencode", "openrouter"), f"provider desconhecido: {m.get('provider')}"
    assert isinstance(m.get("keyless"), bool), "keyless não é bool"
    assert m.get("limits", {}).keys() >= {"rpm", "rpd"}, "limits sem rpm/rpd (null ok, chave tem de existir)"

print(f"validado: {len(refs)} refs ({sum(1 for m in models if m['keyless'])} keyless)")
PYVALIDATE
VALID_RC=$?
[ "$VALID_RC" -eq 0 ] || fail "validação do novo catálogo reprova — snapshot anterior MANTIDO (R2)"

# ── 5. Move atômico ──────────────────────────────────────────────────────────
mv "$TMP_OUT" "$CATALOG" || fail "move atômico falhou"
echo "✅ catálogo free regenerado: $CATALOG ($(python3 -c "import json;print(len(json.load(open('$CATALOG'))['models']))" 2>/dev/null || echo '?') refs)"
exit 0
