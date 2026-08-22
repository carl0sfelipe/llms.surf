---
id: "" # Identificador único do artefato
schema: 1 # Versão do schema; ainda NÃO está congelado
status: draft # Estados possíveis: draft, ready, in-progress, in-review, done, blocked
owner: "" # Responsável atual pelo trabalho
modelo: "" # Modelo de IA utilizado neste artefato
tentativas: 0 # Número de tentativas de execução
bloqueio: false # Indica se o artefato está bloqueado para edição
evidencia: "" # Caminho ou referência para a evidência do trabalho
---

## Objetivo

Descreva o objetivo deste artefato.

## Barra

Referência concreta, fetchable e comparável do que “bom” significa
([gauntlet-loop](https://github.com/robonuggets/gauntlet-loop)). Sem barra
vaga (“bonito”, “profissional”). Preferir: URL live, arquivo canônico no
repo, suite de teste, ou screenshot de referência.

- nome: `<produto/página/repo/teste nomeado>`
- como fetchar: `<url | path | comando que materializa a referência>`
- como comparar: `<oracle/teste | A/B visual | checklist>`

## Passos

- Passo 1
- Passo 2

## Oráculo

Comando + exit esperado que prova que o trabalho foi feito — não que o modelo
rodou, que o resultado é verdade. Sem isto, `bin/ledger-finalize.sh` só sabe
dizer se o log não ficou vazio, e "log não vazio" já registrou como "ok" um
dispatch que alucinou e não fez nada (incident: exit_status fabricado).

O oráculo é a Metric hard do gauntlet. Em falha, `dispatch-mode` /
`dispatch-escalate` injetam `## GAUNTLET FEEDBACK` (biggest_gap) no próximo
attempt até exit 0 (ou safety_ceiling).

- comando: `<comando shell exato, com cd embutido se precisar de outro diretório>`
- exit esperado: `<inteiro, default 0 se omitido>`

Exemplo:

- comando: `cd <workdir-alvo> && bash scripts/check-dup-kit.sh | tail -1 | grep -q '^total=0$'`
- exit esperado: `0`

## Resultado

Descreva o resultado esperado.