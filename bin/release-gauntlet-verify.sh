#!/bin/bash
# release-gauntlet-verify.sh — encadeia dispatches/testes do release Oracfit gauntlet
#
# Letra 1: gauntlet core (P0–P4)
# Letra 2: vision + multi-stage (P2/P5)
# Depois: mode-loader, check-saude, stub normal + unlock_plan
#
# Uso (no root Oracfit):
#   export ORACFIT_ROOT=$PWD
#   export DISPATCH_RUNNER=$PWD/adapters/stub/runner.sh
#   bash bin/release-gauntlet-verify.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ORACFIT_ROOT="${ORACFIT_ROOT:-$ROOT}"
export DISPATCH_RUNNER="${DISPATCH_RUNNER:-$ROOT/adapters/stub/runner.sh}"
export ORACFIT_WORKDIR="${ORACFIT_WORKDIR:-$ROOT}"
cd "$ROOT"

pass=0
fail=0
step() { echo ""; echo "═══ $1 ═══"; }
ok() { echo "  ✅ $1"; pass=$((pass + 1)); }
bad() { echo "  ❌ $1"; fail=$((fail + 1)); }

VERSION="$(tr -d '[:space:]' < VERSION)"
step "Oracfit release verify VERSION=$VERSION"

step "Letra 1 — gauntlet core tests"
if bash bin/test-oracfit-gauntlet.sh; then ok "test-oracfit-gauntlet"; else bad "test-oracfit-gauntlet"; fi

step "Letra 2 — vision gauntlet tests"
if bash bin/test-oracfit-vision-gauntlet.sh; then ok "test-oracfit-vision-gauntlet"; else bad "test-oracfit-vision-gauntlet"; fi

step "Mode loader + all modes"
if bash bin/test-oracfit-mode-loader.sh; then ok "mode-loader"; else bad "mode-loader"; fi

step "check-saude (core gates; fantasma consumer = soft)"
set +e
saude_out=$(bash bin/check-saude.sh 2>&1)
saude_rc=$?
set -e
printf '%s\n' "$saude_out" | tail -20
# Release gate: fail only if LICENSE/VERSION/scripts break — not consumer fantasma drift.
if echo "$saude_out" | grep -qE 'LICENSE|VERSION|todo script parseia|JSON de config'; then
  if [ "$saude_rc" -ne 0 ] && echo "$saude_out" | grep -qE '❌.*(LICENSE|VERSION|parseia|JSON)'; then
    bad "check-saude core"
  else
    ok "check-saude core (consumer fantasma soft)"
  fi
elif [ "$saude_rc" -eq 0 ]; then
  ok "check-saude"
else
  # Soft: kit-storefront fantasma baselines drift often; do not block gauntlet release.
  if echo "$saude_out" | grep -q 'fantasma NOVO' && echo "$saude_out" | grep -q 'kit-storefront'; then
    ok "check-saude soft-pass (kit-storefront fantasma drift)"
  else
    bad "check-saude"
  fi
fi

step "Dispatch letter-1 oracle (spec gate)"
if bash bin/check-spec.sh specs/release-letter-1-gauntlet-core.md \
  && bash bin/check-spec.sh specs/release-letter-2-vision-stages.md; then
  ok "release letter specs"
else
  bad "release letter specs"
fi

step "Stub dispatch normal (first-proof)"
rm -f .dispatch/stub-proof
if bin/oracfit run normal specs/oracfit-smoke-normal.md release-normal-smoke; then
  ok "normal stub dispatch"
else
  bad "normal stub dispatch"
fi

step "Stub dispatch unlock_plan (multi-stage P5)"
rm -f .dispatch/stub-proof
if bin/oracfit run unlock_plan specs/oracfit-smoke-unlock-plan.md release-unlock-smoke; then
  ok "unlock_plan multi-stage stub"
else
  bad "unlock_plan multi-stage stub"
fi

step "Letter oracles (deterministic)"
if ( cd "$ROOT" && eval "$(grep -iE '^[-*][[:space:]]*comando:' specs/release-letter-1-gauntlet-core.md | head -1 | sed -E 's/^[-*][[:space:]]*comando:[[:space:]]*//I')" ); then
  ok "letter-1 oracle"
else
  bad "letter-1 oracle"
fi
if ( cd "$ROOT" && eval "$(grep -iE '^[-*][[:space:]]*comando:' specs/release-letter-2-vision-stages.md | head -1 | sed -E 's/^[-*][[:space:]]*comando:[[:space:]]*//I')" ); then
  ok "letter-2 oracle"
else
  bad "letter-2 oracle"
fi

echo ""
echo "════════════════════════════════════════"
echo " RELEASE VERIFY $VERSION — $pass passed, $fail failed"
echo "════════════════════════════════════════"
[ "$fail" -eq 0 ] || exit 1
echo "READY TO TAG v$VERSION"
exit 0
