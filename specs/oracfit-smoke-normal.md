# spec: oracfit-smoke-normal — first-proof (a promessa de 2 minutos)

Smoke mecânica do laço spec → modelo → artefato → oráculo. É o run que o
comando de start despacha (bin/llms-surf start, oracfit start, oracfit
first-proof — todos caem aqui). Não mede capacidade de modelo: mede o CAMINHO.
A spec chega, o runner roda, um artefato nasce no disco e o oráculo lê o
disco — nada é aprovado na palavra do modelo.

Esta spec viaja para workdir estranho (teste de GUI, workdir temporário,
checkout recém-clonado). Por isso o bloco de fatos abaixo é deliberadamente
mínimo: só afirma o que TODO workdir de dispatch tem.

## Tarefa

Crie o arquivo `.dispatch/stub-proof` com exatamente 3 linhas:

    stub_ok
    model_id=<o identificador do modelo com que você foi lançado>
    spec=oracfit-smoke-normal.md

É tudo. Nenhuma outra escrita é esperada. O artefato é a prova; a linha
model_id= existe para depuração, não para avaliação.

## Regras

Nao invente outro caminho, numero, prazo ou fato alem do listado abaixo.
Nao use declare const como workaround de checagem de tipo — aqui não roda
TypeScript nenhum; a cláusula é o princípio: artefato inexistente não se
declara, se cria.

## Dados verificados

- Existe `.dispatch` no workdir — o dispatcher cria o diretório de logs antes
  de qualquer preflight, em todo run, em qualquer workdir.

## Oráculo

- comando: test -f .dispatch/stub-proof && grep -q stub_ok .dispatch/stub-proof
- exit esperado: 0 = o laço inteiro foi provado (spec → runner → artefato no
  disco → oráculo lendo o disco). Antes do run, exit 1 sem stderr é o estado
  CORRETO: o oráculo falha porque o trabalho não existe ainda, não porque o
  comando quebrou (exit 2 ou stderr de arquivo ausente seria oráculo quebrado
  — por isso o test -f vem antes do grep).

## Verificação

O oráculo precisa falhar pelo motivo certo em workdir vazio, antes de
despachar qualquer modelo (preflight roda exatamente isto, regra 39):

VERIFICACAO: python3 bin/check-oracle.py specs/oracfit-smoke-normal.md "$(mktemp -d)" --quiet

Resultado esperado: "oráculo falha (exit 1) e falha pelo motivo certo", exit 0.

## Barra

Referência nomeada: adapters/stub/runner.sh grava o MESMO artefato que o
modelo real deve gravar — stub e modelo real são julgados pelo mesmo oráculo.
E bin/test-oracfit-tldr.sh reproduz a promessa de 2 minutos inteira (start +
painel) em 3 comandos, sem rede e sem chave de API. Passar na barra é o
TL;DR do README se reproduzir daqui.
