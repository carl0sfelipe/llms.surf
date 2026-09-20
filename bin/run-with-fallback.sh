#!/bin/bash
# run-with-fallback.sh — executa o runner percorrendo a cadeia de fallback (RF-08)
# Uso: bin/run-with-fallback.sh <model_id> <spec_file> [--session ID] [--fork]
#
# Consome os exit codes do contrato (core/runner-contract.md):
#   exit 2 (rate limit) ou exit 4 (saldo/quota) → tenta o PRÓXIMO da cadeia
#   qualquer outro                              → devolve como está
#
# A cadeia vem do campo `fallback` do model-registry.json (RF-08.1). Modelo sem
# cadeia falha direto — nunca inventa substituto (regra 11.2).
#
# Só faz sentido porque o runner devolve 2/4 de verdade: antes do incidente incidents/2026-07-24-rate-limit-chega-como-timeout-nao-como-e.md, rate
# limit virava timeout mudo (124) e esta cadeia nunca era acionada.
#
# Env obrigatória: DISPATCH_RUNNER
# Exit: o do runner que respondeu; 2 se a cadeia inteira esgotou

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${DISPATCH_RUNNER:?Erro: env DISPATCH_RUNNER não definida. Rode: source adapters/<cli>/env.sh}"
REGISTRY="${MODEL_REGISTRY:-$REPO_ROOT/model-registry.json}"

MODEL="${1:?Uso: run-with-fallback.sh <model_id> <spec_file> [flags...]}"
SPEC="${2:?Uso: run-with-fallback.sh <model_id> <spec_file> [flags...]}"
shift 2

# E5-M6: provider por ref — quem serve de verdade vai pro ledger
# (provider_efetivo) via DISPATCH_EFETIVO_FILE quando o dispatch.sh define.
declare -A PROV_POR_REF

