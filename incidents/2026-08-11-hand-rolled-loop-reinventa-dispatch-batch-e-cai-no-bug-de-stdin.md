---
id: 2026-08-11-hand-rolled-loop-reinventa-dispatch-batch-e-cai-no-bug-de-stdin
titulo: nada aponta pra bin/dispatch-batch.sh, orquestrador reinventa loop e cai no classico bug de stdin compartilhado
data: 2026-08-11
recorrivel: sim
regra: nao-catalogada (candidata: documentacao/descoberta de ferramenta existente)
status: aberto
interage_com: "2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback, 2026-08-11-check-oracle-trata-arquivo-de-saida-inexistente-como-quebrado"
---

# Nada aponta pra `bin/dispatch-batch.sh` — orquestrador reinventa loop e cai no clássico bug de stdin compartilhado

## Sintoma

Precisava rodar 21 despachos `deepseek_direct_flash` (extração de fornecedores
de PDF/XLSX/ODS pra JSON). Não conhecia `bin/dispatch-batch.sh` — escrevi um
`while IFS=$'\t' read -r spec task out; do bin/oracfit run ...; done < manifest.tsv`
na mão.

Resultado: rodou o item 1, o subprocesso do runner (`opencode run` via
`DISPATCH_RUNNER`) recebeu `Terminated (SIGTERM)` aos ~50s, e o loop inteiro
encerrou depois de **1 único item** de 21 — sem erro visível, só
`TODOS OS DESPACHOS TERMINARAM` prematuro. Nenhum dos outros 20 chegou a
disparar.

## Causa

`while read ... done < arquivo` mantém o arquivo aberto no **stdin (fd 0)**
durante todo o corpo do loop. Qualquer comando de dentro do corpo que também
leia de stdin (interativo, prompt de confirmação, o que for) consome o
descritor compartilhado — o `read` da próxima iteração bate em EOF cedo, e o
loop morre silenciosamente sem erro de sintaxe. Padrão de bug conhecido de
bash, não específico do oracfit — mas o **efeito prático dentro do oracfit**
foi achar que só 1/21 specs tinha erro, quando na verdade o mecanismo de
loop é que estava quebrado.

## O gap real: a ferramenta certa já existe e ninguém apontou pra ela

`bin/dispatch-batch.sh` já resolve exatamente esse caso — e evita esse bug
por construção: primeiro faz `while read ... done < "$BATCH_FILE"` **só pra
popular arrays** (`SPECS`, `TASKS`, `DIRS`), fecha esse loop, e SÓ DEPOIS
itera com `for i in $(seq ...)` — que não compete por stdin com nada.
Estrutura correta, já pronta, com bônus que meu script não tinha: gate de
`check-spec.sh` + `check-oracle.py` em **todas** as specs antes de gastar
um único token de modelo, rollback via checkpoint, formato `spec|task|workdir`
por linha.

Nada no `bin/oracfit --help`, nem no fluxo natural de quem já usa
`bin/oracfit run <mode> <spec> <task>` pra 1 item, aponta "pra mais de 1 item,
use `dispatch-batch.sh`". `cmd_run` do `bin/oracfit` (usado pra 1 despacho)
não menciona a existência do modo batch em lugar nenhum da mensagem de help
nem do erro. Descobri o script batch só DEPOIS de já ter escrito, debugado e
corrigido meu próprio loop manual.

## Pode acontecer de novo?

Sim — é o caminho natural pra quem usa `oracfit run` pra 1 spec e depois
precisa de N specs: escrever um `for`/`while` em volta é o instinto óbvio, e
sem apontamento pro `dispatch-batch.sh`, cai na mesma reinvenção. Quem
escreve certo (array + `for`) tem sorte; quem escreve o padrão mais comum
(`while read < file`) tromba no bug de stdin sem aviso — e o sintoma (loop
morre depois de 1 item, sem erro de sintaxe) não aponta óbvio pra causa.

## Sugestão de correção (não aplicada — é doc, não código)

`bin/oracfit --help` (seção `run`) ganhar uma linha: "mais de 1 spec? use
`bin/dispatch-batch.sh <batch_file>` (formato `spec|task|workdir` por linha)
— evita reinventar loop e ganha gate + rollback de graça." Não editei o help
agora porque não tenho certeza se `oracfit`/`dispatch-batch.sh` são a mesma
superfície de comando pretendida pro usuário final ou se `dispatch-batch.sh`
é considerado terreno legado (nome ainda `dispatch-*`, não `oracfit *`) —
fica pra quem mantém o core decidir se promove o comando ou deprecia a
duplicidade.
