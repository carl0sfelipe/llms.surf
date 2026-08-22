#!/bin/bash
# runner.sh — implementação llama.cpp do contrato core/runner-contract.md
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
#
# Traduz para: POST $LLAMACPP_URL/v1/chat/completions (API OpenAI-compatível do
# llama-server). Sintaxe verificada em adapters/llamacpp/DISCOVERY.md.
#
# Exit codes (RNF-04): 0=ok, 1=erro, 2=rate-limit, 3=erro de uso, 4=quota
# Local não tem rate limit nem quota — 2 e 4 nunca ocorrem aqui, e é justamente
# a propriedade que torna este adapter útil quando os providers remotos caem.

set -uo pipefail

MODEL_ID="${1:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
SPEC_FILE="${2:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
shift 2

while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      # llama-server é stateless: não há sessão para reusar.
      echo "runner.sh (llamacpp): --session não suportado (capabilities.env SESSION_REUSE=0)" >&2
      exit 3
      ;;
    --fork)
      echo "runner.sh (llamacpp): --fork não suportado (capabilities.env FORK=0)" >&2
      exit 3
      ;;
    *)
      echo "runner.sh (llamacpp): flag desconhecida: $1" >&2
      exit 3
      ;;
  esac
done

[ -f "$SPEC_FILE" ] || { echo "runner.sh (llamacpp): spec_file não encontrado: $SPEC_FILE" >&2; exit 1; }

URL="${LLAMACPP_URL:-http://127.0.0.1:8081}"
MAX_TOKENS="${LLAMACPP_MAX_TOKENS:-2048}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Servidor no ar? Sem isso o erro vira timeout mudo (incidente incidents/2026-07-25-travamento-tem-dois-modos-e-o-erro-fica-.md).
if ! bash "$REPO_ROOT/bin/with-timeout.sh" 8 curl -s -o /dev/null "$URL/health" 2>/dev/null; then
  cat >&2 <<EOF
runner.sh (llamacpp): servidor não responde em $URL

Suba com (ajuste o modelo):
  ~/llama.cpp/build/bin/llama-server -m ~/models/<modelo>.gguf \\
    -c 16384 -ngl 99 --port 8081 --host 127.0.0.1 --jinja

-c 16384 no mínimo: contexto curto não comporta o prompt base e o sintoma
imita incapacidade do modelo (incidente incidents/2026-07-25-travamento-tem-dois-modos-e-o-erro-fica-.md).
EOF
  exit 3
fi

PAYLOAD=$(MODEL="$MODEL_ID" SPEC="$SPEC_FILE" MAXTOK="$MAX_TOKENS" python3 -c '
import json, os
prompt = open(os.environ["SPEC"], encoding="utf-8", errors="replace").read()
print(json.dumps({
    "model": os.environ["MODEL"],
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": int(os.environ["MAXTOK"]),
    "temperature": 0,
}))
')

RESP=$(mktemp)
trap 'rm -f "$RESP"' EXIT

CODE=$(bash "$REPO_ROOT/bin/with-timeout.sh" "${LLAMACPP_TIMEOUT:-300}" \
  curl -s -o "$RESP" -w '%{http_code}' --max-time "${LLAMACPP_TIMEOUT:-300}" \
  "$URL/v1/chat/completions" -H 'Content-Type: application/json' -d "$PAYLOAD" 2>/dev/null)

if [ "$CODE" != "200" ]; then
  echo "runner.sh (llamacpp): HTTP $CODE" >&2
  head -c 200 "$RESP" >&2; echo >&2
  exit 1
fi

# Extrai a resposta. Modelo de reasoning (gemma-4, nemotron-*-reasoning) devolve
# `content` VAZIO e o texto em `reasoning_content` — ler só `content` faria
# concluir "não respondeu" quando respondeu. Observado em 2026-07-25.
python3 - "$RESP" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"runner.sh (llamacpp): resposta ilegível: {e}", file=sys.stderr)
    sys.exit(1)
msg = (d.get("choices") or [{}])[0].get("message", {})
texto = (msg.get("content") or "").strip()
if not texto:
    texto = (msg.get("reasoning_content") or "").strip()
    if texto:
        print("runner.sh (llamacpp): aviso — resposta veio em reasoning_content", file=sys.stderr)
if not texto:
    print("runner.sh (llamacpp): resposta vazia (content e reasoning_content)", file=sys.stderr)
    sys.exit(1)
print(texto)
PY
