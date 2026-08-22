---
id: 2026-08-22-ring-suite-falhava-com-tmp-de-10gb
titulo: T25g/T25h da suíte do ring falhavam em host com /tmp pequeno — gate de disco do open mascarava o que o teste mede
data: 2026-08-22
recorrivel: sim
regra: mecanismo aplicado — T25g/T25h zeram min_disk_gb pós-init (padrão new_target)
status: fechado
---

# T25g/T25h da suíte do ring falhavam em host com /tmp pequeno

## Sintoma

Na máquina <host-local> (Arch, /tmp em tmpfs de 9,7G), `tests/test-ring-runner.sh`
reportava 2 FAIL crônicos:

    FAIL: open do dono vivo recusado (rc=1) — is_ancestor regrediu?
    FAIL: token real não deu posse (rc=1)

A mensagem de diagnóstico do próprio teste ("is_ancestor regrediu?") apontava
para a hipótese errada: a recusa vinha do PREFLIGHT DE DISCO do `ring open`
("disco livre 9GB < mínimo 10GB"), não da verificação de posse.

## Causa

`new_target` (helper da suíte) zera `min_disk_gb` no state.json após o init —
mas T25g e T25h criam o alvo com `mk_bare_repo` + init direto e NUNCA zeram o
gate. Como a suíte roda em `mktemp -d /tmp/...`, todo host cujo /tmp (ou
TMPDIR) tenha menos de 10G livres — tmpfs de 10G ou menos é default comum em
Linux — faz o `open` recusar por disco e os dois testes de posse falharem com
uma mensagem que incrimina o mecanismo errado. O gate em si está correto
(ENOSPC real no meio do anel: pythia-enospc); o defeito era o acoplamento do
TESTE ao disco do host.

## Correção aplicada (2026-08-22)

T25g e T25h agora zeram `min_disk_gb` e commitam o state logo após o init —
o mesmo padrão que `new_target` já usava. Suíte: 114 PASS / 0 FAIL na
<host-local>. Código: tests/test-ring-runner.sh (T25g/T25h, "test: disk gate
off"). A lição geral — teste que depende de recurso do host (disco, rede,
portas) zera/moca o gate correspondente e diz o que está medindo DE FATO —
já era o padrão do helper; faltava aplicar nos dois testes que não o usavam.
