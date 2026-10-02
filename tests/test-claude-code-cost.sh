#!/bin/bash
# tests/test-claude-code-cost.sh — custo real do executor no ledger + escrita negada para na hora.
#
# Fecha: incidents/2026-10-02-claude-code-runner-sai-0-com-escrita-negada.md
# Proposta: docs/proposta-check-delegacao.md §4 (ledger gravava estimated_cost="0").
# Padrão: tests/test-model-override.sh (mktemp, contadores, exit 1 se falhar).
# Nenhum modelo de verdade: CLAUDE_BIN aponta para um claude falso.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/adapters/claude-code/runner.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-cc-cost.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# claude falso: imprime o JSON de $FAKE_JSON (ou texto puro) e, se FAKE_TOUCH, cria o arquivo.
FAKE="$TMPDIR/claude"
cat >"$FAKE" <<'EOF'
#!/bin/bash
echo "aviso qualquer no stderr" >&2
[ -n "${FAKE_TOUCH:-}" ] && touch "$FAKE_TOUCH"
cat "$FAKE_JSON"
EOF
chmod +x "$FAKE"

json() { # $1 = custo, $2 = lista JSON de permission_denials
  printf '{"type":"result","subtype":"success","is_error":false,"result":"feito","total_cost_usd":%s,"usage":{"input_tokens":120,"cache_read_input_tokens":8000,"cache_creation_input_tokens":900,"output_tokens":310},"permission_denials":%s}\n' "$1" "$2"
}

SPEC="$TMPDIR/spec.md"
printf 'faça a tarefa\n' >"$SPEC"
export CLAUDE_BIN="$FAKE" DISPATCH_RUNNER_FORMAT_JSON=1

echo "== 1. runner: sucesso grava custo e sai 0"
json 0.41 '[]' >"$TMPDIR/ok.json"
export ORACFIT_COST_FILE="$TMPDIR/cost1.jsonl"
if FAKE_JSON="$TMPDIR/ok.json" "$RUNNER" claude-sonnet-5 "$SPEC" >/dev/null 2>&1; then ok "exit 0"; else not "exit 0"; fi
python3 - "$ORACFIT_COST_FILE" <<'PY' && ok "custo e tokens no arquivo" || not "custo e tokens no arquivo"
import json, sys
d = json.loads(open(sys.argv[1]).read().strip())
assert d["cost_usd"] == 0.41 and d["in_tok"] == 120 and d["cache_read_tok"] == 8000 and d["out_tok"] == 310, d
assert d["denied_writes"] == 0, d
PY

echo "== 2. runner: Write negado sai 3 com instrução"
json 0.05 '[{"tool_name":"Write","tool_use_id":"t1","tool_input":{}},{"tool_name":"Bash","tool_use_id":"t2","tool_input":{}}]' >"$TMPDIR/neg.json"
export ORACFIT_COST_FILE="$TMPDIR/cost2.jsonl"
set +e
err="$(FAKE_JSON="$TMPDIR/neg.json" "$RUNNER" claude-sonnet-5 "$SPEC" 2>&1 >/dev/null)"; rc=$?
set -e
[ "$rc" -eq 3 ] && ok "exit 3" || not "exit 3 (veio $rc)"
printf '%s' "$err" | grep -q "DISPATCH_ALLOWED_TOOLS" && ok "mensagem cita DISPATCH_ALLOWED_TOOLS" || not "mensagem cita DISPATCH_ALLOWED_TOOLS"
[ -s "$ORACFIT_COST_FILE" ] && ok "custo gravado mesmo negado" || not "custo gravado mesmo negado"

echo "== 3. runner: só Bash negado (não é escrita) não derruba o run"
json 0.02 '[{"tool_name":"Bash","tool_use_id":"t3","tool_input":{}}]' >"$TMPDIR/bash.json"
if FAKE_JSON="$TMPDIR/bash.json" "$RUNNER" claude-sonnet-5 "$SPEC" >/dev/null 2>&1; then ok "exit 0"; else not "exit 0"; fi

echo "== 4. runner: saída sem JSON segue como antes"
printf 'texto puro\n' >"$TMPDIR/txt.json"
export ORACFIT_COST_FILE="$TMPDIR/cost4.jsonl"; : >"$ORACFIT_COST_FILE"
if FAKE_JSON="$TMPDIR/txt.json" "$RUNNER" claude-sonnet-5 "$SPEC" >/dev/null 2>&1; then ok "exit 0"; else not "exit 0"; fi
[ ! -s "$ORACFIT_COST_FILE" ] && ok "nenhum custo inventado" || not "nenhum custo inventado"
unset ORACFIT_COST_FILE

echo "== 5. dispatch-mode ponta a ponta"
spec_e2e() { # $1 = marcador do oráculo
  cat <<EOF
# fixture custo claude-code

## Objetivo
Criar o arquivo $1. Não invente números além dos dados verificados.

## Dados verificados
Nenhum fato numérico.

## Oráculo
- comando: test -f $1
- exit esperado: 0

## Barra
- nome: fixture custo

NUNCA use declare const como workaround.
EOF
}
run_e2e() { # $1 = dir, $2 = json do fake, $3 = FAKE_TOUCH ("" = não escreve)
  mkdir -p "$1"
  spec_e2e marker >"$1/spec.md"
  ( cd "$1" && FAKE_JSON="$2" FAKE_TOUCH="$3" ORACFIT_WORKDIR="$1" DISPATCH_RUNNER="$RUNNER" \
      DISPATCH_MODEL_REF=claude-sonnet-5 "$ROOT/bin/dispatch-mode.sh" normal spec.md fixture-cost >"$1/out.log" 2>&1 ) || true
}
ledger_ultimo() { tail -1 "$1/.dispatch/ledger/mode.jsonl"; }

E1="$TMPDIR/e2e-ok"
run_e2e "$E1" "$TMPDIR/ok.json" "$E1/marker"
python3 - "$(ledger_ultimo "$E1")" <<'PY' && ok "ledger: pass com custo 0.41 e tokens" || { not "ledger: pass com custo 0.41 e tokens"; tail -20 "$E1/out.log"; }
import json, sys
d = json.loads(sys.argv[1])
assert d["status"] == "pass", d
assert abs(float(d["estimated_cost"]) - 0.41) < 1e-9, d
assert int(d["executor_in_tok"]) == 120 + 8000 + 900 and int(d["executor_out_tok"]) == 310, d
PY

E2="$TMPDIR/e2e-negado"
run_e2e "$E2" "$TMPDIR/neg.json" ""
python3 - "$(ledger_ultimo "$E2")" <<'PY' && ok "ledger: fail em 1 tentativa (não queimou o gauntlet)" || { not "ledger: fail em 1 tentativa"; tail -20 "$E2/out.log"; }
import json, sys
d = json.loads(sys.argv[1])
assert d["status"] == "fail" and str(d["attempt"]) == "1", d
PY
grep -q '"runner_usage_error"' "$E2/.dispatch/logs/events.jsonl" && ok "evento runner_usage_error no painel" || not "evento runner_usage_error no painel"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
