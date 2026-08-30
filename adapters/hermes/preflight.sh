#!/bin/bash
# preflight.sh — checagens de config do hermes (contrato: bin/check-cli-config.sh)
#
# Exit: 0=ok, 1=config quebrada (com instrução de conserto no stderr)

set -uo pipefail

CONFIG="${HERMES_CONFIG:-$HOME/.hermes/config.yaml}"
CTX_MINIMO=64000   # mínimo que o hermes exige do modelo de compressão auxiliar

[ -f "$CONFIG" ] || { echo "❌ hermes: config não encontrada em $CONFIG" >&2; exit 1; }

falhou=0

# ── Check 1: default aponta para servidor local fora do ar ───────────────────
# Um base_url local morto não falha na hora: o hermes cai para fallback_providers
# e o erro que chega é sobre OUTRO modelo, o que manda o diagnóstico para o lado
# errado. Este check nomeia a causa real.
BASE_URL=$(python3 - "$CONFIG" <<'PY' 2>/dev/null
import sys, re
texto = open(sys.argv[1]).read()
bloco = re.search(r'^model:\n((?:[ \t].*\n)*)', texto, re.M)
if bloco:
    achado = re.search(r'^\s+base_url:\s*(\S+)', bloco.group(1), re.M)
    if achado:
        print(achado.group(1))
PY
)

if [ -n "$BASE_URL" ]; then
  case "$BASE_URL" in
    *localhost*|*127.0.0.1*)
      if ! bash "$(dirname "$0")/../../bin/with-timeout.sh" 5 curl -sf "${BASE_URL%/}/models" >/dev/null 2>&1; then
        echo "❌ hermes: model.base_url é local ($BASE_URL) e o servidor não responde." >&2
        echo "   O hermes vai cair para fallback_providers e falhar com erro sobre outro modelo." >&2
        echo "   Conserto: use API free como default em $CONFIG —" >&2
        echo "     model:" >&2
        echo "       default: nemotron-3-ultra-free (rota free viva — model-registry.json)" >&2
        echo "       provider: opencode-zen" >&2
        falhou=1
      fi
      ;;
  esac
fi

# ── Check 2: modelo de compressão auxiliar pinado ────────────────────────────
# Sem auxiliary.compression.model, o hermes escolhe o primeiro fallback. Se ele
# tiver menos de CTX_MINIMO de contexto, a sessão aborta antes de qualquer
# trabalho útil.
if ! python3 - "$CONFIG" "$CTX_MINIMO" <<'PY'
import sys, re
texto, minimo = open(sys.argv[1]).read(), int(sys.argv[2])
bloco = re.search(r'^auxiliary:\n((?:[ \t].*\n)*)', texto, re.M)
corpo = bloco.group(1) if bloco else ''
if not re.search(r'^\s+compression:', corpo, re.M):
    sys.exit(1)
achado = re.search(r'^\s+context_length:\s*(\d+)', corpo, re.M)
sys.exit(0 if (achado and int(achado.group(1)) >= minimo) else 1)
PY
then
  echo "❌ hermes: auxiliary.compression não está pinado com context_length >= $CTX_MINIMO." >&2
  echo "   Sem isso o hermes elege o primeiro fallback como modelo de compressão e aborta com" >&2
  echo "   'context window ... below the minimum $CTX_MINIMO required'." >&2
  echo "   Conserto em $CONFIG, dentro de auxiliary:" >&2
  echo "     compression:" >&2
  echo "       provider: opencode-zen" >&2
  echo "       model: nemotron-3-ultra-free   # free vivo, ctx 1M — registry é a verdade" >&2
  echo "       context_length: 128000" >&2
  falhou=1
fi

exit "$falhou"
