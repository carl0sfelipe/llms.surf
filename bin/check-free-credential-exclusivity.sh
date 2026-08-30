#!/bin/bash
# check-free-credential-exclusivity.sh — gate estrutural do E5-M5/D4.
#
# Incidente-âncora (E5): credencial herdada no ambiente virou o default pago
# (118 Bedrock + 36 Copilot) sem ninguém pedir. A classe só morre se a cadeia
# de dispatch NÃO lê credencial de env — a lib-free-credentials.sh é a leitora
# única (por ARQUIVO) e este gate é o grep que prova a exclusividade.
#
# Três anéis:
#   1. Cadeia de dispatch (bin/dispatch*, run-with-fallback, libs oracfit,
#      usage-hub, preflight...): ZERO match de padrão de credencial, com a
#      ÚNICA exceção da própria lib-free-credentials.sh.
#   2. Runners/preflights de adapter: só podem citar o prefixo do PRÓPRIO CLI
#      (cursor → CURSOR_*, zcode → ZCODE_*); chave de PROVIDER (AWS_*,
#      OPENROUTER_*, GROQ_*, NVIDIA_*, ...) nem em comentário — o que é
#      comentário hoje vira código amanhã.
#   3. Exceções FORA da cadeia, documentadas uma a uma: ferramentas de API
#      direta que nasceram antes do E5 e não escolhem provider de dispatch
#      (cf-probe, vision-gauntlet-loop). Adicionar exceção = editar a lista
#      aqui, com justificativa — nunca silenciosamente.
#
# Uso: bin/check-free-credential-exclusivity.sh
# Exit: 0 = exclusividade intacta, 1 = vazamento, 3 = uso

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PADRAO='_API_KEY|API_TOKEN|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|_AUTH_TOKEN'

# Anel 1 — cadeia de dispatch: nenhum leitor de credencial além da lib.
VAZIO=""
for f in bin/dispatch*.sh bin/run-with-fallback.sh bin/lib-oracfit-*.sh \
         bin/usage-hub.py bin/pre-dispatch-check.sh bin/tuned-measure.sh \
         bin/lineup-build.sh bin/classify-dispatch.sh; do
  [ -f "$f" ] || continue
  case "$f" in */lib-free-credentials.sh) continue ;; esac
  if grep -qE "$PADRAO" "$f" 2>/dev/null; then
    VAZIO="$VAZIO $f"
  fi
done
if [ -n "$VAZIO" ]; then
  echo "❌ leitura de credencial fora da lib-free-credentials.sh na cadeia de dispatch:$VAZIO" >&2
  echo "   A credencial de provider se resolve por ARQUIVO via bin/lib-free-credentials.sh" >&2
  echo "   (E5-M5/D4 — env herdada foi o vetor dos 118 Bedrock + 36 Copilot)." >&2
  exit 1
fi
echo "  anel 1 ok: cadeia de dispatch sem leitor de credencial (exceto a lib)"

# Anel 2 — adapters: apenas o prefixo do próprio CLI. Aqui o padrão captura
# o NOME COMPLETO da variável (grep -o devolve o trecho da alternância, não
# a variável inteira — comparar trecho contra allowlist sempre falharia).
declare -A PROPRIO=(
  [cursor]='CURSOR_API_KEY|CURSOR_AUTH_TOKEN'
  [zcode]='ZCODE_API_KEY'
)
NOME_VAR='[A-Z_][A-Z_0-9]*_API_KEY|[A-Z_][A-Z_0-9]*_API_TOKEN|[A-Z_][A-Z_0-9]*_AUTH_TOKEN|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN'
DECLARADO=""
for f in adapters/*/runner.sh adapters/*/preflight.sh; do
  [ -f "$f" ] || continue
  adapter="$(echo "$f" | cut -d/ -f2)"
  proprio="${PROPRIO[$adapter]:-}"
  # Remove linhas de comentário antes do grep (comentário citando padrão
  # normaliza o leak — o gate mede CÓDIGO; a menção em comentário do runner
  # opencode ao caminho do vault fica no anel 3 como exceção documentada).
  while IFS= read -r linha; do
    caso="$(printf '%s' "$linha" | grep -oE "$NOME_VAR" | head -1)"
    [ -n "$caso" ] || continue
    if [ -n "$proprio" ] && printf '%s' "$caso" | grep -qE "^(${proprio})$"; then
      continue
    fi
    DECLARADO="$DECLARADO
  $f: $caso"
  done < <(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null)
done
# opencode runner: a menção ao literal $NVIDIA_API_KEY vive em COMENTÁRIO
# (documento do vault) — anel 2 só mede código, então nada a fazer aqui.
if [ -n "$DECLARADO" ]; then
  echo "❌ adapter cita chave de PROVIDER fora do prefixo do próprio CLI:$DECLARADO" >&2
  exit 1
fi
echo "  anel 2 ok: adapters limitados ao próprio prefixo de CLI"

# Anel 3 — exceções fora da cadeia, contadas para não apodrecerem em silêncio.
EXCECOES=0
for f in bin/cf-probe.sh bin/vision-gauntlet-loop.py; do
  [ -f "$f" ] || continue
  if grep -qE "$PADRAO" "$f" 2>/dev/null; then
    EXCECOES=$((EXCECOES + 1))
  fi
done
echo "  anel 3 ok: $EXCECOES exceção(ões) documentada(s) fora da cadeia (API direta, não escolhe provider de dispatch)"

exit 0
