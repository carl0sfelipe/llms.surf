#!/bin/bash
# verify-models.sh — mede modelo de verdade e carimba verified_at no registry
# Spec: core/model-registry-spec.md, suíte em core/verify-suite.json
#
# Uso:
#   bin/verify-models.sh <model_id> [--write] [--needle <tokens>] [--force]
#   bin/verify-models.sh --all [--write]
#
#   --force  grava mesmo se suite_accuracy der 0.0 (regra 25: zero absoluto é
#            suspeita de bug de harness, não medição — recusado por padrão)
#
# Mede:
#   - disponibilidade  (o modelo responde?)
#   - suite_accuracy   (tarefas de resposta curta, igualdade exata normalizada)
#   - latency_ms       (medido AQUI — o do registry é herdado de spec)
#   - context_tokens   (needle-in-haystack, opcional: valida alegação de contexto)
#
# NÃO sobrescreve `accuracy` nem `context_window` do registry: aqueles têm `source`
# (spec de origem). O que é medido aqui vai para `measured`, separado, com
# `verified_at` e `verified_by`. Números diferentes, campos diferentes.
#
# Env obrigatória: DISPATCH_RUNNER (source adapters/<cli>/env.sh)
# Exit: 0=ok, 1=modelo falhou, 3=erro de uso

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${DISPATCH_RUNNER:?Erro: env DISPATCH_RUNNER não definida. Rode: source adapters/<cli>/env.sh}"
REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"
SUITE="${VERIFY_SUITE:-$REPO_ROOT/core/verify-suite.json}"
RUNNER_NAME="${DISPATCH_RUNNER_NAME:-desconhecido}"
TASK_TIMEOUT="${VERIFY_TASK_TIMEOUT:-120}"   # regra 12: nada sem teto

# A suíte compara TEXTO final. Se o adapter estiver com --format json ligado
# (adapters/opencode/env.sh exporta 1), o runner devolve stream de eventos e
# TODA tarefa falha por formato, não por incapacidade do modelo — o que gravaria
# accuracy 0 falsa no registry. Forçado em 0 aqui, de propósito.
export DISPATCH_RUNNER_FORMAT_JSON=0

WRITE=0
NEEDLE=0
ALL=0
FORCE=0
MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --write)  WRITE=1; shift ;;
    --all)    ALL=1; shift ;;
    --needle) NEEDLE="${2:?--needle requer número de tokens}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    -*)       echo "flag desconhecida: $1" >&2; exit 3 ;;
    *)        MODEL="$1"; shift ;;
  esac
done

[ -f "$SUITE" ] || { echo "❌ suíte não encontrada: $SUITE" >&2; exit 3; }
[ -f "$REGISTRY" ] || { echo "❌ registry não encontrado: $REGISTRY" >&2; exit 3; }

# Extrai o CORPO da resposta, preservando múltiplas linhas.
# O opencode decora com ANSI e uma linha de banner ("> build · <modelo>"); só
# isso é removido. Nada de `tail -1`: truncar reprovava JSON válido de várias
# linhas e resposta de bulk output por formatação, não por capacidade.
# A decisão de passa/falha é do motor determinístico em bin/lib-check.py.
extrai_corpo() {
  perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g' \
    | grep -v '^[[:space:]]*> build · ' \
    | sed -E '/./,$!d'
}

