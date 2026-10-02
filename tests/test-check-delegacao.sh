#!/bin/bash
# tests/test-check-delegacao.sh — vale a pena delegar esta spec a este executor?
# Proposta: docs/proposta-check-delegacao.md §2. Padrão: tests/test-verificar.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHK="$ROOT/bin/check-delegacao.py"
OF="$ROOT/bin/oracfit"
FIX="$ROOT/tests/fixtures/delegacao"
TR13="$FIX/tr-1-3-catalogo-plano.md"
TR67="$FIX/tr-6-7-demanda-politica.md"
TEL="$FIX/tel-1-telemetria-backup.md"
TMPDIR="$(mktemp -d /tmp/oracfit-check-delegacao.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_de() { set +e; "$@" >"$TMPDIR/last.log" 2>"$TMPDIR/last.err"; echo $?; set -e; }

W="$TMPDIR/w"; mkdir -p "$W"; cd "$W"
CHK_CMD=(python3 "$CHK")

echo "== 1. tr-1-3 sonnet → DIRETO, saida_tok 1920, spec_tok do arquivo"
[ "$(rc_de "${CHK_CMD[@]}" "$TR13" --executor claude-sonnet-5)" -eq 10 ] && ok "exit 10" || not "exit 10"
grep -q '^DIRETO' "$TMPDIR/last.log" && ok "linha começa DIRETO" || not "linha começa DIRETO"
[ "$(rc_de "${CHK_CMD[@]}" "$TR13" --executor claude-sonnet-5 --json)" -eq 10 ] || not "json exit 10"
python3 - "$TMPDIR/last.log" "$TR13" <<'PY' && ok "saida_tok 1920 e spec_tok=ceil(len/4)" || not "saida_tok/spec_tok"
import json, math, sys
d = json.loads(open(sys.argv[1]).read())
assert d["saida_tok"] == 1920, d
assert d["spec_tok"] == math.ceil(len(open(sys.argv[2], encoding="utf-8").read()) / 4), d
PY

echo "== 2. tr-6-7 sonnet → saida_tok 1800 (não conta Objetivo)"
[ "$(rc_de "${CHK_CMD[@]}" "$TR67" --executor claude-sonnet-5)" -eq 10 ] && ok "exit 10" || not "exit 10"
[ "$(rc_de "${CHK_CMD[@]}" "$TR67" --executor claude-sonnet-5 --json)" -eq 10 ] || not "json exit"
python3 - "$TMPDIR/last.log" <<'PY' && ok "saida_tok 1800" || not "saida_tok 1800"
import json, sys
d = json.loads(open(sys.argv[1]).read())
assert d["saida_tok"] == 1800, d
PY

echo "== 3. placa qwen → DELEGAR"
[ "$(rc_de "${CHK_CMD[@]}" "$TR13" --executor qwen-3.8-27b)" -eq 0 ] && grep -q DELEGAR "$TMPDIR/last.log" && ok "tr-1-3 qwen" || not "tr-1-3 qwen"
[ "$(rc_de "${CHK_CMD[@]}" "$TR67" --executor qwen-3.8-27b)" -eq 0 ] && grep -q DELEGAR "$TMPDIR/last.log" && ok "tr-6-7 qwen" || not "tr-6-7 qwen"

echo "== 4. tel-1 sem orçamento → exit 3"
[ "$(rc_de "${CHK_CMD[@]}" "$TEL" --executor claude-sonnet-5)" -eq 3 ] && ok "exit 3" || not "exit 3"
grep -q "orçamento de linhas" "$TMPDIR/last.err" "$TMPDIR/last.log" && ok "cita orçamento" || not "cita orçamento"

echo "== 5. grok sem preço → exit 4"
[ "$(rc_de "${CHK_CMD[@]}" "$TR13" --executor grok-4.6-xhigh-fast)" -eq 4 ] && ok "exit 4" || not "exit 4"
grep -q "core/precos.json" "$TMPDIR/last.err" "$TMPDIR/last.log" && ok "cita precos.json" || not "cita precos.json"

echo "== 6. --paralelo → DELEGAR"
[ "$(rc_de "${CHK_CMD[@]}" "$TR13" --executor claude-sonnet-5 --paralelo)" -eq 0 ] && ok "exit 0" || not "exit 0"
grep -qi paralelo "$TMPDIR/last.log" && ok "motivo paralelo" || not "motivo paralelo"

