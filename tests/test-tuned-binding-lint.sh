#!/bin/bash
# test-tuned-binding-lint.sh — S11: model_ref tuned/ fantasma reprova antes do run.
# Casos: fantasma nomeia o id e reprova · sem tuned/ não muda nada ·
# id presente em registry fixture passa · registry ausente reprova mais alto.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$ROOT/bin/lib-oracfit-mode-loader.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_mode() { # $1=dir $2=id $3=model_ref ("" = stage sem model_ref)
  local dir="$1" id="$2" ref="$3"
  mkdir -p "$dir"
  {
    echo "id: $id"
    echo "description: fixture para a lint do binding tuned (S11)"
    echo "stages:"
    echo "  - role: implement"
    if [ -n "$ref" ]; then echo "    model_ref: $ref"; fi
  } > "$dir/$id.yaml"
}

make_registry() { # $1=dir $2...=ids
  local dir="$1"; shift
  mkdir -p "$dir"
  local ids=""
  for id in "$@"; do ids+="{\"id\": \"$id\"},"; done
  printf '{"models": [%s]}\n' "${ids%,}" > "$dir/model-registry.json"
}

# caso 1: fantasma reprova NOMEANDO o id
make_mode "$TMP/caseA" "tuned-lint-ghost" "tuned/teste-dominio-q4"
make_registry "$TMP/caseA-root" "outro-modelo"
if python3 "$LOADER" lint "$TMP/caseA/tuned-lint-ghost.yaml" --root "$TMP/caseA-root" \
    2>"$TMP/errA"; then
  echo "FAIL caso 1: fantasma tuned/ passou na lint"; exit 1
fi
grep -q "tuned/teste-dominio-q4" "$TMP/errA" \
  || { echo "FAIL caso 1: reprova mas não nomeia o id"; exit 1; }

# caso 2: yaml SEM tuned/ não muda nada (usa o registry real do repo)
make_mode "$TMP/caseB" "tuned-lint-clean" ""
python3 "$LOADER" lint "$TMP/caseB/tuned-lint-clean.yaml" --root "$ROOT" >/dev/null 2>&1 \
  || { echo "FAIL caso 2: yaml sem tuned/ quebrou a lint"; exit 1; }

# caso 3: id presente no registry fixture passa
make_mode "$TMP/caseC" "tuned-lint-bound" "tuned/teste-dominio-q4"
make_registry "$TMP/caseC-root" "outro-modelo" "tuned/teste-dominio-q4"
python3 "$LOADER" lint "$TMP/caseC/tuned-lint-bound.yaml" --root "$TMP/caseC-root" >/dev/null 2>&1 \
  || { echo "FAIL caso 3: id presente no registry foi reprovado"; exit 1; }

# caso 4: registry AUSENTE com tuned/ presente reprova mais alto ainda
make_mode "$TMP/caseD" "tuned-lint-noreg" "tuned/teste-dominio-q4"
if python3 "$LOADER" lint "$TMP/caseD/tuned-lint-noreg.yaml" --root "$TMP/caseD-root" \
    2>"$TMP/errD"; then
  echo "FAIL caso 4: registry ausente passou com tuned/ presente"; exit 1
fi
grep -q "model-registry.json" "$TMP/errD" \
  || { echo "FAIL caso 4: não diz que o registry está ausente"; exit 1; }

echo "test-tuned-binding-lint: ok (4 casos)"
exit 0
