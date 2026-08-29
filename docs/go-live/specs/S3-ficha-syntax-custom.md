# S3 — ficha da syntax custom + dois YAMLs que provam o loader

Decisão D3: syntax custom de modo é um SUBCONJUNTO da gramática do loader que
já existe — zero mudança de schema, zero parser novo. A ficha
(`docs/go-live/CUSTOM-MODE-CARD.md`) documenta o subconjunto e os dois YAMLs
de exemplo provam, contra o loader REAL deste tree, que o caminho inteiro
valida e linta.

## O que fazer

Estado exigido (implementado; oráculo abaixo é gate permanente):

1. A ficha existe e ensina o subconjunto: id/version/name/description/stages/
   on_fail, stage role=run com model_ref por tier, `oracle: true`,
   max_attempts, rate_limit_s.
2. Os dois exemplos validam E lintam com o loader real:
   `examples/glassy.yaml` (mínimo viável, tier cheap) e
   `examples/outside_set.yaml` (tier mid + rate_limit_s).
3. O oráculo da task vive na SPEC (seção `## Oráculo`, comando cru sem
   crase — regra 46), não no YAML. `oracle: true` só declara que a spec será
   julgada por comando no disco.
4. A primeira versão dos exemplos foi REPROVADA pelo lint ("ledger" na
   description, classe ring sem mecanismo) — o gate funciona; a ficha documenta
   o pedágio para o próximo autor de modo.

## Regras

Nao invente numero, prazo ou fonte alem dos listados. Nao use declare const
como workaround — YAML que valida no papel mas não no loader é fantasma.

## Dados verificados

- Existe `docs/go-live/CUSTOM-MODE-CARD.md` neste tree.
- Existe `examples/glassy.yaml` neste tree.
- Existe `examples/outside_set.yaml` neste tree.
- Existe `bin/lib-oracfit-mode-loader.py` neste tree.

## Verificação

O mesmo binário do `run` julga os exemplos (validate + lint):

VERIFICACAO: python3 bin/lib-oracfit-mode-loader.py validate examples/outside_set.yaml

## Oráculo

- comando: python3 bin/lib-oracfit-mode-loader.py validate examples/glassy.yaml && python3 bin/lib-oracfit-mode-loader.py lint examples/glassy.yaml && python3 bin/lib-oracfit-mode-loader.py validate examples/outside_set.yaml && python3 bin/lib-oracfit-mode-loader.py lint examples/outside_set.yaml
- exit esperado: 0 — os dois YAMLs passam no schema E no lint de claims do
  loader real (não de um validador paralelo).

## Barra

docs/go-live/CUSTOM-MODE-CARD.md — a ficha é a referência nomeada; o ciclo
completo (init → validate → lint → run → share) está lá, com o caminho de
instalação de modo de terceiro (`mode add`) na S4.