# Cada linha: "<id>\t<id_status ou vazio>" (incidente incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md: id_status vai junto,
# não só o id — quem consome a cadeia precisa saber se o alvo é fantasma).
if [[ "$MODEL" == tier:* ]]; then
  # E5-M4: tier expande para a LISTA fallback ordenada do catálogo free
  # carimbado (data/free-catalog.json via resolve-tier — keyless primeiro).
  # O loop de baixo continua sendo quem pula morto (id_status) e quem desvia
  # em rate limit/saldo real (exit 2/4 → usage-hub), que é o desvio
  # dirigido por evento — a copy pública NUNCA diz "quota-aware" (R3).
  #
  # E5-M5/D4: entrada keyless=false só entra se o provider tem credencial em
  # ARQUIVO (auth.json / opencode.json via lib-free-credentials — leitora
  # única). Env herdada NUNCA é consultada: é o vetor do incidente E5.
  # shellcheck source=lib-free-credentials.sh
  source "$REPO_ROOT/bin/lib-free-credentials.sh"
  CATALOG="${FREE_CATALOG:-$REPO_ROOT/data/free-catalog.json}"
  ALLOWLIST="${FREE_PROVIDER_ALLOWLIST:-$REPO_ROOT/data/free-provider-allowlist.json}"
  KERNEL_BIN="${LLMS_KERNEL_BIN:-$REPO_ROOT/kernel/target/release/dispatch-policy}"
  KERNEL_MODE="${LLMS_KERNEL:-off}"

  require_kernel_bin() {
    if [ ! -x "$KERNEL_BIN" ]; then
      echo "✖ LLMS_KERNEL=$KERNEL_MODE: dispatch-policy ausente ($KERNEL_BIN) — recusa loud, sem fallback silencioso (E5)" >&2
      exit 3
    fi
  }

  python_tier_us() {
    # Always re-emit resolve-tier stderr (T08 F1: capture_output used to
    # swallow E5-M2 WARN on success).
    REG="$REGISTRY" MODEL="$MODEL" ROOT="$REPO_ROOT" CATALOG="$CATALOG" python3 -c '
import json, os, subprocess, sys
out = subprocess.run(
    [sys.executable, os.environ["ROOT"] + "/bin/lib-oracfit-mode-loader.py",
     "resolve-tier", os.environ["MODEL"], "--registry", os.environ["REG"]],
    capture_output=True, text=True)
refs = [l.strip() for l in out.stdout.splitlines() if l.strip()]
if out.returncode != 0 or not refs:
    sys.stderr.write(out.stderr)
    sys.stderr.write("✖ tier %s não resolveu para nenhum ref vivo (E5-M4)\n" % os.environ["MODEL"])
    sys.exit(2)
try:
    statuses = {m.get("id", ""): (m.get("id_status", "") or "")
                for m in json.load(open(os.environ["REG"]))["models"]}
except Exception:
    statuses = {}
meta = {}
try:
    for m in json.load(open(os.environ["CATALOG"]))["models"]:
        meta[m.get("ref", "")] = (m.get("provider") or "", bool(m.get("keyless")))
except Exception:
    pass
# US (\\x1f), NAO tab: tab e IFS whitespace e campos vazios colapsam.
# tier:expensive resolve deepseek-v4-pro (fora do catalogo free -> provider
# vazio, keyless default 1); com tab o bash lia KEYLESS como PROVIDER=1,
# pulava o unico ref, e o stub nunca rodava — test-owner-question e
# test-go-live-local vermelhos em todo push sem auth.json.
FS = "\x1f"
for r in refs:
    prov, keyless = meta.get(r, ("", True))
    print(FS.join((r, statuses.get(r, "") or "", prov, "1" if keyless else "0")))
sys.stderr.write(out.stderr)
' || { echo "✖ cadeia do $MODEL vazia — nada despachado" >&2; exit 2; }
  }

  kernel_tier_us() {
    local err out rc
    err=$(mktemp)
    out=$(mktemp)
    "$KERNEL_BIN" resolve "$MODEL" \
      --registry "$REGISTRY" \
      --catalog "$CATALOG" \
      --allowlist "$ALLOWLIST" \
      --credentials "$(free_cred_providers_csv)" \
      >"$out" 2>"$err"
    rc=$?
    # D-SHELL: re-emit the kernel's stderr in shadow|on.
    cat "$err" >&2
    cat "$out"
    rm -f "$err" "$out"
    return "$rc"
  }

  filter_us_by_file_creds() {
    # Same gate as the loop below, silent — used only to compare with kernel.
    local REF ST PROVIDER KEYLESS
    while IFS=$'\x1f' read -r REF ST PROVIDER KEYLESS; do
      [ -n "$REF" ] || continue
      if [ "$KEYLESS" != "1" ] && [ -n "$PROVIDER" ]; then
        free_cred_has_provider "$PROVIDER" || continue
      fi
      printf '%s\x1f%s\x1f%s\x1f%s\n' "$REF" "$ST" "$PROVIDER" "$KEYLESS"
    done
  }

  write_kernel_sidecar() {
    # T18: kernel_shadow_diff. T19: policy_version (crate + kernel/ tree sha).
    local diff="${1:-}"
    local dest crate ksha
    [ -n "${DISPATCH_EFETIVO_FILE:-}" ] || return 0
    dest="${DISPATCH_EFETIVO_FILE%.efetivo}.kernel"
    crate="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$REPO_ROOT/kernel/dispatch-policy/Cargo.toml" | head -1)"
    ksha="$(git -C "$REPO_ROOT" rev-parse HEAD:kernel 2>/dev/null || true)"
    {
      [ -n "$diff" ] && printf 'kernel_shadow_diff=%s\n' "$diff"
      [ -n "$crate" ] && printf 'policy_version_crate=%s\n' "$crate"
      [ -n "$ksha" ] && printf 'policy_version_sha=%s\n' "$ksha"
    } >"$dest"
  }

  case "$KERNEL_MODE" in
    on)
      require_kernel_bin
      CHAIN_META="$(kernel_tier_us)" || { echo "✖ cadeia do $MODEL vazia (kernel) — nada despachado" >&2; exit 2; }
      write_kernel_sidecar ""
      ;;
    shadow)
      require_kernel_bin
      CHAIN_META="$(python_tier_us)" || { echo "✖ cadeia do $MODEL vazia — nada despachado" >&2; exit 2; }
      KERNEL_US="$(kernel_tier_us)" || KERNEL_US=""
      PYTHON_GATED="$(printf '%s\n' "$CHAIN_META" | filter_us_by_file_creds)"
      if [ "$(printf '%s\n' "$PYTHON_GATED")" = "$(printf '%s\n' "$KERNEL_US")" ]; then
        write_kernel_sidecar 0
      else
        write_kernel_sidecar 1
      fi
      ;;
    off|"")
      CHAIN_META="$(python_tier_us)" || { echo "✖ cadeia do $MODEL vazia — nada despachado" >&2; exit 2; }
      ;;
    *)
      echo "✖ LLMS_KERNEL must be off|shadow|on (got: $KERNEL_MODE)" >&2
      exit 3
      ;;
  esac

  CADEIA=""
  # Aviso de pulo por credencial: detalhe só na 1ª tentativa do run. O loop de
  # attempts re-executa este script inteiro por tentativa e o conteúdo não muda
  # entre tentativas (credencial em arquivo ou existe ou não) — 9 pernas × 5
  # tentativas = 45 linhas do mesmo aviso empurrando o sinal pra fora da tela
  # (incidente 2026-09-20-run-with-fallback-reimprime-pulando-sem-).
  # DISPATCH_ATTEMPT vem do loop do dispatch-mode.sh; ORACFIT_STAGE_ATTEMPT, do
  # dispatch-stages.sh; sem nenhum (chamada direta), imprime detalhe como antes.
  SKIP_ATTEMPT="${DISPATCH_ATTEMPT:-${ORACFIT_STAGE_ATTEMPT:-1}}"
  case "$SKIP_ATTEMPT" in ''|*[!0-9]*) SKIP_ATTEMPT=1 ;; esac
  PULADOS_SEM_CRED=0
  while IFS=$'\x1f' read -r REF ST PROVIDER KEYLESS; do
    [ -n "$REF" ] || continue
    if [ "$KEYLESS" != "1" ] && [ -n "$PROVIDER" ]; then
      if ! free_cred_has_provider "$PROVIDER"; then
        PULADOS_SEM_CRED=$((PULADOS_SEM_CRED + 1))
        if [ "$SKIP_ATTEMPT" -le 1 ]; then
          echo "  ↳ pulando $REF — provider '$PROVIDER' sem credencial em arquivo (E5-M5: env herdada não conta)" >&2
        fi
        continue
      fi
    fi
    CADEIA+="${REF}"$'\t'"${ST}"$'\n'
    PROV_POR_REF[$REF]="$PROVIDER"
  done <<< "$CHAIN_META"
  if [ "$PULADOS_SEM_CRED" -gt 0 ] && [ "$SKIP_ATTEMPT" -gt 1 ]; then
    echo "  ↳ $PULADOS_SEM_CRED perna(s) puladas — sem credencial em arquivo (E5-M5); detalhes na tentativa 1" >&2
  fi
  if [ -z "$CADEIA" ]; then
    echo "✖ cadeia do $MODEL vazia após gate de credencial — nada despachado (configura a chave do provider em 'opencode auth login' ou use a perna keyless)" >&2
    exit 2
  fi
