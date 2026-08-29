#!/bin/bash
# check-saude.sh — roda a bateria inteira de verificação do framework.
#
# Existe porque a verificação estava espalhada: cinco scripts, cada um rodado
# de memória, e nenhum inventário de qual deles cobre o quê. Quem chega novo
# não sabe se o repositório está são, e "rodei o que lembrei" não é resposta.
#
# NÃO mede modelo (isso é `bin/verify-models.sh`, custa rede e minutos). Aqui só
# entra checagem local e instantânea — pode rodar antes de qualquer commit.
#
# Uso: bin/check-saude.sh
# Exit: 0=tudo são, 1=alguma checagem falhou

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FALHAS=0
LARGURA=34

checar() {  # checar <rótulo> <comando...>
  local rotulo="$1"; shift
  local saida rc
  saida=$("$@" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    printf "  ✅ %-${LARGURA}s ok\n" "$rotulo"
  else
    printf "  ❌ %-${LARGURA}s exit %s\n" "$rotulo" "$rc"
    printf '%s\n' "$saida" | sed 's/^/       /' | head -12
    FALHAS=$((FALHAS + 1))
  fi
}

echo "── Fluxos ────────────────────────────────────────────"
checar "step sem comando cru de CLI"      bash bin/lint-steps.sh
checar "step cita script que existe"      bash tests/test-drift.sh
checar "retomada por artefato"            bash tests/test-retomada.sh

echo ""
echo "── Regras ────────────────────────────────────────────"
checar "invariantes da poda"              bash tests/test-regras.sh
checar "sem dívida de incidente"          bash bin/incident.sh audit
# superfície exportável sem telefone/e-mail de terceiro/caminho de máquina —
# incidents/2026-08-13-oracfit-soldado-no-orbe-corte-sem-catego.md
checar "superfície pública sem dado pessoal" bash bin/check-publico.sh --oficina
checar "site público: números honestos"   bash tests/test-site-honesty.sh

echo ""
echo "── Sintaxe ───────────────────────────────────────────"
checar "regex sem acento em conjunto"     bash tests/test-regex-multibyte.sh
ERRO_SINTAXE=""
for f in bin/*.sh adapters/*/runner.sh adapters/*/env.sh tests/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null || ERRO_SINTAXE="$ERRO_SINTAXE $f"
done
if [ -z "$ERRO_SINTAXE" ]; then
  printf "  ✅ %-${LARGURA}s ok\n" "todo script parseia"
else
  printf "  ❌ %-${LARGURA}s %s\n" "script com erro de sintaxe" "$ERRO_SINTAXE"
  FALHAS=$((FALHAS + 1))
fi

# JSON de configuração: arquivo quebrado só aparece na hora do dispatch.
ERRO_JSON=""
for j in model-registry.json core/verify-suite.json; do
  [ -f "$j" ] || continue
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$j" 2>/dev/null || ERRO_JSON="$ERRO_JSON $j"
done
if [ -z "$ERRO_JSON" ]; then
  printf "  ✅ %-${LARGURA}s ok\n" "JSON de config válido"
else
  printf "  ❌ %-${LARGURA}s %s\n" "JSON inválido" "$ERRO_JSON"
  FALHAS=$((FALHAS + 1))
fi

echo ""
echo "── Fantasma (repos consumidores) ─────────────────────"
# check-fantasma.sh recusa declare/as any/@ts-ignore NOVO nos repos que este
# dispatch orquestra. Guardado com [ -d ]: rodar este framework noutra máquina
# sem os repos-irmãos clonados não pode quebrar a saúde do próprio dispatch —
# a checagem é sobre o QUE o dispatch toca, não sobre o dispatch em si.
KIT_SRC="$HOME/medusa-br-framework/packages/kit-storefront/src"
KIT_BASELINE="$REPO_ROOT/fantasma-baselines/kit-storefront.txt"
if [ -d "$KIT_SRC" ]; then
  checar "kit-storefront sem fantasma novo" bash bin/check-fantasma.sh "$KIT_SRC" "$KIT_BASELINE"
else
  printf "  ⓘ %-${LARGURA}s %s\n" "kit-storefront" "repo não clonado nesta máquina — pulado"
fi

echo ""
echo "── Docs ──────────────────────────────────────────────"
# Número de README copiado à mão apodrece em silêncio (medido em 2026-08-22:
# README 91/23 vs árvore 104/26; Detailed/pt-BR uma geração atrás). O gate
# deriva os números da árvore e falha em drift — copy se corrige, não o gate.
checar "números de README derivam da árvore" bash bin/check-docs.sh

echo ""
echo "── Registry ──────────────────────────────────────────"
# id_status que afirma estado de PROVIDER (401, auth, saldo, quota) apodrece:
# a causa some quando a credencial é trocada ou a cota reseta, e o registry
# continua afirmando que o provider está morto. Aconteceu com a NVIDIA — 7 de 11
# ids marcados como mortos por 401 respondiam OK dois dias depois.
# id_status sobre o MODELO (410 Gone, id inexistente) não vence.
# Incidente: incidents/2026-07-27-registry-marcou-provider-como-morto-e-ni.md
VENCIDOS=$(python3 - <<'PY' 2>/dev/null
import json, re, datetime, sys
LIMITE = 14
try:
    d = json.load(open("model-registry.json"))
except Exception:
    sys.exit(0)
hoje = datetime.date.today()
PROVIDER = re.compile(r"401|unauthorized|auth quebrada|insufficient balance|sem saldo|quota", re.I)
for m in d.get("models", []):
    st = str(m.get("id_status", ""))
    if not st or not PROVIDER.search(st):
        continue
    datas = re.findall(r"(20\d\d)-(\d\d)-(\d\d)", st)
    if not datas:
        continue
    mais_nova = max(datetime.date(int(a), int(b), int(c)) for a, b, c in datas)
    idade = (hoje - mais_nova).days
    if idade > LIMITE:
        print(f"{m['id']} ({idade}d)")
PY
)
if [ -z "$VENCIDOS" ]; then
  printf "  ✅ %-${LARGURA}s ok\n" "id_status de provider atual"
else
  printf "  ⚠️  %-${LARGURA}s revalide\n" "id_status de provider vencido"
  printf '%s\n' "$VENCIDOS" | sed 's/^/       /' | head -12
  echo "       Afirmação sobre auth/quota apodrece. Remeça antes de confiar."
fi

# GGUF local: `ls -la` num symlink mede o LINK, e isso já transformou um modelo
# íntegro de 5,6 GB em "truncado, 104 bytes" em três documentos.
# Incidente: incidents/2026-07-27-ls-la-em-symlink-reportou-tamanho-do-lin.md
GGUF_DIR="${GGUF_DIR:-$HOME/Models}"
if [ -d "$GGUF_DIR" ] && ls "$GGUF_DIR"/*.gguf >/dev/null 2>&1; then
  if bash bin/check-gguf.sh "$GGUF_DIR"/*.gguf >/dev/null 2>&1; then
    printf "  ✅ %-${LARGURA}s ok\n" "GGUF local íntegro"
  else
    printf "  ❌ %-${LARGURA}s\n" "GGUF local inválido"
    bash bin/check-gguf.sh "$GGUF_DIR"/*.gguf 2>&1 | grep '^❌' | sed 's/^/       /' | head -6
    FALHAS=$((FALHAS + 1))
  fi
fi

echo ""
echo "── Legal / telemetria (FR-11/12) ──────────────────────"
for f in LICENSE NOTICE docs/TELEMETRY.md VERSION; do
  if [ -f "$f" ]; then
    printf "  ✅ %-${LARGURA}s ok\n" "$f"
  else
    printf "  ❌ %-${LARGURA}s ausente\n" "$f"
    FALHAS=$((FALHAS + 1))
  fi
done

echo ""
echo "── Adapters ──────────────────────────────────────────"
SEM_TOOLS=""
for c in adapters/*/capabilities.env; do
  grep -q "^TOOLS=" "$c" || SEM_TOOLS="$SEM_TOOLS $(dirname "$c" | xargs basename)"
done
if [ -z "$SEM_TOOLS" ]; then
  printf "  ✅ %-${LARGURA}s ok\n" "todo adapter declara TOOLS"
else
  printf "  ❌ %-${LARGURA}s %s\n" "adapter sem TOOLS" "$SEM_TOOLS"
  FALHAS=$((FALHAS + 1))
fi

echo ""
echo "══════════════════════════════════════════════════════"
if [ "$FALHAS" -eq 0 ]; then
  echo "✅ Framework são — $(ls fluxos/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ') fluxos, $(grep -cE '^\*\*[0-9]+\.' SKILL.md) regras, $(ls incidents/*.md 2>/dev/null | wc -l | tr -d ' ') incidentes."
  echo ""
  echo "Não coberto aqui (exige rede e minutos):"
  echo "  bin/verify-models.sh --all    mede os modelos"
  echo "  bin/audit-registry-ids.sh     id fantasma no registry"
  exit 0
fi

echo "❌ $FALHAS checagem(ns) falharam."
exit 1
