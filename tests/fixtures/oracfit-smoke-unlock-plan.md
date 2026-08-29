# spec: oracfit-smoke-unlock-plan — first-proof multi-stage (tow / unlock_plan)

Smoke mecânica do runtime multi-stage (P5): unlock → plan → run, cada stage
com seu modelo e seus artifacts, on_fail halt. Mesmo contrato da smoke de
modo normal (oracfit-smoke-normal.md): não mede capacidade, mede o CAMINHO —
spec chega, os stages rodam na ordem, um artefato nasce no disco, o oráculo
lê o disco.

Esta spec viaja para workdir estranho. Bloco de fatos deliberadamente mínimo:
só afirma o que TODO workdir de dispatch tem.

## Tarefa

Em CADA stage em que você rodar, garanta que o arquivo `.dispatch/stub-proof`
exista no workdir com exatamente 3 linhas:

    stub_ok
    model_id=<o identificador do modelo com que você foi lançado>
    spec=oracfit-smoke-unlock-plan.md

O stage unlock caro prova o caminho; o stage plan faz o plano; o stage run
barato fecha o run. O oráculo só olha o disco no fim — plano bonito sem
artefato é reprovação.

## Regras

Nao invente outro caminho, numero, prazo ou fato alem do listado abaixo.
Nao use declare const como workaround de checagem — artefato inexistente não
se declara, se cria.

## Dados verificados

- Existe `.dispatch` no workdir — o dispatcher cria o diretório de logs antes
  de qualquer preflight, em todo run, em qualquer workdir.

## Oráculo

- comando: test -f .dispatch/stub-proof && grep -q stub_ok .dispatch/stub-proof
- exit esperado: 0 = os stages rodaram e o artefato está no disco. Antes do
  run, exit 1 sem stderr é o estado CORRETO (trabalho ainda não existe); o
  test -f antes do grep garante que arquivo ausente é falha limpa, nunca
  oráculo quebrado.

## Verificação

O oráculo precisa falhar pelo motivo certo em workdir vazio, antes de
despachar (regra 39):

VERIFICACAO: python3 bin/check-oracle.py tests/fixtures/oracfit-smoke-unlock-plan.md "$(mktemp -d)" --quiet

Resultado esperado: "oráculo falha (exit 1) e falha pelo motivo certo", exit 0.

## Barra

Referência nomeada: bin/dispatch-stages.sh (o runtime multi-stage que executa
unlock_plan) e bin/release-gauntlet-verify.sh, que roda esta smoke como passo
de verificação de release. Passar na barra é o gauntlet de release reproduzir
aqui dentro, com stub, sem rede e sem chave de API.
