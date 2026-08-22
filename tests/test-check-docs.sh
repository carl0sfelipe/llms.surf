#!/usr/bin/env bash
# tests/test-check-docs.sh — guarda o guard de números de README.
#
# TESTE 1: sandbox com fatos conhecidos (v9.9.9, 2 incidentes, 1 suíte,
#          1 modo, 1 modelo) e 3 READMEs corretos  ⇒ gate passa.
# TESTE 2: badge de versão adulterado              ⇒ gate falha.
# TESTE 3: badge de incidentes adulterado          ⇒ gate falha.
# TESTE 4: menção em prosa adulterada              ⇒ gate falha.
# TESTE 5: menção removida (copy mudou)            ⇒ gate falha avisando
#          "padrão sumiu" — o gate não pode passar mudo quando o texto muda.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$REPO_ROOT/bin/check-docs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pas=0
falhas=0

ok()   { pas=$((pas + 1)); echo "PASS: $1"; }
falha() { falhas=$((falhas + 1)); echo "FAIL: $1"; }

# ── sandbox: árvore mínima com fatos conhecidos ────────────────────────
mkdir -p "$TMP/incidents" "$TMP/tests" "$TMP/core/modes" "$TMP/docs"
echo "9.9.9" > "$TMP/VERSION"
echo a > "$TMP/incidents/2026-01-01-um.md"
echo b > "$TMP/incidents/2026-01-02-dois.md"
echo x > "$TMP/tests/test-x.sh"
echo y > "$TMP/core/modes/um.yaml"
echo '{"models": [{"id": "m1"}]}' > "$TMP/model-registry.json"

# READMEs mínimos contendo TODOS os padrões que o gate exige.
gera_readmes() {  # gera_readmes <inc_badge> <inc_prosa> <versao_badge>
  local ib="${1:-2}" ip="${2:-2}" vb="${3:-9.9.9}"
  cat > "$TMP/README.md" <<EOF
[![Version](https://img.shields.io/badge/version-$vb-brightgreen.svg)](VERSION)
[![Incidents](https://img.shields.io/badge/incidents%E2%86%92mechanisms-$ib-orange.svg)](incidents/)
Refuse. **$ip postmortems.** So are $((ip - 2)) others.
Memory: $ip incident postmortems, 1 models in the registry, 1 modes, 1 test suites.
That's how the $ip happened. $ip and counting. $ip failures that became permanent protections.
EOF
  cat > "$TMP/docs/README.Detailed.md" <<EOF
[![Version](https://img.shields.io/badge/version-$vb-brightgreen.svg)](../VERSION)
[![Incidents](https://img.shields.io/badge/incidents%E2%86%92rules-$ib-orange.svg)](../incidents/)
$ip so far. $ip and counting. $ip failures that became protections.
EOF
  cat > "$TMP/docs/README.pt-BR.md" <<EOF
[![Version](https://img.shields.io/badge/version-$vb-brightgreen.svg)](../VERSION)
[![Incidents](https://img.shields.io/badge/incidents%E2%86%92regras-$ib-orange.svg)](../incidents/)
($ip até hoje) $ip falhas que viraram proteção
EOF
}

# TESTE 1 — tudo certo ⇒ exit 0
gera_readmes
if bash "$GATE" "$TMP" >/dev/null 2>&1; then ok "sandbox correto passa"; else falha "sandbox correto deveria passar: $(bash "$GATE" "$TMP" 2>&1 | head -3)"; fi

# TESTE 2 — badge de versão mentindo ⇒ exit 1
gera_readmes 2 2 "3.0.0"
if bash "$GATE" "$TMP" >/dev/null 2>&1; then falha "badge v3.0.0 com VERSION 9.9.9 não pode passar"; else ok "badge de versão em drift falha"; fi

# TESTE 3 — badge de incidentes mentindo (o drift real de 2026-08-22) ⇒ exit 1
gera_readmes 56
if bash "$GATE" "$TMP" >/dev/null 2>&1; then falha "badge 56 com 2 incidentes não pode passar"; else ok "badge de incidentes em drift falha"; fi

# TESTE 4 — prosa mentindo (badge certo, número no texto errado) ⇒ exit 1
gera_readmes 2 91
if bash "$GATE" "$TMP" >/dev/null 2>&1; then falha "prosa 91 com 2 incidentes não pode passar"; else ok "prosa em drift falha"; fi

# TESTE 5 — padrão sumiu (copy mudou de forma) ⇒ exit 1 E avisa "padrão sumiu"
gera_readmes
sed 's/\*\*2 postmortems\.\*\*//' "$TMP/README.md" > "$TMP/README.md.tmp" && mv "$TMP/README.md.tmp" "$TMP/README.md"
saida="$(bash "$GATE" "$TMP" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && echo "$saida" | grep -q "padrão sumiu"; then
  ok "padrão removido falha com aviso explícito"
else
  falha "padrão removido deveria falhar avisando 'padrão sumiu' (rc=$rc)"
fi

echo "──"
echo "check-docs guard: $pas PASS / $falhas FAIL"
[ "$falhas" -eq 0 ]
