---
id: 2026-08-13-ring-retest-nao-disparou-regex-sem-convencao-python
titulo: retest descorrelacionado do ring close não disparou — regex de teste novo não cobria a convenção python test_*.py
data: 2026-08-13
recorrivel: sim
regra: mecanismo aplicado — bin/oracfit-ring.sh (regex) + tests/test-ring-runner.sh (T14)
status: aberto
interage_com: "2026-08-13-ananke-god-mode-v4-teste-de-campo-3-aneis-mecanismos-pegaram-executor-e-runner"
---

# retest do ring close não disparou em test_fifoq.py

## Sintoma

Close do anel A-1 do teste de campo ananke (run `ananke-20260813-0011`)
com `test_fifoq.py` NOVO staged fechou com `oracle.runs=1` no evento do
ledger — o retest descorrelacionado (proteção contra flaky verde-2x do
autarca) deveria ter re-rodado o oráculo e não rodou. Nenhum erro, nenhum
aviso: o gate simplesmente não se considerou aplicável.

## Causa

Com EVIDÊNCIA: a regex de detecção de teste novo em `bin/oracfit-ring.sh`
era `(^|/)tests?/|(^|/)__tests__/|\.(test|spec)\.|_test\.|-test\.` — cobre
`tests/`, `x_test.py`, `x.test.ts`, mas NÃO `test_fifoq.py` (convenção
python padrão: prefixo `test_`). Verificado por `echo test_fifoq.py |
grep -E '<regex>'` → sem match, e pelo evento de close no ledger central
(`oracle.runs: 1`, `test_files: 1` — o próprio evento carrega a contradição).

## Correção aplicada

- `bin/oracfit-ring.sh`: alternância `(^|/)test_` adicionada à regex, com
  comentário citando este achado.
- `tests/test-ring-runner.sh` T14: anel fechando com `test_novo.py` staged
  exige `oracle.runs >= 2` no evento close (29 PASS após a correção).
- Re-medido no campo: close do A-2 (mesmo run) com teste novo → `oracle.runs: 2`.

## Pode acontecer de novo?

Sim, como CLASSE: gate condicional cujo predicado (regex, glob, threshold)
nunca foi exercitado com dado real da convenção do alvo falha em silêncio
como não-aplicável. A defesa que funcionou foi o ledger gravar `runs` e
`test_files` no mesmo evento — a contradição fica legível. Regra candidata
(no postmortem principal): todo gate condicional grava no ledger se
disparou ou não.
