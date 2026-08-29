#!/usr/bin/env bash
# tests/test-protected-paths.sh — guard de zonas protegidas do dispatch-mode
# (v3.5, triagem fábrica-agentic §A1 — fase "Core Hijacking" do ClawWorm).
#
# TESTE 1: stub escreve em caminho protegido (.oracfit-protected: core/*)
#          ⇒ evento protected_paths_alert citando o arquivo.
# TESTE 2: stub escreve fora da zona protegida ⇒ NENHUM alerta.
# TESTE 3: sujeira pré-existente em zona protegida NÃO gera alerta
#          (o guard mede o que mudou DURANTE o run, não o estado do mundo).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$REPO_ROOT/tests/fixtures/oracfit-smoke-normal.md"
pas=0
falhas=0

roda_guard() {  # roda_guard <workdir> <stub_write> <task>
  local wd="$1" write="$2" task="$3"
  # Spec local = smoke com "## Dados verificados" REESCRITO: os fatos da smoke
  # citam caminhos do CHECKOUT e o preflight (check-spec-facts, regra 37) os
  # mede contra o WORKDIR — num tmp eles falham e o run nem começa. Remover a
  # seção também não dá: check-spec exige o bloco (cláusula anti-invenção).
  # Fato substituto: .oracfit-protected, que novo_workdir cria no próprio tmp.
  local spec_local="$wd/spec-guard.md"
  awk '/^## Dados verificados/{
         print; print "";
         print "- Existe `.oracfit-protected` no workdir (lista de zonas do teste).";
         skip=1; next
       }
       /^## /{skip=0} !skip' "$SPEC" >"$spec_local"
  ORACFIT_ROOT="$REPO_ROOT" \
  DISPATCH_RUNNER="$REPO_ROOT/adapters/stub/runner.sh" \
  ORACFIT_WORKDIR="$wd" \
  ORACFIT_STUB_WRITE="$write" \
    bash "$REPO_ROOT/bin/dispatch-mode.sh" normal "$spec_local" "$task" \
    >"$wd/.test-stdout" 2>"$wd/.test-stderr"
  # anti-vácuo: sem run_finished, qualquer asserção "não houve alerta" é nula
  if ! grep -q '"type": *"run_finished"' "$wd/.dispatch/logs/events.jsonl" 2>/dev/null; then
    echo "FAIL(setup): run $task não chegou a run_finished — teste inválido"
    echo "--- stderr:"; tail -5 "$wd/.test-stderr" 2>/dev/null
    return 1
  fi
}

novo_workdir() {  # novo_workdir — git repo limpo com .oracfit-protected: core/*
  local wd
  wd=$(mktemp -d "/tmp/oracfit-test-protected.XXXXXX")
  git -C "$wd" init -q
  git -C "$wd" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf 'core/*\n' >"$wd/.oracfit-protected"
  echo "$wd"
}

# ═══ TESTE 1: escrita em zona protegida gera alerta ═══
echo "=== TESTE 1: escrita em core/ gera protected_paths_alert ==="
WD1=$(novo_workdir)
trap 'rm -rf "$WD1" "${WD2:-}" "${WD3:-}"' EXIT
if roda_guard "$WD1" "core/hacked.txt" guard-t1; then
  EV1="$WD1/.dispatch/logs/events.jsonl"
  if grep -q '"type": *"protected_paths_alert"' "$EV1" 2>/dev/null \
     && grep -q 'core/hacked.txt' "$EV1" \
     && grep -q 'ZONA PROTEGIDA' "$WD1/.test-stderr"; then
    echo "PASS: alerta emitido (evento + stderr) citando core/hacked.txt"
    pas=$((pas + 1))
  else
    echo "FAIL: sem protected_paths_alert p/ core/hacked.txt"
    echo "--- events:"; tail -5 "$EV1" 2>/dev/null
    echo "--- stderr:"; tail -5 "$WD1/.test-stderr" 2>/dev/null
    falhas=$((falhas + 1))
  fi
else
  falhas=$((falhas + 1))
fi

# ═══ TESTE 2: escrita fora da zona não gera alerta ═══
echo ""
echo "=== TESTE 2: escrita em src/ NÃO gera alerta ==="
WD2=$(novo_workdir)
if roda_guard "$WD2" "src/ok.txt" guard-t2; then
  EV2="$WD2/.dispatch/logs/events.jsonl"
  if grep -q '"type": *"protected_paths_alert"' "$EV2" 2>/dev/null; then
    echo "FAIL: alerta indevido para escrita fora da zona protegida"
    falhas=$((falhas + 1))
  else
    echo "PASS: nenhum alerta para src/ok.txt"
    pas=$((pas + 1))
  fi
else
  falhas=$((falhas + 1))
fi

# ═══ TESTE 3: sujeira pré-existente não vira alerta ═══
echo ""
echo "=== TESTE 3: mudança pré-run em core/ não é atribuída ao modelo ==="
WD3=$(novo_workdir)
mkdir -p "$WD3/core"
echo "sujeira anterior ao run" >"$WD3/core/preexistente.txt"
if roda_guard "$WD3" "src/ok.txt" guard-t3; then
  EV3="$WD3/.dispatch/logs/events.jsonl"
  if grep -q '"type": *"protected_paths_alert"' "$EV3" 2>/dev/null; then
    echo "FAIL: sujeira pré-run em core/ gerou alerta (snapshot não filtrou)"
    falhas=$((falhas + 1))
  else
    echo "PASS: guard mede só o delta do run — pré-existente ignorado"
    pas=$((pas + 1))
  fi
else
  falhas=$((falhas + 1))
fi

echo ""
echo "resultado: $pas pass, $falhas fail"
[ "$falhas" -eq 0 ]
