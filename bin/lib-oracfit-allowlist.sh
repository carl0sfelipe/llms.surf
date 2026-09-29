# lib-oracfit-allowlist.sh — the free-path verdict, shared by every dispatch entry (E5-M6/R4, T18/T19).
# One implementation: ledger-finalize.sh (bin/dispatch.sh) and dispatch-mode.sh / dispatch-stages.sh
# (modes) must never disagree on whether a run stayed inside the owner's free allowlist.
# Nasceu em 2026-09-29: o fix de 0190e93 mandou tier:* para o dispatch-mode.sh, cujo ledger não
# gravava allowlist_status nem o sidecar do kernel — o gate E5-D5 ficou vermelho sem ter como migrar.

# oracfit_allowlist_status <provider> [ref] — prints ok | violado | sem-allowlist.
# FREE_PROVIDER_ALLOWLIST overrides the file (tests only: leg 8 of bin/test-free-path.sh).
oracfit_allowlist_status() {
  local provider="$1" ref="${2:-}" file
  file="${FREE_PROVIDER_ALLOWLIST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data/free-provider-allowlist.json}"
  if [ ! -f "$file" ]; then
    echo "⛔ allowlist ausente: $file (E5-M6/R4 — crie o arquivo antes de despachar free)" >&2
    echo "sem-allowlist"
    return 0
  fi
  if python3 - "$file" "$provider" <<'PYALLOW'
import json, sys
al = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if sys.argv[2] in (al.get("providers") or []) else 1)
PYALLOW
  then
    echo "ok"
  else
    echo "⛔ PROVIDER FORA DA ALLOWLIST DO DONO: $provider (ref $ref) — run fica marcado como violação (E5-M6/R4)" >&2
    echo "violado"
  fi
}

# oracfit_free_path_read <efetivo-file> — reads what run-with-fallback left next to the run:
#   <x>.efetivo  "ref<TAB>provider" of whoever actually served it
#   <x>.kernel   kernel_shadow_diff= / policy_version_crate= / policy_version_sha= (LLMS_KERNEL=shadow)
# Sets REF_EFETIVO PROVIDER_EFETIVO ALLOWLIST_STATUS KERNEL_SHADOW_DIFF POLICY_VERSION_CRATE
# POLICY_VERSION_SHA, and ORACFIT_FREE_FIELDS: the ledger arguments for oracfit_emit_metric_and_ledger.
# No efetivo file = the run never went through the free chain: fora-do-escopo.
oracfit_free_path_read() {
  local efetivo="${1:-}" kernel
  REF_EFETIVO=""; PROVIDER_EFETIVO=""; ALLOWLIST_STATUS="fora-do-escopo"
  KERNEL_SHADOW_DIFF=""; POLICY_VERSION_CRATE=""; POLICY_VERSION_SHA=""
  if [ -n "$efetivo" ] && [ -f "$efetivo" ]; then
    IFS=$'\t' read -r REF_EFETIVO PROVIDER_EFETIVO < "$efetivo" || true
    if [ -n "$PROVIDER_EFETIVO" ]; then
      ALLOWLIST_STATUS="$(oracfit_allowlist_status "$PROVIDER_EFETIVO" "$REF_EFETIVO")"
    else
      ALLOWLIST_STATUS="sem-provider"
    fi
  fi
  kernel="${efetivo%.efetivo}.kernel"
  if [ -n "$efetivo" ] && [ -f "$kernel" ]; then
    KERNEL_SHADOW_DIFF="$(sed -n 's/^kernel_shadow_diff=//p' "$kernel" | head -1)"
    POLICY_VERSION_CRATE="$(sed -n 's/^policy_version_crate=//p' "$kernel" | head -1)"
    POLICY_VERSION_SHA="$(sed -n 's/^policy_version_sha=//p' "$kernel" | head -1)"
  fi
  ORACFIT_FREE_FIELDS=(provider_efetivo="$PROVIDER_EFETIVO" provider_efetivo_ref="$REF_EFETIVO" allowlist_status="$ALLOWLIST_STATUS")
  [ -n "$KERNEL_SHADOW_DIFF" ] && ORACFIT_FREE_FIELDS+=("kernel_shadow_diff:int=$KERNEL_SHADOW_DIFF")
  # T19: policy_version is additive — absent when the kernel flag is off.
  if [ -n "$POLICY_VERSION_CRATE$POLICY_VERSION_SHA" ]; then
    ORACFIT_FREE_FIELDS+=("policy_version:json=$(python3 -c 'import json, sys; print(json.dumps({"crate": sys.argv[1], "kernel_sha": sys.argv[2]}))' "$POLICY_VERSION_CRATE" "$POLICY_VERSION_SHA")")
  fi
  return 0
}
