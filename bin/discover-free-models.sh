#!/bin/bash
# discover-free-models.sh — Varre catálogos de providers em busca de novos modelos free
# Uso: bin/discover-free-models.sh
#
# Env obrigatória: DISPATCH_RUNNER (source adapters/<cli>/env.sh)
# Saída: lista de novos modelos free não registrados + atualização do registry
#
# Varre:
#   - opencode models (lista completa de modelos acessíveis)
#   - OpenRouter (IDs com :free)
#   - Groq
#   - NVIDIA via agent-vault
#
# Exit: 0 = nenhuma novidade, 2 = novos modelos encontrados, 3 = erro

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"
: "${DISPATCH_RUNNER_NAME:?Erro: env DISPATCH_RUNNER_NAME não definida. Rode: source adapters/<cli>/env.sh}"

[ -f "$REGISTRY" ] || { echo "❌ registry não encontrado: $REGISTRY" >&2; exit 3; }

echo "🔍 Descobrindo novos modelos free..."

# Puxa lista de modelos do opencode
OPENCODE_MODELS=$(mktemp)
source "$REPO_ROOT/adapters/opencode/env.sh" 2>/dev/null
opencode models 2>/dev/null > "$OPENCODE_MODELS"
OC_COUNT=$(wc -l < "$OPENCODE_MODELS")
echo "   Modelos no opencode: ${OC_COUNT}"

# IDs já no registry
REGS_JSON=$(mktemp)
python3 -c "
import json
d = json.load(open('$REGISTRY'))
for m in d['models']:
    id = m['id']
    print(id)
    for cli, hint in m.get('cli_hints', {}).items():
        if hint and hint != id:
            print(hint)
" > "$REGS_JSON"
REG_COUNT=$(wc -l < "$REGS_JSON")
echo "   IDs no registry: ${REG_COUNT}"

# Também reporta modelos free no registry sem verified_at (pendentes de smoke-test)
echo ""
echo "⏳ Modelos free no registry AGUARDANDO smoke-test:"
PENDENTES=$(mktemp)
python3 -c "
import json
d = json.load(open('$REGISTRY'))
for m in d.get('models', []):
    if m.get('tier') == 'free' and not m.get('verified_at'):
        id_status = m.get('id_status', '')[:60]
        print(f'  ⏳ {m[\"id\"]:45s} {id_status}')
" > "$PENDENTES"
PEND_COUNT=$(wc -l < "$PENDENTES")
[ "$PEND_COUNT" -gt 0 ] && cat "$PENDENTES" || echo "  ✅ Nenhum pendente"
rm -f "$PENDENTES"

# Filtra: modelos não no registry + free candidates
NOVOS=$(mktemp)
python3 -c "
import sys

# Carrega registry IDs
with open('$REGS_JSON') as f:
    known = set(line.strip() for line in f if line.strip())

novos = []
with open('$OPENCODE_MODELS') as f:
    for line in f:
        mid = line.strip()
        if not mid or mid in known:
            continue

        # Ignora modelos pagos (Claude, GPT, etc.)
        if '/' in mid:
            prov = mid.split('/')[0]
            name = mid.split('/')[-1].lower()
        else:
            prov = ''
            name = mid.lower()

        # Critério free
        is_free = (':free' in mid or
                   prov == 'groq' or
                   prov == 'openrouter' and ':free' in mid)

        if is_free:
            novos.append(mid)

for m in sorted(novos):
    print(m)
" > "$NOVOS"

NOVO_COUNT=$(wc -l < "$NOVOS")

if [ "$NOVO_COUNT" -eq 0 ]; then
    echo "   ✅ Nenhum novo modelo free encontrado."
    rm -f "$OPENCODE_MODELS" "$REGS_JSON" "$NOVOS"
    exit 0
fi

echo ""
echo "🆕 ${NOVO_COUNT} NOVOS MODELOS FREE ENCONTRADOS!"
echo "═══════════════════════════════════════════"
cat "$NOVOS"
echo "═══════════════════════════════════════════"

# Registra no arquivo de descoberta
DISCOVERY_LOG="$REPO_ROOT/.dispatch/discovered-free-$(date +%Y-%m-%d).txt"
mkdir -p "$(dirname "$DISCOVERY_LOG")"
cp "$NOVOS" "$DISCOVERY_LOG"
echo "   Log salvo em: $DISCOVERY_LOG"

rm -f "$OPENCODE_MODELS" "$REGS_JSON" "$NOVOS"
exit 2