echo "== 7. ledger ≥3 attempts → tentativas 3"
mkdir -p "$W/led/.dispatch/ledger"
printf '%s\n' '{"model_id":"claude-sonnet-5","attempt":3,"status":"pass"}'{,,} \
  >"$W/led/.dispatch/ledger/mode.jsonl"
[ "$(rc_de "${CHK_CMD[@]}" "$TR13" --executor claude-sonnet-5 --json --workdir "$W/led")" -eq 10 ] || not "ledger rc"
python3 - "$TMPDIR/last.log" <<'PY' && ok "tentativas 3" || not "tentativas 3"
import json, sys
d = json.loads(open(sys.argv[1]).read())
assert d["tentativas"] == 3, d
PY

echo "== 8. spec curta ≤400 linhas: sem contexto DIRETO (regra 5), com 200k DELEGAR (regra 4)"
cat >s.md <<'EOF'
# s

## Dados verificados
- `big.bin`

## ENTREGÁVEIS
- x.py (≤ 400 linhas)
EOF
[ "$(rc_de "${CHK_CMD[@]}" s.md --executor claude-sonnet-5)" -eq 10 ] && grep -q '^DIRETO' "$TMPDIR/last.log" \
  && grep -q 'delegar custa' "$TMPDIR/last.log" && ok "regra 5 DIRETO" || not "regra 5 DIRETO"
head -c 200000 /dev/zero >big.bin
[ "$(rc_de "${CHK_CMD[@]}" s.md --executor claude-sonnet-5 --json)" -eq 0 ] || not "regra 4 rc"
python3 - "$TMPDIR/last.log" <<'PY' && ok "regra 4 contexto 50000 DELEGAR" || not "regra 4"
import json, sys
d = json.loads(open(sys.argv[1]).read())
assert d["veredito"] == "DELEGAR" and d["contexto_tok"] == 50000, d
assert "delegar custa" in d["motivo"], d
PY

echo "== 9. oracfit check-delegacao = o script"
[ "$(rc_de "$OF" check-delegacao "$TR13" --executor claude-sonnet-5 --workdir "$W")" -eq 10 ] \
  && grep -q '^DIRETO' "$TMPDIR/last.log" && ok "oracfit DIRETO" || not "oracfit DIRETO"
[ "$(rc_de "$OF" check-delegacao "$TR13" --executor qwen-3.8-27b --workdir "$W")" -eq 0 ] \
  && grep -q DELEGAR "$TMPDIR/last.log" && ok "oracfit DELEGAR" || not "oracfit DELEGAR"

echo "== modo antes da spec (--entrega): decide sem gastar a spec"
CD="$ROOT/bin/check-delegacao.py"
V="$(mktemp -d)"; head -c 200000 /dev/zero | tr '\0' x >"$V/ctx.txt"
set +e
python3 "$CD" --entrega 160 --executor claude-sonnet-5 --workdir "$V" >/dev/null 2>&1; r1=$?
python3 "$CD" --entrega 160 --contexto ctx.txt --executor claude-sonnet-5 --workdir "$V" >/dev/null 2>&1; r2=$?
python3 "$CD" --entrega 160 --executor qwen-3.8-27b --workdir "$V" >/dev/null 2>&1; r3=$?
python3 "$CD" --executor claude-sonnet-5 --workdir "$V" >/dev/null 2>&1; r4=$?
j="$(python3 "$CD" --entrega 160 --executor claude-sonnet-5 --workdir "$V" --json 2>/dev/null)"
set -e
rm -rf "$V"
[ "$r1" -eq 10 ] && ok "antes: 160 linhas sem contexto → DIRETO" || not "antes: DIRETO (veio $r1)"
[ "$r2" -eq 0 ] && ok "antes: contexto de 50k tok → DELEGAR" || not "antes: DELEGAR com contexto (veio $r2)"
[ "$r3" -eq 0 ] && ok "antes: placa → DELEGAR" || not "antes: placa (veio $r3)"
[ "$r4" -eq 3 ] && ok "sem spec e sem --entrega → uso" || not "sem --entrega (veio $r4)"
printf '%s' "$j" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["modo"]=="antes" and d["spec_tok"]==1805 and d["saida_tok"]==1920, d' \
  && ok "antes: spec estimada (0,94 × 1920 = 1805 tok)" || not "antes: spec estimada"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
