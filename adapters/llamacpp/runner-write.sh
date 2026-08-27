#!/bin/bash
# runner-write.sh — variante write-out do adapter llamacpp (adapters/llamacpp/runner.sh).
#
# Propósito: o llama-server é stateless e devolve TEXTO puro; o contrato do
# dispatch lê o DISCO (oráculo), não o stdout. Este wrapper fecha esse vazio para
# tarefas cujo entregável é um arquivo inteiro e novo (tradução, copy, docs):
# a spec declara um único alvo, o modelo devolve só o conteúdo, o wrapper grava.
#
# Convenção na SPEC (uma linha exata, case-sensitive):
#   ## ARQUIVO-ALVO: <caminho-relativo>
# O caminho é resolvido contra $ORACFIT_WORKDIR (cwd se ausente).
#
# Sanitização mínima antes de gravar:
#   - cerca de código markdown aberta/fechada em volta do corpo inteiro é removida
#     (modelo pequeno adora embrulhar tudo em ```markdown```);
#   - proibido sobrescrever FORA do workdir (anti-path-traversal);
#   - qualquer coisa < 200 bytes = provável recusa/vazio → exit 1 sem gravar,
#     para o gauntlet injetar feedback na attempt seguinte.
#
# Uso: runner-write.sh <model_id> <spec_file>   (mesma interface do runner.sh)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SPEC_FILE="${2:-}"

[ -f "$SPEC_FILE" ] || { echo "runner-write.sh: spec_file não encontrado" >&2; exit 3; }

TARGET="$(grep -m1 '^## ARQUIVO-ALVO:' "$SPEC_FILE" | sed 's/^## ARQUIVO-ALVO:[[:space:]]*//')"
if [ -z "$TARGET" ]; then
  echo "runner-write.sh: spec sem '## ARQUIVO-ALVO:' — use adapters/llamacpp/runner.sh" >&2
  exit 3
fi

WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
WORKDIR="$(cd "$WORKDIR" && pwd)" || { echo "runner-write.sh: workdir inválido: $WORKDIR" >&2; exit 3; }
DEST="$WORKDIR/$TARGET"

case "$(cd "$(dirname "$DEST")" 2>/dev/null && pwd)" in
  "$WORKDIR"|"$WORKDIR"/*) ;;
  *) echo "runner-write.sh: alvo escapa do workdir — recusado ($TARGET)" >&2; exit 3 ;;
esac

TMP="$(mktemp "${TMPDIR:-/tmp}/rw-XXXXXX")"
trap 'rm -f "$TMP"' EXIT

if bash "$HERE/runner.sh" "$@" >"$TMP"; then RC=0; else RC=$?; fi

python3 - "$TMP" "$DEST" <<'PY'
import re, sys, os

src, dest = sys.argv[1], sys.argv[2]
texto = open(src, encoding="utf-8", errors="replace").read().strip()
if len(texto) < 200:
    print(f"runner-write.sh: saída suspeita ({len(texto)} bytes) — nada gravado", file=sys.stderr)
    sys.exit(1)
# uma única cerca envolvendo TODO o corpo: abre ```\n ... \n``` e fecha
m = re.fullmatch(r"```[A-Za-z0-9+-]*\s*\n(.*)\n?```\s*", texto, flags=re.S)
if m:
    texto = m.group(1).rstrip() + "\n"
os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
with open(dest, "w", encoding="utf-8") as f:
    f.write(texto)
print(f"runner-write.sh: gravado {dest} ({len(texto)} bytes)", file=sys.stderr)
PY
WRC=$?

# rc do runner propaga; erro da aplicação vira 1 para o gauntlet retrabalhar
[ "$RC" -eq 0 ] && [ "$WRC" -ne 0 ] && exit 1
exit "$RC"