# Descobre provider_observed e quantization a partir do cli_hint (incidente incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md).
# openrouter/*: consulta API pública de endpoints. opencode/* (Zen): sem API
# pública, grava unknown com motivo. Demais: unknown, sem catálogo acessível.
# Preenche globais PROVIDER_OBSERVED e QUANTIZATION.
detecta_provider() {
  local mid="$1"
  local hint
  hint=$(MID="$mid" RUNNER="$RUNNER_NAME" REG="$REGISTRY" python3 -c "
import json, os
d = json.load(open(os.environ['REG']))
for m in d['models']:
    if os.environ['MID'] in (m['id'], m.get('cli_hints', {}).get(os.environ['RUNNER'])):
        print(m.get('cli_hints', {}).get(os.environ['RUNNER'], ''))
        break
")
  case "$hint" in
    openrouter/*)
      local slug="${hint#openrouter/}"
      local resp_tmp
      resp_tmp=$(mktemp)
      bash "$REPO_ROOT/bin/with-timeout.sh" 20 curl -s "https://openrouter.ai/api/v1/models/${slug}/endpoints" > "$resp_tmp" 2>/dev/null
      local resultado
      resultado=$(RESP_TMP="$resp_tmp" python3 <<'PY'
import json, os
try:
    d = json.load(open(os.environ['RESP_TMP']))
    eps = d.get('data', {}).get('endpoints', [])
    if eps:
        prov = '; '.join(e.get('provider_name', '?') for e in eps)
        quant = '; '.join(f"{e.get('provider_name','?')}={e.get('quantization','unknown')}" for e in eps)
    else:
        prov = 'unknown — endpoints vazio na resposta openrouter'
        quant = prov
except Exception as e:
    prov = f'unknown — falha ao ler endpoints openrouter: {e}'
    quant = prov
print(prov)
print(quant)
PY
)
      rm -f "$resp_tmp"
      PROVIDER_OBSERVED=$(printf '%s\n' "$resultado" | sed -n '1p')
      QUANTIZATION=$(printf '%s\n' "$resultado" | sed -n '2p')
      ;;
    opencode/*)
      PROVIDER_OBSERVED="unknown — Zen nao publica"
      QUANTIZATION="unknown — Zen nao publica"
      ;;
    "")
      PROVIDER_OBSERVED="unknown — cli_hint ausente para runner $RUNNER_NAME"
      QUANTIZATION="unknown — cli_hint ausente para runner $RUNNER_NAME"
      ;;
    *)
      PROVIDER_OBSERVED="unknown — sem catálogo público acessível sem chave"
      QUANTIZATION="unknown — sem catálogo público acessível sem chave"
      ;;
  esac
}

verifica_modelo() {
  MID="$1"
  echo "═══ $MID ═══"

  TOTAL=$(python3 -c "import json;print(len(json.load(open('$SUITE'))['tasks']))")
  PASS=0
  SOMA_MS=0
  FALHOU_TUDO=1

  i=0
  while [ "$i" -lt "$TOTAL" ]; do
    PROMPT=$(python3 -c "import json;print(json.load(open('$SUITE'))['tasks'][$i]['prompt'])")
    TID=$(python3 -c "import json;print(json.load(open('$SUITE'))['tasks'][$i]['id'])")

    SPEC_TMP=$(mktemp)
    printf '%s\n' "$PROMPT" > "$SPEC_TMP"

    INICIO=$(python3 -c 'import time;print(int(time.time()*1000))')
    # stdout = resposta; stderr = avisos/diagnóstico do runner (incidente incidents/2026-07-24-rate-limit-chega-como-timeout-nao-como-e.md escreve
    # avisos legítimos lá). Misturar com 2>&1 fazia o aviso virar "a resposta"
    # e gravar accuracy 0 falsa no registry.
    ERR_TMP=$(mktemp)
    # SANDBOX: o runner roda a partir de um diretório VAZIO, nunca do repo.
    # Motivo comprovado em 2026-07-25: `opencode run` dá ferramentas de escrita ao
    # modelo, e modelos sob teste (a) criaram somar.md no repo a partir da tarefa
    # de bulk e (b) EDITARAM core/verify-suite.json aplicando a tarefa de
    # refinamento no próprio arquivo da suíte — o sujeito da medição alterou o
    # instrumento de medição, tornando a tarefa trivial e as notas inválidas.
    SANDBOX=$(mktemp -d)
    SAIDA=$(cd "$SANDBOX" && bash "$REPO_ROOT/bin/with-timeout.sh" "$TASK_TIMEOUT" "$DISPATCH_RUNNER" "$MID" "$SPEC_TMP" 2>"$ERR_TMP")
    RC=$?
    # o que o modelo escreveu no sandbox é descartado — e serve de sinal
    ESCREVEU=$(find "$SANDBOX" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$ESCREVEU" != "0" ] && echo "     ℹ️  modelo criou $ESCREVEU arquivo(s) no sandbox (descartados)" >&2
    rm -rf "$SANDBOX"
    MOTIVO=$(grep -oE 'RATE LIMIT|SALDO/QUOTA esgotado|TIMEOUT' "$ERR_TMP" | head -1)
    rm -f "$ERR_TMP"
    FIM=$(python3 -c 'import time;print(int(time.time()*1000))')
    rm -f "$SPEC_TMP"

    MS=$((FIM - INICIO))
    SOMA_MS=$((SOMA_MS + MS))

    # Resposta preservada INTEIRA (multi-linha) num arquivo, e a decisão é do
    # motor determinístico bin/lib-check.py (core/verify-suite-spec.md).
    # Antes: `tail -1` truncava e reprovava JSON válido de várias linhas por
    # formatação, não por capacidade — falso negativo apontado pela revisão
    # adversarial BMAD de 2026-07-25.
    RESP_TMP=$(mktemp)
    printf '%s' "$SAIDA" | extrai_corpo > "$RESP_TMP"

    if [ "$RC" -eq 0 ]; then
      FALHOU_TUDO=0
    fi

    if [ "$RC" -eq 0 ]; then
      VEREDITO=$(python3 "$REPO_ROOT/bin/lib-check.py" "$SUITE" "$i" "$RESP_TMP" 2>&1)
      RESULTADO=$(printf '%s\n' "$VEREDITO" | sed -n '1p')
      RAZAO=$(printf '%s\n' "$VEREDITO" | sed -n '2p')
    else
      RESULTADO="FAIL"
      RAZAO="runner exit=$RC ${MOTIVO:+[$MOTIVO]}"
    fi
    rm -f "$RESP_TMP"

    if [ "$RESULTADO" = "PASS" ]; then
      PASS=$((PASS + 1))
      printf "  ✅ %-34s %6dms\n" "$TID" "$MS"
    else
      printf "  ❌ %-34s %6dms  %.70s\n" "$TID" "$MS" "$RAZAO"
    fi
    i=$((i + 1))
  done

  MEDIA_MS=$((SOMA_MS / TOTAL))
  echo "  ── ${PASS}/${TOTAL} corretas, latência média ${MEDIA_MS}ms"

  detecta_provider "$MID"
  echo "  ── provider=${PROVIDER_OBSERVED} quant=${QUANTIZATION}"

  CTX_OK="null"
  if [ "$NEEDLE" != "0" ]; then
    echo "  ── needle-in-haystack (~${NEEDLE} tokens)..."
    NEEDLE_SPEC=$(mktemp)
    python3 - "$NEEDLE" > "$NEEDLE_SPEC" <<'PY'
import sys
n = int(sys.argv[1])
filler = "O framework dispatch orquestra modelos. " * max(1, n // 8)
print("Leia o texto e responda apenas com o código, sem mais nada.\n")
print(filler[: n * 4])
print("\nCODIGO-SECRETO: ZX42Q\n")
print(filler[: n * 4])
print("\nQual é o CODIGO-SECRETO? Responda apenas o código.")
PY
    NS=$(bash "$REPO_ROOT/bin/with-timeout.sh" 300 "$DISPATCH_RUNNER" "$MID" "$NEEDLE_SPEC" 2>&1)
    NRC=$?
    rm -f "$NEEDLE_SPEC"
    if [ "$NRC" -eq 0 ] && printf '%s' "$NS" | grep -q 'ZX42Q'; then
      echo "  ✅ recuperou a agulha em ~${NEEDLE} tokens"
      CTX_OK="$NEEDLE"
    else
      echo "  ❌ NÃO recuperou a agulha em ~${NEEDLE} tokens (rc=$NRC)"
      CTX_OK="0"
    fi
  fi

  if [ "$FALHOU_TUDO" = "1" ]; then
    echo "  ⚠️  modelo não respondeu a nenhuma tarefa — nada será carimbado."
    return 1
  fi

  if [ "$WRITE" = "1" ] && [ "$FORCE" != "1" ]; then
    ID_STATUS=$(MID="$MID" REG="$REGISTRY" python3 -c "
import json, os
d = json.load(open(os.environ['REG']))
for m in d['models']:
    if os.environ['MID'] in (m['id'], *(m.get('cli_hints', {}) or {}).values()):
        print(m.get('id_status', ''))
        break
")
    case "$ID_STATUS" in
      *FANTASMA*|*NAO-VERIFICADO*)
        echo "  ❌ id_status=\"$ID_STATUS\" — gravação recusada (incidente incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md)."
        echo "     Medir id não confirmado é medir fantasma: verified_at não pode"
        echo "     carimbar um id cujo próprio catálogo do provider nega existir."
        echo "     Use --force para gravar mesmo assim."
        return 3
        ;;
    esac
  fi

  if [ "$WRITE" = "1" ] && [ "$PASS" -eq 0 ] && [ "$FORCE" != "1" ]; then
    echo "  ❌ suite_accuracy=0.0 — gravação recusada (regra 25)."
    echo "     Zero absoluto é suspeita de bug de harness, não medição: o modelo"
    echo "     pode estar respondendo certo e o parser/extrator errado (banner"
    echo "     colado na resposta, stderr fundido com stdout, etc)."
    echo "     Proceda assim: inspecione a resposta crua da tarefa (rode o"
    echo "     DISPATCH_RUNNER manualmente e olhe o output cru, sem extrai_corpo)."
    echo "     Se o zero for real, repita com --force para gravar mesmo assim."
    return 3
  fi

  if [ "$WRITE" = "1" ]; then
    MID="$MID" PASS="$PASS" TOTAL="$TOTAL" MEDIA="$MEDIA_MS" CTX="$CTX_OK" \
    PROV="$PROVIDER_OBSERVED" QUANT="$QUANTIZATION" \
    RUNNER="$RUNNER_NAME" REG="$REGISTRY" python3 <<'PY'
import json, os, datetime
reg = os.environ["REG"]
d = json.load(open(reg))
mid = os.environ["MID"]
alvo = None
for m in d["models"]:
    if mid in (m["id"], m.get("cli_hints", {}).get(os.environ["RUNNER"])):
        alvo = m
        break
if alvo is None:
    raise SystemExit(f"modelo {mid} ausente do registry")
ctx = os.environ["CTX"]
alvo["verified_at"] = datetime.date.today().isoformat()
alvo["verified_by"] = os.environ["RUNNER"]
med = alvo.setdefault("measured", {})
med["suite_accuracy"] = round(int(os.environ["PASS"]) / int(os.environ["TOTAL"]), 3)
med["suite_n"] = int(os.environ["TOTAL"])
med["latency_ms"] = int(os.environ["MEDIA"])
if ctx not in ("null",):
    med["context_verified_tokens"] = int(ctx)
med["provider_observed"] = os.environ["PROV"]
med["quantization"] = os.environ["QUANT"]
json.dump(d, open(reg, "w"), indent=2, ensure_ascii=False)
print(f"  💾 registry atualizado: verified_at={alvo['verified_at']} measured={med}")
PY
  else
    echo "  (dry-run — use --write para carimbar verified_at no registry)"
  fi
  return 0
}

if [ "$ALL" = "1" ]; then
  IDS=$(RUNNER="$RUNNER_NAME" REG="$REGISTRY" python3 -c "
import json, os
d = json.load(open(os.environ['REG']))
for m in d['models']:
    if m.get('cli_hints', {}).get(os.environ['RUNNER']):
        print(m['id'])
")
  [ -n "$IDS" ] || { echo "nenhum modelo com cli_hint para '$RUNNER_NAME'"; exit 0; }

  OK=0
  TOTAL_MODELOS=0
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    TOTAL_MODELOS=$((TOTAL_MODELOS + 1))
    if verifica_modelo "$m"; then
      OK=$((OK + 1))
    fi
  done <<< "$IDS"

  echo "═══ resumo: ${OK} de ${TOTAL_MODELOS} modelos medidos com sucesso ═══"
  [ "$OK" -gt 0 ] && exit 0
  exit 1
else
  [ -n "$MODEL" ] || { echo "Uso: verify-models.sh <model_id> [--write] [--needle <tokens>] | --all" >&2; exit 3; }
  verifica_modelo "$MODEL"
fi
