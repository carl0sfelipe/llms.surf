#!/usr/bin/env bash
# ring-preflight.sh — preflight mecânico de ambiente antes de abrir anel (v4).
#
# Consolida a classe "ambiente/capacidade" dos incidentes:
#   - ENOSPC no meio do anel sem preflight (pythia-enospc)
#   - colima/docker morto com preflight PULADO ou com container errado (autarca)
#   - identidade git default nos commits (pythia/autarca, classe preflight)
#   - árvore suja de OUTRO agente varrida por commit (ouroboros/talos/autarca)
#
# Uso:
#   ring-preflight.sh <target_dir> [--min-disk-gb N] [--require-clean]
#                     [--custom "<cmd>"] [--strict-identity]
#
# Exit: 0=ok, 1=gate falhou (motivo no stderr), 3=uso
set -uo pipefail

TARGET="${1:?uso: ring-preflight.sh <target_dir> [--min-disk-gb N] [--require-clean] [--custom cmd] [--strict-identity]}"
shift

MIN_DISK_GB=10
REQUIRE_CLEAN=0
CUSTOM_CMD=""
STRICT_IDENTITY=0
IGNORE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --min-disk-gb) MIN_DISK_GB="${2:?--min-disk-gb requer valor}"; shift 2 ;;
    --require-clean) REQUIRE_CLEAN=1; shift ;;
    --custom) CUSTOM_CMD="${2:?--custom requer comando}"; shift 2 ;;
    --strict-identity) STRICT_IDENTITY=1; shift ;;
    --ignore) IGNORE_DIR="${2:?--ignore requer dir}"; shift 2 ;;
    *) echo "ERROR: flag desconhecida: $1" >&2; exit 3 ;;
  esac
done

fail() { echo "PREFLIGHT FALHOU: $1" >&2; exit 1; }

[ -d "$TARGET" ] || fail "target não existe: $TARGET"
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || fail "target não é repo git: $TARGET"

# (1) disco — df -k é portável (macOS/linux); GB = blocos de 1K / 1048576
avail_kb=$(df -k "$TARGET" | awk 'NR==2 {print $4}')
[ -n "$avail_kb" ] || fail "não consegui medir disco livre em $TARGET"
avail_gb=$((avail_kb / 1048576))
if [ "$avail_gb" -lt "$MIN_DISK_GB" ]; then
  fail "disco livre ${avail_gb}GB < mínimo ${MIN_DISK_GB}GB (ENOSPC no meio do anel — pythia-enospc)"
fi
echo "preflight: disco ${avail_gb}GB livre (mínimo ${MIN_DISK_GB}GB) — ok"

# (2) identidade git — default de host (`user@Mac-mini-de-mac.local`) apareceu
# em 3 sessões (classe preflight). Sem identidade explícita: warn; --strict: fail.
# EXCEÇÃO (débito 8, run ananke-20260813-0421): a identidade do RUN
# (oracfit-ring <ring@oracfit.local>) é setada DE PROPÓSITO pelo init quando
# a efetiva está vazia — o email termina em .local e caía no regex de default
# de host, e o WARN a cada open avisava sobre a escolha do próprio framework
# (ruído que treina executor a ignorar warning). Identidade do run é VÁLIDA;
# vazia de verdade continua avisando.
ident_email=$(git -C "$TARGET" config user.email 2>/dev/null || true)
ident_name=$(git -C "$TARGET" config user.name 2>/dev/null || true)
if [ "$ident_email" = "ring@oracfit.local" ] || [ "$ident_name" = "oracfit-ring" ]; then
  echo "preflight: identidade do run '${ident_name:-oracfit-ring} <${ident_email:-ring@oracfit.local}>' — ok"
elif [ -z "$ident_email" ] || echo "$ident_email" | grep -qE '@.*\.local$'; then
  if [ "$STRICT_IDENTITY" = "1" ]; then
    fail "identidade git ausente ou default de host: '${ident_email:-<vazia>}' (git config user.email)"
  fi
  echo "preflight WARN: identidade git ausente/default: '${ident_email:-<vazia>}' — commits sairão com autoria de host" >&2
else
  echo "preflight: identidade git '$ident_email' — ok"
fi

# (3) colisão de árvore — working tree sujo no OPEN significa trabalho de outro
# agente (ou anel anterior mal fechado): abrir por cima varre autoria alheia.
# --ignore exclui o diretório do próprio ring (ledger/score sujam por
# construção entre anéis e são commitados no close seguinte).
if [ "$REQUIRE_CLEAN" = "1" ]; then
  if [ -n "$IGNORE_DIR" ]; then
    dirty=$(git -C "$TARGET" status --porcelain -- . ":(exclude)$IGNORE_DIR" 2>/dev/null \
      || git -C "$TARGET" status --porcelain | grep -v " $IGNORE_DIR/" || true)
  else
    dirty=$(git -C "$TARGET" status --porcelain)
  fi
  if [ -n "$dirty" ]; then
    echo "PREFLIGHT FALHOU: árvore suja no open (colisão com outro agente ou anel mal fechado):" >&2
    echo "$dirty" | head -20 >&2
    # diagnóstico (2026-08-13, ai-usage-hub): __pycache__/*.pyc RASTREADOS
    # sujavam a árvore a cada pytest e o executor perdeu 2 commits de higiene
    # caçando "quem sujou". Quando TODOS os paths sujos são artefato
    # regenerável, a mensagem nomeia a causa e o remédio. A recusa CONTINUA
    # (fail-closed) — só o diagnóstico melhora.
    regen=$(printf '%s\n' "$dirty" | python3 -c '
import re, sys
pats = [r"(^|/)__pycache__/", r"\.pyc$", r"(^|/)\.pytest_cache/",
        r"(^|/)node_modules/\.cache/"]
paths = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line.strip():
        continue
    p = line[3:] if len(line) > 3 else line
    for side in (p.split(" -> ") if " -> " in p else [p]):
        paths.append(side.strip().strip(chr(34)))
if paths and all(any(re.search(pat, p) for pat in pats) for p in paths):
    print("\n".join(sorted(set(paths))))
' 2>/dev/null || true)
    if [ -n "$regen" ]; then
      echo "dirty é artefato regenerado pelo oráculo — candidatos a .gitignore/untrack:" >&2
      printf '%s\n' "$regen" | sed 's/^/  /' >&2
    fi
    exit 1
  fi
  echo "preflight: árvore limpa — ok"
fi

# (4) staging não pode ter resto pré-staged de outro agente (o commit de
# nascimento do autarca varreu incident alheio JÁ staged).
staged=$(git -C "$TARGET" diff --cached --name-only)
if [ -n "$staged" ]; then
  echo "PREFLIGHT FALHOU: staging area já contém arquivos (pré-staged por outro agente?):" >&2
  echo "$staged" | head -20 >&2
  exit 1
fi
echo "preflight: staging vazio — ok"

# (5) comando custom do alvo (pg_isready, docker ps, curl de serviço…)
if [ -n "$CUSTOM_CMD" ]; then
  if ( cd "$TARGET" && bash -c "$CUSTOM_CMD" ); then
    echo "preflight: custom '$CUSTOM_CMD' — ok"
  else
    fail "comando custom falhou: $CUSTOM_CMD"
  fi
fi

echo "preflight: PASS"
exit 0