else
  CADEIA=$(MODEL="$MODEL" REG="$REGISTRY" python3 -c '
import json, os, sys
d = json.load(open(os.environ["REG"]))
mid = os.environ["MODEL"]
for m in d["models"]:
    if mid in (m["id"], *(m.get("cli_hints", {}) or {}).values()):
        idx = {mm["id"]: (mm.get("id_status") or "") for mm in d["models"]}
        print(m["id"] + "\t" + (m.get("id_status") or ""))
        for f in m.get("fallback", []):
            print(f + "\t" + (idx.get(f) or ""))
        sys.exit(0)
print(mid + "\t")   # não está no registry: o runner é quem recusa (exit 3)
')
  # Mapa id→provider do registry (E5-M6: provider_efetivo por ref).
  while IFS="$(printf '\t')" read -r REF PROV; do
    [ -n "$REF" ] && PROV_POR_REF[$REF]="$PROV"
  done < <(REG="$REGISTRY" python3 -c '
import json, os
try:
    for m in json.load(open(os.environ["REG"]))["models"]:
        print(m.get("id", "") + "\t" + (m.get("provider") or ""))
except Exception:
    pass
')
fi

# Lê a cadeia pelo fd 3 (não pelo stdin padrão do loop): o runner é chamado
# dentro do loop e não pode herdar a cadeia como stdin dele.
exec 3<<EOF_CADEIA
$CADEIA
EOF_CADEIA

ULTIMO=2
TODOS_PULADOS_POR_STATUS=1
while IFS="$(printf '\t')" read -r M STATUS <&3; do
  [ -n "$M" ] || continue
  case "$STATUS" in
    *FANTASMA*|*NAO-VERIFICADO*|*NAO-ENCONTRADO*)
      echo "  ↳ ⚠️  pulando $M — id_status: $STATUS" >&2
      ULTIMO=2
      continue
      ;;
  esac
  TODOS_PULADOS_POR_STATUS=0
  echo "▶ tentando: $M" >&2
  "$DISPATCH_RUNNER" "$M" "$SPEC" "$@"
  RC=$?
  case "$RC" in
    # exit 2/4 são eventos REAIS de provider — alimentam o usage-hub (v3.5)
    # para que pre-dispatch-check e pick vetem o provider na janela seguinte,
    # em vez de redescobrir o rate limit no próximo dispatch.
    2)
      echo "  ↳ rate limit em $M — próximo da cadeia (RF-08)" >&2
      python3 "$REPO_ROOT/bin/usage-hub.py" observe --kind rate_limit \
        --model-ref "$M" --source run-with-fallback >/dev/null 2>&1 || true
      ULTIMO=2
      ;;
    4)
      echo "  ↳ saldo/quota esgotado em $M — próximo da cadeia (RF-08)" >&2
      python3 "$REPO_ROOT/bin/usage-hub.py" observe --kind balance \
        --model-ref "$M" --source run-with-fallback >/dev/null 2>&1 || true
      ULTIMO=4
      ;;
    3)
      # A cadeia de fallback é dado CLI-agnóstico: pode listar modelo que não tem
      # cli_hint para o CLI ativo. Isso é "indisponível aqui" (PRD 4.3), não erro
      # do chamador — pula, mas avisa alto para não mascarar flag inválida.
      echo "  ↳ ⚠️  $M indisponível neste CLI (exit 3) — pulando. Se não for falta de cli_hint, é erro de uso." >&2
      ULTIMO=3
      ;;
    *) 
      # E5-M6: sucesso (ou erro fatal) — registra quem SERVIU de verdade.
      # Sem arquivo definido (chamadas fora do dispatch.sh), não registra.
      if [ "$RC" -eq 0 ] && [ -n "${DISPATCH_EFETIVO_FILE:-}" ]; then
        printf '%s\t%s\n' "$M" "${PROV_POR_REF[$M]:-}" > "$DISPATCH_EFETIVO_FILE" 2>/dev/null || true
      fi
      exit "$RC" ;;
  esac
done
exec 3<&-

if [ "$TODOS_PULADOS_POR_STATUS" = "1" ]; then
  echo "✖ nenhum alvo confiável na cadeia de $MODEL — todos pulados por id_status FANTASMA/NAO-VERIFICADO (incidente incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md)" >&2
  exit 2
fi

echo "✖ cadeia de fallback esgotada para $MODEL (último motivo: exit $ULTIMO)" >&2
exit "$ULTIMO"
