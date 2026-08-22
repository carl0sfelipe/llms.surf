#!/bin/bash
# diagnose-hang.sh — classifica um travamento de dispatch em vez de adivinhar
# Uso: bin/diagnose-hang.sh [<model_id>] [<minutos_atras>]
#
# Por que existe: em 2026-07-24/25 o mesmo sintoma ("pendura, sem erro no stderr")
# teve pelo menos TRÊS causas diferentes — agente concorrente, id de modelo
# fantasma, e contexto do modelo pequeno demais para o prompt base do opencode.
# Diagnosticar por plausibilidade errou todas as vezes; o que separa os casos é
# uma pergunta objetiva: **a sessão existe no banco?**
#
#   sessão existe + erro gravado  → causa está no banco (leia o erro)
#   sessão existe + sem erro      → resposta em andamento ou perdida
#   sessão NÃO existe             → travou antes de falar com o provider
#
# O erro fica no BANCO, não no stderr — `--print-logs` não mostra. Foi isso que
# tornou o sintoma opaco por horas.
#
# Env opcional: DB_PATH (default: store do opencode)
# Exit: 0 sempre (é ferramenta de diagnóstico, não gate)

set -uo pipefail

DB="${DB_PATH:-$HOME/.local/share/opencode/opencode.db}"
MODELO="${1:-}"
MINUTOS="${2:-30}"

[ -f "$DB" ] || { echo "❌ banco não encontrado: $DB" >&2; exit 0; }

echo "═══ Diagnóstico de travamento (últimos ${MINUTOS}min) ═══"
echo

echo "── 1. Concorrência (regras 8 e 19) ──"
BUSY=""
for P in "opencode run" "^opencode$" "hermes -z" "hermes chat" "claude -p"; do
  PIDS=$(pgrep -f "$P" 2>/dev/null | tr '\n' ' ')
  [ -n "$PIDS" ] && BUSY="$BUSY  $P → ${PIDS}\n"
done
if [ -n "$BUSY" ]; then
  printf "  ⚠️  agentes ativos agora:\n%b" "$BUSY"
  echo "  → dois agentes no mesmo store contendem e penduram o dispatch"
else
  echo "  ✅ nenhum agente concorrente"
fi
echo

echo "── 2. Órfãos (incidente incidents/2026-07-25-grupo-nao-basta-neto-com-set-m-escapa.md) ──"
ORFAOS=$(pgrep -f 'opencode run' 2>/dev/null | wc -l | tr -d ' ')
if [ "$ORFAOS" != "0" ]; then
  echo "  ⚠️  $ORFAOS processo(s) 'opencode run' vivos — podem ser órfãos de teto anterior"
  ps -o pid,etime,command -p $(pgrep -f 'opencode run' | tr '\n' ',' | sed 's/,$//') 2>/dev/null | tail -n +2 | cut -c1-100
else
  echo "  ✅ zero órfãos"
fi
echo

echo "── 3. Sessões criadas no período ──"
SESSOES=$(sqlite3 "$DB" "SELECT COUNT(DISTINCT session_id) FROM message WHERE time_created > (strftime('%s','now')-${MINUTOS}*60)*1000;" 2>/dev/null || echo "?")
echo "  sessões com mensagem: $SESSOES"
if [ "$SESSOES" = "0" ]; then
  echo "  ⚠️  NENHUMA sessão criada → travou ANTES de falar com o provider (modo opaco)"
  echo "     Checar: id do modelo existe? (bin/audit-registry-ids.sh) · rede · estado do opencode"
else
  echo "  → sessão existe: o erro, se houver, está no banco (item 4)"
fi
echo

echo "── 4. Erros gravados no banco (NÃO aparecem no stderr) ──"
sqlite3 "$DB" "SELECT data FROM message WHERE time_created > (strftime('%s','now')-${MINUTOS}*60)*1000;" 2>/dev/null \
| MODELO="$MODELO" python3 -c '
import sys, json, os
from collections import Counter
alvo = os.environ.get("MODELO", "")
c = Counter()
total = 0
for linha in sys.stdin:
    linha = linha.strip()
    if not linha:
        continue
    try:
        d = json.loads(linha)
    except Exception:
        continue
    if d.get("role") != "assistant":
        continue
    total += 1
    mid = d.get("modelID", "?")
    if alvo and alvo not in mid:
        continue
    err = d.get("error") or {}
    if not err:
        continue
    msg = (err.get("data") or {}).get("message") or err.get("name") or "?"
    c[(d.get("providerID", "?"), mid, d.get("mode", "?"), str(msg)[:90])] += 1
if not c:
    print(f"  ✅ nenhum erro gravado ({total} respostas de assistente no período)")
else:
    for (prov, mid, mode, msg), n in c.most_common(10):
        print(f"  ❌ {n}x {prov}/{mid} [{mode}]")
        print(f"       {msg}")
' 2>/dev/null || echo "  (falha ao ler mensagens)"
echo

echo "── 5. Contexto do modelo suporta o prompt base? ──"
if [ -n "$MODELO" ]; then
  MODELO="$MODELO" REG="${MODEL_REGISTRY:-$(cd "$(dirname "$0")/.." && pwd)/model-registry.json}" python3 -c '
import json, os
try:
    d = json.load(open(os.environ["REG"]))
except Exception as e:
    raise SystemExit(f"  (registry ilegível: {e})")
alvo = os.environ["MODELO"]
for m in d["models"]:
    ids = [m["id"], *(m.get("cli_hints", {}) or {}).values()]
    if any(alvo in str(i) for i in ids):
        ctx = m.get("context_window")
        print("  %s: context_window=%s" % (m["id"], ctx))
        if isinstance(ctx, int) and ctx < 16000:
            print("  ⚠️  contexto PEQUENO. O prompt base do opencode (sistema + ferramentas)")
            print("      pode não caber, e o sintoma é ContextOverflowError na compactação —")
            print("      confirmado em 2026-07-25 com groq/llama-3.3-70b-versatile (6K).")
            print("      Não é incapacidade do modelo: é incompatibilidade com o harness.")
        break
else:
    print(f"  (modelo {alvo} não encontrado no registry)")
' 2>/dev/null
else
  echo "  (passe <model_id> para checar o contexto declarado)"
fi
echo
echo "Ver também: lessons/2026-07-24-dispatch-travado.md e incidents/"
