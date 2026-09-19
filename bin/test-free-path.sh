#!/bin/bash
# test-free-path.sh — D5 (APERTADO, veredito do Fable): o gate que prova o
# fim do incidente E5 ("free path" servia id morto e credencial herdada
# virava provider pago sem ninguém pedir).
#
# Pernas:
#   1. catálogo carimbado válido (schema + ref ∈ registry)
#   2. resolve-tier tier:cheap >= 3 refs VIVOS, keyless primeiro
#   3. catálogo ausente = exit 2 LOUD (nunca degrada)
#   4. R2: feed morto NUNCA sobrescreve o snapshot bom
#   5. exclusividade de credencial (gate estrutural, 3 anéis)
#   6. R5: consumidores do ledger não re-resolvem id via registry
#   7. DESPACHO COM ENVS PAGAS ENVENENADAS (isca prova imunidade — ambiente
#      limpo só prova ausência): dispatch stub tier:cheap com baits em
#      AWS_*/OPENROUTER/GROQ/NVIDIA/DEEPSEEK; o run fecha com
#      provider_efetivo ∈ allowlist, allowlist_status=ok e NENHUMA isca lida
#   8. allowlist ADULTERADA → run marcado violado (gate não mente verde)
#
# Sem rede real de modelo: runner stub. Exit 0 = caminho free íntegro.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not_() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-free-path (E5-D5 apertado) ==="

# ── 1. catálogo carimbado ────────────────────────────────────────────────────
python3 - "$ROOT/data/free-catalog.json" "$ROOT/model-registry.json" <<'PY1'
import json, sys
cat = json.load(open(sys.argv[1], encoding="utf-8"))
assert cat.get("kind") == "free-catalog/1" and cat.get("stamped_at")
reg_ids = {m["id"] for m in json.load(open(sys.argv[2], encoding="utf-8"))["models"]}
assert all(m["ref"] in reg_ids for m in cat["models"]), "ref fora do registry"
PY1
[ $? -eq 0 ] && ok "catálogo carimbado válido" || not_ "catálogo inválido"

# ── 2. resolve-tier: >=3 vivos, keyless primeiro ─────────────────────────────
REFS=$(python3 "$ROOT/bin/lib-oracfit-mode-loader.py" resolve-tier tier:cheap 2>/dev/null)
N_REFS=$(printf '%s\n' "$REFS" | grep -c . || true)
if [ "$N_REFS" -ge 3 ]; then ok "resolve-tier devolve $N_REFS refs (>=3)"; else not_ "só $N_REFS refs"; fi
FIRST=$(printf '%s\n' "$REFS" | head -1)
KEYLESS_FIRST=$(python3 - "$ROOT/data/free-catalog.json" "$FIRST" <<'PY2'
import json, sys
cat = json.load(open(sys.argv[1], encoding="utf-8"))
m = next(m for m in cat["models"] if m["ref"] == sys.argv[2])
print("1" if m["keyless"] else "0")
PY2
)
[ "$KEYLESS_FIRST" = "1" ] && ok "primeiro da fila é keyless ($FIRST)" || not_ "primeiro não é keyless: $FIRST"
DEAD_IN_REFS=$(python3 - "$ROOT/model-registry.json" <<'PY3'
import json, sys
reg = {m["id"]: (m.get("id_status") or "") for m in json.load(open(sys.argv[1]))["models"]}
refs = [l.strip() for l in """$REFS""".splitlines() if l.strip()]
bad = [r for r in refs if any(d in reg.get(r, "") for d in ("FANTASMA", "NAO-ENCONTRADO", "NAO-VERIFICADO"))]
print(",".join(bad))
PY3
)
[ -z "$DEAD_IN_REFS" ] && ok "nenhum ref morto na lista (M2)" || not_ "refs mortos na lista: $DEAD_IN_REFS"

# ── 3. catálogo ausente = exit 2 ─────────────────────────────────────────────
RC=0
python3 "$ROOT/bin/lib-oracfit-mode-loader.py" resolve-tier tier:cheap --catalog /tmp/free-catalog-fantasma-$$.json >/dev/null 2>&1 || RC=$?
rm -f /tmp/free-catalog-fantasma-$$.json
[ "$RC" -eq 2 ] && ok "catálogo ausente reprova loud (exit 2)" || not_ "catálogo ausente devolveu $RC"

