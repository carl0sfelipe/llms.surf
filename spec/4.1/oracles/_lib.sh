#!/usr/bin/env bash
# Funções comuns dos oráculos do corte 4.1. Um oráculo é um comando shell que falha antes do
# trabalho existir e passa depois. Lê só o que está no disco; a opinião do modelo é irrelevante.
set -u
ROOT="${ORACFIT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 2
FALHAS=0
falha() { echo "FALHA: $*" >&2; FALHAS=$((FALHAS + 1)); }
ok() { echo "ok: $*"; }
exige_arquivo() { [ -s "$1" ] && ok "existe $1" || falha "arquivo ausente ou vazio: $1"; }
exige_grep() { grep -qE -- "$1" "$2" 2>/dev/null && ok "${3:-$2 contém /$1/}" || falha "${3:-$2 não contém /$1/}"; }
proibe_grep() { if grep -qE -- "$1" "$2" 2>/dev/null; then falha "${3:-$2 contém /$1/ (proibido)}"; grep -nE -- "$1" "$2" | head -n 5 >&2; else ok "${3:-$2 livre de /$1/}"; fi; }
passa() { # passa <descricao> <comando...>
  local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else falha "$d (exit $?)"; fi
}
# Fonte da verdade das contagens públicas: DATA.stats em site/app.js (mesma fonte do test-site-honesty).
stat_js() { python3 - "$ROOT/site/app.js" "$1" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"stats:\s*\{(.*?)\n\s*\}", t, re.S)
b = m.group(1) if m else ""
k = re.search(rf"{re.escape(sys.argv[2])}:\s*(\d+|\"[^\"]+\")", b)
print(k.group(1).strip('"') if k else "")
PY
}
n_suites() { find tests -maxdepth 1 -name 'test-*.sh' | wc -l | tr -d ' '; }
n_incidents() { find incidents -name '*.md' ! -name README.md ! -path '*/uso/*' | wc -l | tr -d ' '; }
# Copia a árvore (sem .git) para um tmp, aplica um sed e roda um teste; espera que o teste FALHE.
mutacao_deve_falhar() { # mutacao_deve_falhar <descricao> <arquivo> <sed-expr> <teste>
  local d="$1" f="$2" expr="$3" teste="$4" tmp
  tmp=$(mktemp -d); rsync -a --exclude .git --exclude ledger --exclude .dispatch "$ROOT/" "$tmp/" 2>/dev/null || cp -r "$ROOT/." "$tmp/"
  sed -i -E "$expr" "$tmp/$f"
  if ( cd "$tmp" && bash "$teste" >/dev/null 2>&1 ); then falha "$d: o gate NÃO detectou a adulteração de $f"; else ok "$d: gate detecta adulteração de $f"; fi
  rm -rf "$tmp"
}
contagens_publicas_batem() {
  local S; S=$(n_suites)
  [ "$(stat_js suites)" = "$S" ] && ok "app.js stats.suites = $S" || falha "app.js stats.suites=$(stat_js suites), árvore tem $S suítes"
  grep -qE "test suites: *$S\b" site/llms.txt && ok "llms.txt test suites = $S" || falha "llms.txt não diz 'test suites: $S'"
  grep -qE "\b$S test suites" README.md && ok "README test suites = $S" || falha "README.md não diz '$S test suites'"
  passa "tests/test-site-honesty.sh" bash tests/test-site-honesty.sh
  passa "bin/check-docs.sh" bash bin/check-docs.sh
}
veredito() { if [ "$FALHAS" -eq 0 ]; then echo "ORÁCULO VERDE"; exit 0; else echo "ORÁCULO VERMELHO ($FALHAS falha(s))" >&2; exit 1; fi; }
