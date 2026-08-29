#!/bin/bash
# tests/test-go-live-local.sh — oráculo mecânico do pack de go-live (S1..S6).
#
# O pack (docs/go-live/) é ordem de trabalho; este teste é a prova de que o
# tree continua entregando o que o pack especifica. Roda sem rede, sem modelo
# e sem chave: check-spec das seis stories, os seis oráculos delas, as duas
# smokes despachando com stub em workdir temp, e os gates de higiene.
# docs/go-live é privado por política (D8) — mas o GATE que protege o corte
# é público e mora aqui.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
pas=0
falhas=0

ok()  { echo "PASS: $1"; pas=$((pas + 1)); }
not() { echo "FAIL: $1"; falhas=$((falhas + 1)); }

oracle_of() { # imprime a linha `- comando:` da seção ## Oráculo
  grep -iE '^[-*][[:space:]]*comando:' "$1" | head -1 \
    | sed -E 's/^[-*][[:space:]]*comando:[[:space:]]*//I'
}

echo "=== S0: as duas smokes do first-proof passam no check-spec ==="
for spec in specs/oracfit-smoke-normal.md specs/oracfit-smoke-unlock-plan.md; do
  if [ -f "$spec" ] && bash bin/check-spec.sh "$spec" >/dev/null 2>&1; then
    ok "check-spec $spec"
  else
    not "check-spec $spec (arquivo morto de novo? — D1)"
  fi
done

echo "=== S1..S6: as seis stories do pack passam no check-spec ==="
for spec in "$ROOT"/docs/go-live/specs/S*.md; do
  if bash bin/check-spec.sh "$spec" >/dev/null 2>&1; then
    ok "check-spec $(basename "$spec")"
  else
    not "check-spec $(basename "$spec")"
  fi
done

echo "=== S1..S6: os seis oráculos de 1 linha estão verdes no disco ==="
for spec in "$ROOT"/docs/go-live/specs/S*.md; do
  cmd="$(oracle_of "$spec")"
  if [ -n "$cmd" ] && eval "$cmd" >/dev/null 2>&1; then
    ok "oracle verde: $(basename "$spec")"
  else
    not "oracle vermelho: $(basename "$spec")"
  fi
done

echo "=== D1: a promessa de 2 minutos despacha verde com stub (workdir estranho) ==="
# Um workdir NOVO por dispatch: stub-proof que sobrou do run anterior faria o
# preflight reprovar "oracle already passes" — o gate de frescor (regra 39)
# está certo; o teste é que não pode mentir pra ele.
T=$(mktemp -d /tmp/golive-smoke.XXXXXX)
git -C "$T" init -q
git -C "$T" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
if ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
   ORACFIT_WORKDIR="$T" bash "$ROOT/bin/dispatch-mode.sh" \
   normal "$ROOT/specs/oracfit-smoke-normal.md" golive-smoke-normal \
   >/dev/null 2>&1 && grep -q stub_ok "$T/.dispatch/stub-proof"; then
  ok "stub dispatch normal em workdir estranho (oracle lê o disco)"
else
  not "stub dispatch normal falhou"
fi
rm -rf "$T"
T=$(mktemp -d /tmp/golive-tow.XXXXXX)
git -C "$T" init -q
git -C "$T" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
if ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
   ORACFIT_WORKDIR="$T" bash "$ROOT/bin/oracfit" run unlock_plan \
   "$ROOT/specs/oracfit-smoke-unlock-plan.md" golive-smoke-tow \
   >/dev/null 2>&1; then
  ok "stub dispatch multi-stage (unlock_plan) em workdir estranho"
else
  not "stub dispatch multi-stage falhou"
fi
rm -rf "$T"

echo "=== D2: aliases resolvem; god modes continuam no CLI ==="
# grep -q em pipeline fecha o pipe cedo (SIGPIPE) e pipefail viraria falso
# negativo — captura primeiro, casa depois.
modes_out="$(bin/oracfit modes)"
if [ "$(bin/oracfit alias paddle)" = "normal" ] \
   && [ "$(bin/oracfit alias tow)" = "unlock_plan" ] \
   && [ "$(bin/oracfit alias surfcheck)" = "ui_visual_qa" ]; then
  ok "paddle/tow/surfcheck resolvem para o id canônico"
else
  not "mapa de aliases divergiu"
fi
if printf '%s' "$modes_out" | grep -q midas && printf '%s' "$modes_out" | grep -q "surf aliases"; then
  ok "oracfit modes lista god modes E aliases (D7: CLI completo)"
else
  not "oracfit modes perdeu god modes ou aliases"
fi

echo "=== D3: os dois YAMLs da ficha validam e lintam no loader real ==="
for y in examples/glassy.yaml examples/outside_set.yaml; do
  if python3 bin/lib-oracfit-mode-loader.py validate "$y" >/dev/null 2>&1 \
     && python3 bin/lib-oracfit-mode-loader.py lint "$y" >/dev/null 2>&1; then
    ok "validate+lint $y"
  else
    not "validate+lint $y"
  fi
done

echo "=== D4: nenhuma linha '- comando:' de oráculo com crase (regra 46) ==="
if grep -qE '^[-*][[:space:]]*comando:.*`' specs/oracfit-smoke-*.md docs/go-live/specs/S*.md 2>/dev/null; then
  not "crase em linha de oráculo (regra 46)"
else
  ok "oráculos em texto cru"
fi

echo "=== D5: templates do mode share e da waitlist existem ==="
for t in .github/ISSUE_TEMPLATE/share-your-break.md .github/ISSUE_TEMPLATE/tokens-waitlist.md; do
  [ -f "$t" ] && ok "$t" || not "faltou $t"
done

echo "=== D6/D7: site honesto + tokens sem número + TUI no trio ==="
if bash tests/test-site-honesty.sh >/dev/null 2>&1; then
  ok "test-site-honesty"
else
  not "test-site-honesty"
fi
if grep -qi "waitlist" site/index.html && grep -q "Tokens at cost" site/llms.txt \
   && ! grep -qiE 'tokens for sale: [0-9]|price: \$?[0-9]' site/index.html site/llms.txt; then
  ok "seção de tokens presente e sem número inventado"
else
  not "seção de tokens ausente ou com número"
fi
if grep -q "surf aliases" bin/llms-surf-tui.sh; then
  ok "TUI no trio de surf"
else
  not "TUI fora do trio de surf"
fi

echo "=== D8: docs/go-live declarado nos dois gates ==="
if grep -q "docs/go-live" bin/oracfit-publish-cut.sh && grep -q "docs/go-live" bin/check-publico.sh; then
  ok "categoria privada declarada em publish-cut e check-publico"
else
  not "docs/go-live fora dos gates do corte"
fi
if bash bin/check-publico.sh --oficina >/dev/null 2>&1; then
  ok "check-publico --oficina limpo"
else
  not "check-publico --oficina"
fi

echo ""
echo "resultado: $pas pass, $falhas fail"
[ "$falhas" -eq 0 ]
