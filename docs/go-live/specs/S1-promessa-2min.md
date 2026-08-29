# S1 — a promessa de 2 minutos volta a ser verdade (P0, D1)

Prioridade ZERO do go-live (D1: nenhum tráfego sobe antes disto verde). O hero do
site promete "clone in 2 minutes — no API key" e o quickstart termina em
`bin/llms-surf start`; em HEAD esse comando despachava
`specs/oracfit-smoke-normal.md`, e `specs/` inteiro ficou fora do corte
público (regra 52). A promessa estava quebrada no produto público.

## O que fazer

Estado exigido (já implementado neste corte — esta spec é a ordem de trabalho
que originou o corte e o oráculo abaixo é o gate de regressão permanente):

1. `specs/oracfit-smoke-normal.md` existe e despacha verde com o stub runner,
   em workdir estranho (temp git, sem nada do checkout).
2. `specs/oracfit-smoke-unlock-plan.md` existe e despacha verde multi-stage
   (o mesmo contrato, para o passo de release do unlock_plan).
3. Os seis pontos que apontavam para a spec morta apontam para arquivo vivo:
   bin/oracfit (first-proof), bin/test-oracfit-tldr.sh,
   bin/release-gauntlet-verify.sh (2 specs), tests/test-gui-remote.sh,
   tests/test-protected-paths.sh.
4. dispatch-stages.sh cria o diretório de logs do workdir ANTES do preflight —
   mesmo invariante do dispatch-mode.sh, senão o fato `.dispatch` da smoke é
   reprovado pelo check-spec-facts no runtime multi-stage.

## Regras

Nao invente numero, prazo ou fonte alem dos listados. Nao use declare const
como workaround — o que o oráculo mede é disco, não declaração.

## Dados verificados

- Existe `specs/oracfit-smoke-normal.md` neste tree.
- Existe `specs/oracfit-smoke-unlock-plan.md` neste tree.
- Existe `bin/dispatch-stages.sh` neste tree.
- Existe `bin/test-oracfit-tldr.sh` neste tree.

## Verificação

Os dois testes que travavam na spec morta passam, e a smoke despacha:

VERIFICACAO: python3 bin/check-oracle.py specs/oracfit-smoke-normal.md /tmp --quiet && bash bin/test-oracfit-tldr.sh

## Oráculo

- comando: bash bin/check-spec.sh specs/oracfit-smoke-normal.md && bash bin/check-spec.sh specs/oracfit-smoke-unlock-plan.md && python3 bin/check-oracle.py specs/oracfit-smoke-normal.md /tmp --quiet
- exit esperado: 0 — as duas smokes passam no check-spec e o oráculo da
  smoke normal falha pelo motivo certo em workdir sem trabalho (estado correto
  antes de qualquer dispatch).

## Barra

bin/release-gauntlet-verify.sh — o gauntlet de release roda as duas smokes
como passos; é a referência nomeada desta story.
