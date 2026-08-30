#!/bin/bash
# audit-registry-ids.sh — Varre model-registry.json e valida cada model_id
# contra os catalogos reais (opencode local + OpenRouter).
#
# Incidente incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md — id so entra no registry apos existir no catalogo
# real do provider. NAO-ENCONTRADO nao prova modelo falso (pode ser provider
# sem catalogo publico, ex: NVIDIA/Groq exigem chave), mas marca o que
# precisa verificacao manual.
#
# Uso: bin/audit-registry-ids.sh [--stamp]
#
# --stamp (E5-M2, gate na porta): grava o status medido de volta no
# model-registry.json (id_status + id_checked_at por modelo). Consumidores
# (resolve-tier, run-with-fallback) recusam FANTASMA/NAO-ENCONTRADO/
# NAO-VERIFICADO na porta — o registry vira a única verdade, inclusive de
# liveza. Sem --stamp o script só reporta (comportamento original).
#
# Dependencias: python3, curl, bash 4+
# Todo comando de rede passa por with-timeout.sh (regra 12).

set -uo pipefail

STAMP=0
for arg in "$@"; do
  case "$arg" in
    --stamp) STAMP=1 ;;
    *) echo "Uso: audit-registry-ids.sh [--stamp]" >&2; exit 3 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"
WITH_TIMEOUT="$REPO_ROOT/bin/with-timeout.sh"

[ -f "$MODEL_REGISTRY" ] || { echo "Erro: $MODEL_REGISTRY nao encontrado"; exit 3; }
[ -x "$WITH_TIMEOUT" ]   || { echo "Erro: $WITH_TIMEOUT nao encontrado ou sem execucao"; exit 3; }

# ── 1. Catalogo local (opencode models) ──
echo "Obtendo catalogo local (opencode models) ..." >&2
OC_CATALOG=$(bash "$WITH_TIMEOUT" 30 opencode models 2>/dev/null)
OC_EXIT=$?
if [ "$OC_EXIT" -ne 0 ]; then
  echo "Erro: opencode models falhou (exit=$OC_EXIT)" >&2
  exit 2
fi

