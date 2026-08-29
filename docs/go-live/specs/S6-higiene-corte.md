# S6 — docs/go-live é ordem de trabalho, não produto (higiene do corte)

Decisão D8: este diretório (decisões, specs de anel, copy de anúncio) é
ferramenta de trabalho do go-live. Não entra no próximo corte público. A
categoria fora do manifesto é a que vaza (incidente 2026-08-13) — então a
categoria entra DECLARADA nos dois gates, antes de valer.

## O que fazer

Estado exigido (implementado; oráculo abaixo é gate permanente):

1. `bin/oracfit-publish-cut.sh`: `docs/go-live` em PRIVATE_DIRS — o apply
   recusa corte contaminado se o diretório existir no destino; o report o
   lista como "PRESENTE NO PUBLICO" quando for o caso.
2. `bin/check-publico.sh`: `docs/go-live` em PRIVADO (em sincronia com o
   publish-cut — os dois arrays são o mesmo contrato em dois gates).

## Regras

Nao invente numero, prazo ou fonte alem dos listados. Nao use declare const
como workaround — categoria privada é a que está no array dos gates, não a
que está num comentário de README.

## Dados verificados

- Existe `bin/oracfit-publish-cut.sh` neste tree.
- Existe `bin/check-publico.sh` neste tree.
- Existe `docs/go-live/DECISIONS-D1-D10.md` neste tree.

## Verificação

O gate da oficina roda limpo com a categoria nova declarada:

VERIFICACAO: bash bin/check-publico.sh --oficina && grep -q docs/go-live bin/oracfit-publish-cut.sh

## Oráculo

- comando: grep -q "docs/go-live" bin/oracfit-publish-cut.sh && grep -q "docs/go-live" bin/check-publico.sh && bash bin/check-publico.sh --oficina
- exit esperado: 0 — os dois gates declaram a categoria e o scan da oficina
  segue limpo.

## Barra

docs/go-live/DECISIONS-D1-D10.md (D8) e o comentário no array PRIVATE_DIRS —
o porquê (categoria fora do manifesto é a que vaza) está registrado junto do
código que impõe.
