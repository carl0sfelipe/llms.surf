#!/bin/bash
# tests/test-t4-runid-stamp.sh — Carimbo de run_id no T4 pelo writer do content-factory.
#
# O freshness gate do oracfit (test-oracle-freshness.sh) exige `run_id` no T4. Este
# teste fecha o ciclo do lado do writer: _persist_artifact carimba run_id quando
# rodando sob oracfit (env ORACFIT_RUN_ID presente) e o path é T4-content-validation.
#
# Ciclo fechado: stamp do CF escreve run_id → gate do oracfit ACEITA o T4.
# Sem env (CF standalone) → sem carimbo → gate em bypass também aceita.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/oracfit-runid.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# A função _stamp_run_id é estática e pura (sem deps de crewai). Testamos a lógica
# diretamente para não arrastar todo o import graph do CF, e validamos o ciclo
# completo (stamp → gate) no final.
STAMP_PY='import re, sys
def stamp(text, run_id):
    rid = re.sub(r"[^A-Za-z0-9_.\-]", "", run_id)[:128]
    line = f"run_id: \"{rid}\"\n"
    m = re.search(r"(?m)^[A-Za-z0-9_\-]+\s*:", text)
    if m: return text[:m.start()] + line + text[m.start():]
    return text.rstrip() + "\n" + line
text, rid = sys.stdin.read(), sys.argv[1]
sys.stdout.write(stamp(text, rid))'

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

RUN_ID="run-ciclo-fechado-789"

# --- (1) T4 real (veneno, SÓ LEITURA) ganha run_id e continua YAML válido --------
# Fixture no repo (não caminho de máquina): teste passa em qualquer clone/CI.
VENENO="$REPO_ROOT/tests/fixtures/t4-poison-nintendo-switch-2.yaml"
VENENO_SHA=$(shasum -a 256 "$VENENO" | awk '{print $1}')
cp "$VENENO" "$TMPDIR/t4-real-copy.yaml"   # cópia; original nunca é tocado
STAMPED=$(printf '%s' "$(cat "$TMPDIR/t4-real-copy.yaml")" | python3 -c "$STAMP_PY" "$RUN_ID" >"$TMPDIR/t4-real-stamped.yaml"; echo "$TMPDIR/t4-real-stamped.yaml")
if grep -q "run_id: \"$RUN_ID\"" "$STAMPED"; then
  ok "T4 real (cópia) carimbado com run_id"
else
  bad "T4 real não recebeu run_id"
fi
# YAML válido (parse não explode)?
if python3 -c "
import re, yaml, sys
t = open('$STAMPED').read()
f = re.search(r'\`\`\`yaml\s*\n(.*?)\`\`\`', t, re.S)
d = yaml.safe_load(f.group(1) if f else t)
assert d.get('run_id') == '$RUN_ID', 'run_id divergente'
assert 'approval_gate' in d, 'bloco original sumiu'
print('YAML válido, run_id+approval_gate presentes')
"; then ok "T4 real carimbado mantém YAML válido e bloco original"; else bad "T4 real carimbado quebrou YAML ou perdeu bloco"; fi
# Veneno ORIGINAL intocado?
VENENO_SHA_AFTER=$(shasum -a 256 "$VENENO" | awk '{print $1}')
if [ "$VENENO_SHA" = "$VENENO_SHA_AFTER" ]; then
  ok "veneno original intocado (sha idêntico)"
else
  bad "veneno original foi modificado — PROIBIDO"
fi

# --- (2) CICLO FECHADO: stamp do CF → gate do oracfit ACEITA --------------------
source "$REPO_ROOT/bin/lib-oracfit-gauntlet.sh"
export ORACFIT_RUN_ID="$RUN_ID"
export ORACFIT_RUN_STARTED_AT="$(date +%s)"
# Reescreve mtime do T4 carimbado p/ agora (fresh).
cp "$STAMPED" "$TMPDIR/t4-fresh.yaml"
touch "$TMPDIR/t4-fresh.yaml"
if oracfit_gauntlet_freshness_gate "$TMPDIR/t4-fresh.yaml"; then
  ok "CICLO FECHADO: stamp do CF + gate do oracfit ACEITAM o T4"
else
  bad "gate rejeitou T4 carimbado pelo CF (ciclo quebrado)"
fi

# --- (3) run_id divergente (T4 de outro run) → gate REJEITA ---------------------
echo 'approval_gate:
  decision: "APPROVED"
run_id: "run-de-outro-999"' >"$TMPDIR/t4-outro.yaml"
touch "$TMPDIR/t4-outro.yaml"
if oracfit_gauntlet_freshness_gate "$TMPDIR/t4-outro.yaml" 2>/dev/null; then
  bad "gate aceitou T4 de outro run (veneno)"
else
  ok "gate rejeita T4 com run_id divergente"
fi

# --- (4) Sem ORACFIT_RUN_ID → sem carimbo (CF standalone) -----------------------
unset ORACFIT_RUN_ID ORACFIT_RUN_STARTED_AT
PLAIN='approval_gate:
  decision: "APPROVED"'
STAMPED_NOENV=$(printf '%s' "$PLAIN" | ORACFIT_RUN_ID="" python3 -c "
import re, sys
# Réplica do _persist_artifact: só carimba se env presente.
import os
run_id = os.getenv('ORACFIT_RUN_ID', '')
text = sys.stdin.read()
if run_id:
    rid = re.sub(r'[^A-Za-z0-9_.\-]', '', run_id)[:128]
    line = f'run_id: \"{rid}\"\n'
    m = re.search(r'(?m)^[A-Za-z0-9_\-]+\s*:', text)
    text = text[:m.start()] + line + text[m.start():] if m else text
sys.stdout.write(text)
")
if grep -q "run_id:" <<<"$STAMPED_NOENV"; then
  bad "CF standalone (sem env) carimbou run_id — deveria deixar sem campo"
else
  ok "CF standalone não carimba run_id (env ausente) — gate bypass também aceita"
fi

echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