# ── 4. R2: feed morto mantém snapshot ────────────────────────────────────────
SHA_BEFORE=$(shasum -a 256 "$ROOT/data/free-catalog.json" | cut -d' ' -f1)
OR_FEED_ENDPOINT="http://127.0.0.1:1/models" bash "$ROOT/bin/sync-free-catalog.sh" >/dev/null 2>&1
SHA_AFTER=$(shasum -a 256 "$ROOT/data/free-catalog.json" | cut -d' ' -f1)
if [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then ok "R2: feed morto mantém snapshot"; else not_ "R2: snapshot SOBRESCRITO"; fi

# ── 5. exclusividade de credencial ───────────────────────────────────────────
if bash "$ROOT/bin/check-free-credential-exclusivity.sh" >/dev/null 2>&1; then
  ok "gate de exclusividade (3 anéis) verde"
else
  not_ "gate de exclusividade reprova"
fi

# ── 6. R5: ledger autossuficiente ────────────────────────────────────────────
RE_RESOLVE=$(grep -l "model-registry\|MODEL_REGISTRY" \
  "$ROOT/bin/ledger.sh" "$ROOT/bin/ledger-finalize.sh" \
  "$ROOT"/bin/poll-status.sh "$ROOT/bin/oracfit" 2>/dev/null || true)
if [ -z "$RE_RESOLVE" ]; then ok "R5: consumidores do ledger não re-resolvem registry"; else not_ "re-resolução em: $RE_RESOLVE"; fi

# ── 7. DESPACHO COM ENVS PAGAS ENVENENADAS ───────────────────────────────────
WD=$(mktemp -d /tmp/free-path-d5-XXXXXX)
trap 'rm -rf "$WD"' EXIT
git -C "$WD" init -q
git -C "$WD" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

SPEC="$WD/spec-free-d5.md"
cat > "$SPEC" <<'EOS'
# spec: free-path-d5 — caminho free sob env paga envenenada (stub)

Fixture do D5: mede o CAMINHO (tier → catálogo → cadeia → ledger), não
capacidade de modelo.

## Tarefa

Crie o arquivo `.dispatch/stub-proof` com exatamente 3 linhas:

    stub_ok
    model_id=<o identificador do modelo com que você foi lançado>
    spec=<o nome desta spec>

## Regras

Nao invente outro caminho, numero, prazo ou fato alem do listado abaixo.
Nao use declare const como workaround — artefato inexistente nao se
declara, se cria.

## Dados verificados

- Existe `.dispatch` no workdir — o dispatcher cria o diretório antes de
  qualquer preflight, em todo run.

## Oráculo

- comando: test -f .dispatch/stub-proof && grep -q stub_ok .dispatch/stub-proof
- exit esperado: 0 — antes do run, exit 1 sem stderr é o estado correto.
EOS

export LOG_DIR="$WD/logs" PID_DIR="$WD/pids" DB_PATH="$WD/sem-db.sqlite"
export LEDGER_DIR="$WD/ledger"
export DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh"
export ORACFIT_ROOT="$ROOT"
mkdir -p "$LOG_DIR" "$PID_DIR"

# As ISCAS: valores falsos em credenciais pagas. Se QUALQUER código do
# caminho free ler env herdada, a isca vaza num artefato e a perna reprova.
# (cd "$WD": o dispatch usa $PWD como workdir do run — sem isso o stub
# escreveria .dispatch/stub-proof na RAIZ deste repo e o run seguinte
# reprovaria em "oráculo já passa". Foi exatamente o que aconteceu.)
export AWS_ACCESS_KEY_ID='BAIT-AWS-7f3a' AWS_SECRET_ACCESS_KEY='BAIT-AWS-7f3a' \
  AWS_SESSION_TOKEN='BAIT-AWS-7f3a' OPENROUTER_API_KEY='BAIT-OR-91cd' \
  OR_API_KEY='BAIT-OR-91cd' GROQ_API_KEY='BAIT-GROQ-22ab' \
  NVIDIA_API_KEY='BAIT-NV-55ee' DEEPSEEK_API_KEY='BAIT-DS-88bc'
( cd "$WD" && bash "$ROOT/bin/dispatch.sh" tier:cheap "$SPEC" d5-envenenado ) > "$WD/dispatch-out.log" 2>&1
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
  OPENROUTER_API_KEY OR_API_KEY GROQ_API_KEY NVIDIA_API_KEY DEEPSEEK_API_KEY

# Espera o finalizador gravar a linha do ledger (teto 60s).
LEDGER_LINE=""
for i in $(seq 1 60); do
  LEDGER_LINE=$(grep -F '"task_name": "d5-envenenado"' "$LEDGER_DIR/ledger.jsonl" 2>/dev/null | head -1)
  [ -n "$LEDGER_LINE" ] && break
  sleep 1
done
if [ -n "$LEDGER_LINE" ]; then ok "dispatch envenenado fechou com linha no ledger"; else
  not_ "linha do ledger não apareceu em 60s — dispatch-out.log:"
  sed 's/^/    /' "$WD/dispatch-out.log" 2>/dev/null | head -15
fi

ALLOW_OK=$(printf '%s' "$LEDGER_LINE" | python3 -c '
import json, sys
try:
    r = json.loads(sys.stdin.read())
    print(r.get("allowlist_status", ""), r.get("provider_efetivo", ""), r.get("provider_efetivo_ref", ""))
except Exception:
    print("parse-erro")
')
ALLOW_STATUS=$(echo "$ALLOW_OK" | cut -d' ' -f1)
PROV_EF=$(echo "$ALLOW_OK" | cut -d' ' -f2)
REF_EF=$(echo "$ALLOW_OK" | cut -d' ' -f3)
if [ "$ALLOW_STATUS" = "ok" ]; then ok "allowlist_status=ok no run envenenado"; else not_ "allowlist_status=$ALLOW_STATUS (esperado ok)"; fi
if printf '%s\n' "$REFS" | grep -qF "$REF_EF"; then
  ok "provider_efetivo_ref ($REF_EF) veio da lista do tier"
else
  not_ "provider_efetivo_ref ($REF_EF) fora da lista do tier"
fi

VAZOU=0
grep -rq "BAIT-AWS\|BAIT-OR\|BAIT-GROQ\|BAIT-NV\|BAIT-DS" "$LOG_DIR" "$LEDGER_DIR" "$WD/pids" 2>/dev/null && VAZOU=1
if [ "$VAZOU" -eq 0 ]; then
  ok "nenhuma isca vazou em log/ledger/efetivo (imunidade a env herdada)"
else
  not_ "ISCA VAZOU — código do caminho free leu credencial de env"
fi

# ── 8. allowlist adulterada → violado ────────────────────────────────────────
TAMPER="$WD/allowlist-tampered.json"
cat > "$TAMPER" <<'EOT'
{"kind": "free-provider-allowlist/1", "updated": "2026-08-31", "note": "teste", "providers": ["provider-inexistente"]}
EOT
export FREE_PROVIDER_ALLOWLIST="$TAMPER"
LEDGER_BEFORE=$(wc -l < "$LEDGER_DIR/ledger.jsonl" 2>/dev/null || echo 0)
# Oráculo volta a vermelho: o proof da perna 7 faria o preflight recusar
# ("oráculo já passa não mede nada") — mesma regra da porta, outro run.
rm -f "$WD/.dispatch/stub-proof"
export AWS_ACCESS_KEY_ID='BAIT-XX-0000'
( cd "$WD" && bash "$ROOT/bin/dispatch.sh" tier:cheap "$SPEC" d5-tamper ) > "$WD/dispatch-tamper.log" 2>&1
unset AWS_ACCESS_KEY_ID
TAMPER_LINE=""
for i in $(seq 1 60); do
  TAMPER_LINE=$(tail -n +"$((LEDGER_BEFORE + 1))" "$LEDGER_DIR/ledger.jsonl" 2>/dev/null | grep -F '"task_name": "d5-tamper"' | head -1)
  [ -n "$TAMPER_LINE" ] && break
  sleep 1
done
TAMPER_STATUS=$(printf '%s' "$TAMPER_LINE" | python3 -c '
import json, sys
try:
    print(json.loads(sys.stdin.read()).get("allowlist_status", ""))
except Exception:
    print("parse-erro")
')
if [ "$TAMPER_STATUS" = "violado" ]; then
  ok "allowlist adulterada → allowlist_status=violado (gate não mente verde)"
else
  not_ "allowlist adulterada devolveu '$TAMPER_STATUS' (esperado violado)"
fi

# ── 9. storage de credencial ILEGÍVEL = exit 3 (sugestão do Fable no E6:
#     o fail-loud da lib existia em código, não em gate) ────────────────────
CORRUPT="$WD/auth-corrupto.json"
echo '{auth quebrada' > "$CORRUPT"
ORACFIT_AUTH_JSON="$CORRUPT" ORACFIT_OPENCODE_CONFIG="$WD/inexistente.json" \
  bash -c 'source "'"$ROOT"'/bin/lib-free-credentials.sh"; free_cred_has_provider opencode' >/dev/null 2>&1
RC_CORRUPT=$?
if [ "$RC_CORRUPT" -eq 3 ]; then
  ok "auth.json corrompido → exit 3 fail-loud (não vira 'sem chave')"
else
  not_ "storage ilegível devolveu rc=$RC_CORRUPT (esperado 3)"
fi

# ── 10. risco E6-1: sync sem opencode NUNCA apaga a perna keyless ────────────
SHA_KB=$(shasum -a 256 "$ROOT/data/free-catalog.json" | cut -d' ' -f1)
NOOC_BIN="$WD/nooc-bin"; mkdir -p "$NOOC_BIN"
for tool in curl mktemp python3 timeout rm mv mkdir dirname basename cat; do
  P="$(command -v "$tool" 2>/dev/null)" && ln -sf "$P" "$NOOC_BIN/$tool"
done
( PATH="$NOOC_BIN:/usr/bin:/bin" \
  bash "$ROOT/bin/sync-free-catalog.sh" ) >/dev/null 2>&1
RC_NOOC=$?
SHA_KA=$(shasum -a 256 "$ROOT/data/free-catalog.json" | cut -d' ' -f1)
if [ "$RC_NOOC" -eq 1 ] && [ "$SHA_KB" = "$SHA_KA" ]; then
  ok "sync sem opencode aborta loud e mantém a perna keyless (risco E6-1)"
else
  not_ "sync sem opencode: rc=$RC_NOOC, snapshot-mantido=$([ "$SHA_KB" = "$SHA_KA" ] && echo sim || echo NAO)"
fi

# ── 11. provider vazio no TSV não vira provider '1' (IFS tab) ────────────────
# tier:expensive cai num ref fora do catálogo free. Sem credencial em arquivo
# (o caso do CI), o gate tem de chamar o stub — não pular um provider
# fantasma '1' porque o bash colapsou o campo vazio.
EXP_WD="$WD/expensive-empty-prov"
mkdir -p "$EXP_WD"
AUTH_MISS="$WD/auth-ausente.json"
CFG_MISS="$WD/opencode-ausente.json"
rm -f "$AUTH_MISS" "$CFG_MISS" "$EXP_WD/.dispatch/stub-proof"
ORACFIT_AUTH_JSON="$AUTH_MISS" ORACFIT_OPENCODE_CONFIG="$CFG_MISS" \
ORACFIT_WORKDIR="$EXP_WD" DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
  bash "$ROOT/bin/run-with-fallback.sh" tier:expensive "$SPEC" \
  >"$WD/expensive-out.log" 2>"$WD/expensive-err.log"
RC_EXP=$?
if [ "$RC_EXP" -eq 0 ] \
   && grep -q stub_ok "$EXP_WD/.dispatch/stub-proof" 2>/dev/null \
   && ! grep -q "provider '1'" "$WD/expensive-err.log"; then
  ok "tier:expensive com provider vazio chama o stub (não inventa provider 1)"
else
  not_ "tier:expensive: rc=$RC_EXP err=$(tail -3 "$WD/expensive-err.log" 2>/dev/null)"
fi

# Legs 8–9 export fixtures; they must not leak into the kernel path.
unset FREE_PROVIDER_ALLOWLIST ORACFIT_AUTH_JSON ORACFIT_OPENCODE_CONFIG

# ── 12. D-SHELL: id_status null no registry não derruba o Python ──────────────
NULL_REG="$WD/registry-null-status.json"
python3 - "$ROOT/model-registry.json" "$NULL_REG" <<'PYNULL'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["models"] = [
    {
        "id": "null-status-probe",
        "id_status": None,
        "provider": "opencode",
        "cli_hints": {},
        "fallback": [],
    }
]
json.dump(d, open(sys.argv[2], "w"), ensure_ascii=False)
PYNULL
NULL_WD="$WD/null-status"
mkdir -p "$NULL_WD"
rm -f "$NULL_WD/.dispatch/stub-proof"
rc_null=0
MODEL_REGISTRY="$NULL_REG" ORACFIT_WORKDIR="$NULL_WD" \
  DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
  bash "$ROOT/bin/run-with-fallback.sh" null-status-probe "$SPEC" \
  >"$WD/null-status-out.log" 2>"$WD/null-status-err.log" || rc_null=$?
if [ "$rc_null" -eq 0 ] && grep -q stub_ok "$NULL_WD/.dispatch/stub-proof" 2>/dev/null \
   && ! grep -qiE 'TypeError|NoneType' "$WD/null-status-err.log"; then
  ok "id_status:null no registry não derruba o shell (D-SHELL)"
else
  not_ "id_status:null: rc=$rc_null err=$(tail -5 "$WD/null-status-err.log" 2>/dev/null)"
fi

# ── 13. T18 shadow: Python e kernel, US gated idêntico, ledger diff=0 ────────
if [ ! -x "$ROOT/kernel/target/release/dispatch-policy" ]; then
  (cd "$ROOT/kernel" && cargo build --release >/tmp/t18-kernel-build.log 2>&1) \
    || not_ "cargo build --release do kernel falhou (ver /tmp/t18-kernel-build.log)"
fi
rm -f "$WD/.dispatch/stub-proof"
LEDGER_BEFORE_S=$(wc -l < "$LEDGER_DIR/ledger.jsonl" 2>/dev/null || echo 0)
( cd "$WD" && LLMS_KERNEL=shadow DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
    bash "$ROOT/bin/dispatch.sh" tier:cheap "$SPEC" t18-shadow ) \
  >"$WD/t18-shadow.log" 2>&1 || true
SHADOW_LINE=""
for i in $(seq 1 60); do
  SHADOW_LINE=$(tail -n +"$((LEDGER_BEFORE_S + 1))" "$LEDGER_DIR/ledger.jsonl" 2>/dev/null \
    | grep -F '"task_name": "t18-shadow"' | head -1)
  [ -n "$SHADOW_LINE" ] && break
  sleep 1
done
SHADOW_DIFF=$(printf '%s' "$SHADOW_LINE" | python3 -c '
import json, sys
try:
    v = json.loads(sys.stdin.read()).get("kernel_shadow_diff", "")
    print(v if v != "" else "ausente")
except Exception:
    print("parse-erro")
')
if [ "$SHADOW_DIFF" = "0" ]; then
  ok "shadow dispatch: kernel_shadow_diff=0 no ledger"
else
  not_ "shadow dispatch: kernel_shadow_diff='$SHADOW_DIFF' (esperado 0). log:"
  sed 's/^/    /' "$WD/t18-shadow.log" 2>/dev/null | head -20
fi

echo ""
echo "=== RESULTADO: $pass pass, $fail fail ==="
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "FREE PATH ÍNTEGRO — D5 apertado fechado (envs pagas envenenadas não vazam; allowlist assertiona)"
exit 0
