#!/bin/bash
# run-with-fallback.sh — executa o runner percorrendo a cadeia de fallback (RF-08)
# Uso: bin/run-with-fallback.sh <model_id> <spec_file> [--session ID] [--fork]
#
# Consome os exit codes do contrato (core/runner-contract.md):
#   exit 2 (rate limit) ou exit 4 (saldo/quota) → tenta o PRÓXIMO da cadeia
#   qualquer outro                              → devolve como está
#
# A cadeia vem do campo `fallback` do model-registry.json (RF-08.1). Modelo sem
# cadeia falha direto — nunca inventa substituto (regra 11.2).
#
# Só faz sentido porque o runner devolve 2/4 de verdade: antes do incidente incidents/2026-07-24-rate-limit-chega-como-timeout-nao-como-e.md, rate
# limit virava timeout mudo (124) e esta cadeia nunca era acionada.
#
# Env obrigatória: DISPATCH_RUNNER
# Exit: o do runner que respondeu; 2 se a cadeia inteira esgotou

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${DISPATCH_RUNNER:?Erro: env DISPATCH_RUNNER não definida. Rode: source adapters/<cli>/env.sh}"
REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"

MODEL="${1:?Uso: run-with-fallback.sh <model_id> <spec_file> [flags...]}"
SPEC="${2:?Uso: run-with-fallback.sh <model_id> <spec_file> [flags...]}"
shift 2

# Cada linha: "<id>\t<id_status ou vazio>" (incidente incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md: id_status vai junto,
# não só o id — quem consome a cadeia precisa saber se o alvo é fantasma).
CADEIA=$(MODEL="$MODEL" REG="$REGISTRY" python3 -c '
import json, os, sys
d = json.load(open(os.environ["REG"]))
mid = os.environ["MODEL"]
for m in d["models"]:
    if mid in (m["id"], *(m.get("cli_hints", {}) or {}).values()):
        idx = {mm["id"]: mm.get("id_status", "") for mm in d["models"]}
        print(m["id"] + "\t" + m.get("id_status", ""))
        for f in m.get("fallback", []):
            print(f + "\t" + idx.get(f, ""))
        sys.exit(0)
print(mid + "\t")   # não está no registry: o runner é quem recusa (exit 3)
')

# Lê a cadeia pelo fd 3 (não pelo stdin padrão do loop): o runner é chamado
# dentro do loop e não pode herdar a cadeia como stdin dele.
exec 3<<EOF_CADEIA
$CADEIA
EOF_CADEIA

ULTIMO=2
TODOS_PULADOS_POR_STATUS=1
while IFS="$(printf '\t')" read -r M STATUS <&3; do
  [ -n "$M" ] || continue
  case "$STATUS" in
    *FANTASMA*|*NAO-VERIFICADO*)
      echo "  ↳ ⚠️  pulando $M — id_status: $STATUS" >&2
      ULTIMO=2
      continue
      ;;
  esac
  TODOS_PULADOS_POR_STATUS=0
  echo "▶ tentando: $M" >&2
  "$DISPATCH_RUNNER" "$M" "$SPEC" "$@"
  RC=$?
  case "$RC" in
    # exit 2/4 são eventos REAIS de provider — alimentam o usage-hub (v3.5)
    # para que pre-dispatch-check e pick vetem o provider na janela seguinte,
    # em vez de redescobrir o rate limit no próximo dispatch.
    2)
      echo "  ↳ rate limit em $M — próximo da cadeia (RF-08)" >&2
      python3 "$REPO_ROOT/bin/usage-hub.py" observe --kind rate_limit \
        --model-ref "$M" --source run-with-fallback >/dev/null 2>&1 || true
      ULTIMO=2
      ;;
    4)
      echo "  ↳ saldo/quota esgotado em $M — próximo da cadeia (RF-08)" >&2
      python3 "$REPO_ROOT/bin/usage-hub.py" observe --kind balance \
        --model-ref "$M" --source run-with-fallback >/dev/null 2>&1 || true
      ULTIMO=4
      ;;
    3)
      # A cadeia de fallback é dado CLI-agnóstico: pode listar modelo que não tem
      # cli_hint para o CLI ativo. Isso é "indisponível aqui" (PRD 4.3), não erro
      # do chamador — pula, mas avisa alto para não mascarar flag inválida.
      echo "  ↳ ⚠️  $M indisponível neste CLI (exit 3) — pulando. Se não for falta de cli_hint, é erro de uso." >&2
      ULTIMO=3
      ;;
    *) exit "$RC" ;;
  esac
done
exec 3<&-

if [ "$TODOS_PULADOS_POR_STATUS" = "1" ]; then
  echo "✖ nenhum alvo confiável na cadeia de $MODEL — todos pulados por id_status FANTASMA/NAO-VERIFICADO (incidente incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md)" >&2
  exit 2
fi

echo "✖ cadeia de fallback esgotada para $MODEL (último motivo: exit $ULTIMO)" >&2
exit "$ULTIMO"
