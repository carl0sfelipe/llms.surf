#!/bin/bash
# tests/test-oracle-freshness.sh — Gate de freshness do oráculo anti-veneno T4.
#
# O oráculo do content_factory confere `decision: APPROVED` num T4-content-validation.yaml.
# Bug de fit (veneno): um T4 velho de run anterior (ou de fixtures) fica no disco e o grep
# passa — run novo "aprovado" sem ter produzido nada.
#
# Gate: oracfit_gauntlet_freshness_gate exige AS DUAS condições:
#   1. mtime(T4) >= $ORACFIT_RUN_STARTED_AT   (arquivo foi escrito durante ESTE run)
#   2. campo `run_id:` dentro do T4 == $ORACFIT_RUN_ID   (é o T4 DESTE run)
#
# Sem ORACFIT_RUN_ID no env → bypass (modo standalone do content-factory fora do oracfit).
#
# DoD: o veneno real (fixture t4-poison-nintendo-switch-2.yaml, cópia byte a byte do
# T4 do incidente) é rejeitado e seu sha256+mtime são idênticos antes/depois do teste
# (diff vazio). Teste que toca o veneno é teste reprovado.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/oracfit-freshness.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# shellcheck source=../bin/lib-oracfit-gauntlet.sh
source "$REPO_ROOT/bin/lib-oracfit-gauntlet.sh"

PASS=0
FAIL=0
ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }

# mtime epoch portátil (BSD: stat -f %m · GNU: stat -c %Y). Sem isto o
# Linux deixava BEFORE/AFTER vazios e a checagem de integridade do veneno
# comparava vazio-com-vazio — sensor cego (achado sessão #9, CI HT1).
file_mtime() {
  local m
  m=$(stat -f '%m' "$1" 2>/dev/null) || m=$(stat -c '%Y' "$1" 2>/dev/null) || m=""
  printf '%s' "$m"
}
# timestamp touch portátil: GNU aceita -d @epoch; BSD usa -t com date -r epoch
touch_epoch() {  # touch_epoch <arquivo> <epoch>
  touch -d "@$2" "$1" 2>/dev/null || touch -t "$(date -r "$2" +%Y%m%d%H%M.%S 2>/dev/null)" "$1"
}
bad()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Veneno real — somente LEITURA, nunca modificar. Hash esperado travado no teste.
# Fixture no repo (não caminho de máquina): teste passa em qualquer clone/CI.
POISON="$REPO_ROOT/tests/fixtures/t4-poison-nintendo-switch-2.yaml"
POISON_SHA=47a7c3efc0730b9599ffdd3aedd2d62f4728499cc2e3b28ec9fdc565bb4b8ef2

# ---------------------------------------------------------------------------
# Pré: bypass quando ORACFIT_RUN_ID ausente (content-factory standalone).
# Sem run ativo, o gate NÃO bloqueia — retorna 0 mesmo para arquivo inexistente.
# ---------------------------------------------------------------------------
unset ORACFIT_RUN_ID ORACFIT_RUN_STARTED_AT
if oracfit_gauntlet_freshness_gate "$TMPDIR/qualquer.yaml" 2>/dev/null; then
  ok "bypass com RUN_ID ausente retorna 0 (não bloqueia CF standalone)"
else
  bad "bypass com RUN_ID ausente deveria passar (0) mas bloqueou"
fi

# ---------------------------------------------------------------------------
# Fixtures: cada cenário monta um T4 de mentira num subdir próprio.
# ---------------------------------------------------------------------------
RUN_ID="run-abc-123"
# run_started_at = agora em epoch segundos
RUN_STARTED_AT=$(date +%s)

make_t4() {
  local dir="$1"; local content="$2"
  mkdir -p "$dir"
  printf '%s\n' "$content" >"$dir/T4-content-validation.yaml"
  echo "$dir/T4-content-validation.yaml"
}

# --- Cenário 1: T4 fresco deste run → gate ACEITA (exit 0) ------------------
FRESH_DIR="$TMPDIR/fresh"
FRESH_T4=$(make_t4 "$FRESH_DIR" "approval_gate:
  decision: \"APPROVED\"
run_id: \"${RUN_ID}\"")
export ORACFIT_RUN_ID="$RUN_ID" ORACFIT_RUN_STARTED_AT="$RUN_STARTED_AT"
if oracfit_gauntlet_freshness_gate "$FRESH_T4"; then
  ok "T4 fresco deste run (run_id correto, mtime recente) aceito"