# ── 2. Catalogo OpenRouter ──
echo "Obtendo catalogo OpenRouter ..." >&2
OR_JSON=$(mktemp /tmp/or-catalog-XXXXXX)
bash "$WITH_TIMEOUT" 20 curl -s https://openrouter.ai/api/v1/models > "$OR_JSON"
OR_EXIT=$?
OR_LIST=""
if [ "$OR_EXIT" -eq 0 ] && [ -s "$OR_JSON" ]; then
  OR_LIST=$(python3 -c "
import json, sys
data = json.load(open('$OR_JSON'))
for item in data.get('data', []):
    print(item['id'])
" 2>/dev/null) || OR_LIST=""
else
  echo "Aviso: OpenRouter falhou (exit=$OR_EXIT) — checagem OR desativada" >&2
fi
rm -f "$OR_JSON"

# ── 3. Extrair pares (id, hint) do registry ──
REGISTRY_PAIRS=$(mktemp /tmp/registry-pairs-XXXXXX)
python3 -c "
import json, sys
d = json.load(open('$MODEL_REGISTRY'))
for m in d.get('models', []):
    mid = m.get('id', '')
    hint = (m.get('cli_hints') or {}).get('opencode', '')
    if mid:
        sys.stdout.write(mid + '\t' + hint + '\n')
" 2>/dev/null > "$REGISTRY_PAIRS"

# ── 4. Validar cada modelo ──
EXISTE=0
FANTASMA=0
PROVAVEL=0
NAO_ENCONTRADO=0
STATUS_FILE=$(mktemp /tmp/registry-status-XXXXXX)

echo ""
echo "Modelo (registry id)                            Hint (opencode)                Status          Detalhe"
echo "-------------------------------------------------------------------------------------------------------------"

while IFS=$'\t' read -r mid hint; do
  [ -z "$mid" ] && continue

  if [ -n "$hint" ]; then
    # ── Modelo com hint: valida o hint contra os catalogos ──
    FOUND=0

    if echo "$OC_CATALOG" | grep -Fxq "$hint" 2>/dev/null; then
      FOUND=1
    fi

    if [[ "$hint" == openrouter/* ]]; then
      or_part="${hint#openrouter/}"
      if [ -n "$or_part" ] && [ -n "$OR_LIST" ] && echo "$OR_LIST" | grep -Fxq "$or_part" 2>/dev/null; then
        FOUND=1
      fi
    fi

    if [ "$FOUND" -eq 1 ]; then
      STATUS="EXISTE"
      DETALHE=""
      EXISTE=$((EXISTE+1))
    else
      STATUS="FANTASMA"
      DETALHE="hint sem correspondencia em catalogo"
      FANTASMA=$((FANTASMA+1))
    fi

    printf '%s\t%s\n' "$mid" "$STATUS" >> "$STATUS_FILE"
    printf "%-48s %-30s %-15s %s\n" "$mid" "$hint" "$STATUS" "$DETALHE"
    continue
  fi

  # ── Modelo sem hint: valida o id cru contra os catalogos ──
  MATCH_LINE=""
  MATCH_ORIGEM=""

  if echo "$OC_CATALOG" | grep -F -- "$mid" >/dev/null 2>&1; then
    MATCH_LINE=$(echo "$OC_CATALOG" | grep -F -- "$mid" | head -1)
    MATCH_ORIGEM="opencode"
  fi

  if [ -z "$MATCH_LINE" ] && [ -n "$OR_LIST" ]; then
    if echo "$OR_LIST" | grep -F -- "$mid" >/dev/null 2>&1; then
      MATCH_LINE=$(echo "$OR_LIST" | grep -F -- "$mid" | head -1)
      MATCH_ORIGEM="openrouter"
    else
      tail_part="${mid##*/}"
      if [ -n "$tail_part" ] && echo "$OR_LIST" | grep -F -- "$tail_part" >/dev/null 2>&1; then
        MATCH_LINE=$(echo "$OR_LIST" | grep -F -- "$tail_part" | head -1)
        MATCH_ORIGEM="openrouter"
      fi
    fi
  fi

  if [ -n "$MATCH_LINE" ]; then
    STATUS="PROVAVEL"
    DETALHE="casou em $MATCH_ORIGEM: $MATCH_LINE"
    PROVAVEL=$((PROVAVEL+1))
  else
    STATUS="NAO-ENCONTRADO"
    DETALHE="nada parecido em catalogo nenhum"
    NAO_ENCONTRADO=$((NAO_ENCONTRADO+1))
  fi

  printf '%s\t%s\n' "$mid" "$STATUS" >> "$STATUS_FILE"
  printf "%-48s %-30s %-15s %s\n" "$mid" "(sem hint)" "$STATUS" "$DETALHE"
done < "$REGISTRY_PAIRS"

rm -f "$REGISTRY_PAIRS"

# ── 4.5 Gravar a liveza medida no registry (E5-M2) ──
# Escrita atômica: temp no mesmo dir + move. Formato byte-compatível com o
# arquivo atual (indent 2, ensure_ascii=False, sem newline final).
if [ "$STAMP" -eq 1 ]; then
  python3 - "$MODEL_REGISTRY" "$STATUS_FILE" <<'PYSTAMP' || echo "Erro: --stamp não conseguiu gravar o registry" >&2
import json, os, sys, tempfile
from datetime import datetime, timezone

reg_path, status_path = sys.argv[1], sys.argv[2]
status = {}
with open(status_path, encoding="utf-8") as f:
    for line in f:
        mid, st = line.rstrip("\n").split("\t", 1)
        status[mid] = st

with open(reg_path, encoding="utf-8") as f:
    reg = json.load(f)

checked_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
stamped = 0
for m in reg.get("models", []):
    mid = m.get("id", "")
    if mid in status:
        m["id_status"] = status[mid]
        m["id_checked_at"] = checked_at
        stamped += 1

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(reg_path), suffix=".tmp")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(reg, f, indent=2, ensure_ascii=False)
os.replace(tmp, reg_path)
print(f"stamp: {stamped} modelos com id_status gravado em {reg_path} (checked_at {checked_at})", file=sys.stderr)
PYSTAMP
fi
rm -f "$STATUS_FILE"

# ── 5. Resumo ──
echo ""
echo "═══ RESUMO ═══"
echo "  EXISTE:          $EXISTE"
echo "  PROVAVEL:        $PROVAVEL"
echo "  NAO-ENCONTRADO:  $NAO_ENCONTRADO"
echo "  FANTASMA:        $FANTASMA"
echo "  TOTAL:           $((EXISTE + PROVAVEL + NAO_ENCONTRADO + FANTASMA))"
echo ""

if [ "$FANTASMA" -gt 0 ] || [ "$NAO_ENCONTRADO" -gt 0 ]; then
  exit 1
fi
exit 0