else
  bad "T4 fresco foi rejeitado (esperava exit 0)"
fi

# --- Cenário 2: T4 com run_id DE OUTRO run → gate REJEITA (veneno) ---------
OTHER_DIR="$TMPDIR/other-run"
OTHER_T4=$(make_t4 "$OTHER_DIR" "approval_gate:
  decision: \"APPROVED\"
run_id: \"run-diferente-999\"")
if oracfit_gauntlet_freshness_gate "$OTHER_T4" 2>/dev/null; then
  bad "T4 com run_id de outro run foi aceito (veneno!)"
else
  ok "T4 com run_id divergente rejeitado (exit≠0)"
fi

# --- Cenário 3: T4 sem campo run_id (pré-carimbo) → gate REJEITA -----------
NORID_DIR="$TMPDIR/no-runid"
NORID_T4=$(make_t4 "$NORID_DIR" "approval_gate:
  decision: \"APPROVED\"")
if oracfit_gauntlet_freshness_gate "$NORID_T4" 2>/dev/null; then
  bad "T4 sem run_id foi aceito (arquivo de run anterior = veneno)"
else
  ok "T4 sem run_id rejeitado (exit≠0)"
fi

# --- Cenário 4: T4 com run_id correto mas mtime VELHO → gate REJEITA -------
STALE_DIR="$TMPDIR/stale"
STALE_T4=$(make_t4 "$STALE_DIR" "approval_gate:
  decision: \"APPROVED\"
run_id: \"${RUN_ID}\"")
# Força mtime para 1 hora ANTES do run_started_at (veneno: arquivo pré-existente).
touch_epoch "$STALE_T4" "$((RUN_STARTED_AT - 3600))"
if oracfit_gauntlet_freshness_gate "$STALE_T4" 2>/dev/null; then
  bad "T4 com mtime anterior ao run foi aceito (stale = veneno)"
else
  ok "T4 com mtime < run_started_at rejeitado (exit≠0)"
fi

unset ORACFIT_RUN_ID ORACFIT_RUN_STARTED_AT

# ---------------------------------------------------------------------------
# Cenário 5 (O GATE do DoD): veneno REAL é rejeitado E fica intacto.
# O veneno é de 2026-08-02, sem run_id — exatamente o cenário de envenenamento.
# ---------------------------------------------------------------------------
if [ ! -f "$POISON" ]; then
  bad "veneno real não encontrado em $POISON — fixture do DoD sumiu"
else
  BEFORE_SHA=$(shasum -a 256 "$POISON" | awk '{print $1}')
  BEFORE_MTIME=$(file_mtime "$POISON")
  [ -n "$BEFORE_MTIME" ] || bad "file_mtime vazio no Linux/BSD — sensor de integridade cego"

  export ORACFIT_RUN_ID="run-teste-doD-2026" ORACFIT_RUN_STARTED_AT="$(date +%s)"
  if oracfit_gauntlet_freshness_gate "$POISON" 2>/dev/null; then
    bad "VENENO REAL foi aceito pelo gate — bug de fit NÃO corrigido"
  else
    ok "veneno real rejeitado pelo gate (decision APPROVED mas sem run_id e mtime velho)"
  fi
  unset ORACFIT_RUN_ID ORACFIT_RUN_STARTED_AT

  AFTER_SHA=$(shasum -a 256 "$POISON" | awk '{print $1}')
  AFTER_MTIME=$(file_mtime "$POISON")
  if [ "$BEFORE_SHA" != "$AFTER_SHA" ]; then
    bad "veneno teve sha alterado: $BEFORE_SHA → $AFTER_SHA (PROIBIDO tocar o veneno)"
  elif [ "$BEFORE_MTIME" != "$AFTER_MTIME" ]; then
    bad "veneno teve mtime alterado: $BEFORE_MTIME → $AFTER_MTIME (PROIBIDO)"
  else
    ok "veneno intacto após teste (sha+mtime idênticos)"
  fi
  # Sanity: confere contra o sha travado no topo do teste.
  if [ "$AFTER_SHA" != "$POISON_SHA" ]; then
    bad "sha do veneno ($AFTER_SHA) diverge do esperado ($POISON_SHA) — fixture mudou?"
  fi
fi

# ---------------------------------------------------------------------------
echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
