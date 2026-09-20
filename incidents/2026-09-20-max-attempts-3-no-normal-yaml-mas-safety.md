---
id: 2026-09-20-max-attempts-3-no-normal-yaml-mas-safety
titulo: max attempts 3 no normal yaml mas safety ceiling 5 manda
data: 2026-09-20
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): precedência documentada no próprio core/modes/normal.yaml (comentário no bloco gauntlet) e em docs/go-live/CUSTOM-MODE-CARD.md (nota junto ao campo safety_ceiling)
status: corrigido
---

# max attempts 3 no normal yaml mas safety ceiling 5 manda

Dogfood real da v4.1.0 (2026-09-20), modo normal.

## Sintoma

`core/modes/normal.yaml` declara `max_attempts: 3` no topo, mas o run dogfood
fez 5 tentativas. Nenhum dos lugares onde o operador lê a gramática de modos
(`normal.yaml`, `docs/go-live/CUSTOM-MODE-CARD.md`) declara a precedência —
quem lê "3" planeja 3, e o framework roda 5.

## Causa

Comportamento CORRETO, documentação errada. Resolução em
`bin/lib-oracfit-gauntlet.sh:57-71`
(`oracfit_gauntlet_resolve_max_attempts`): com `until_approved: true` e
`safety_ceiling` definido (normal.yaml: `gauntlet.until_approved: true`,
`safety_ceiling: 5`), o teto efetivo é o MAIOR dos dois — 5. `max_attempts: 3`
só governa sem o bloco gauntlet. Call site: `bin/dispatch-mode.sh:219-221` →
loop `while [ "$attempt" -lt "$max_attempts" ]` (`:323`). A precedência não
estava escrita em nenhum lugar que o operador lê (yaml, SKILL, mode card).

## Correção aplicada

1. `core/modes/normal.yaml` — comentário no bloco gauntlet: com
   `until_approved: true`, `safety_ceiling` prevalece sobre `max_attempts`
   (teto efetivo = max dos dois).
2. `docs/go-live/CUSTOM-MODE-CARD.md` — nota de precedência junto ao campo
   `safety_ceiling` na gramática de exemplo.

Nota de verificação: a alegação do dogfood de que o SKILL.md documentava
"≤3 attempts" não se confirmou na árvore (nem no HEAD, nem na tag v4.1.0 —
grep por "attempt" em SKILL.md/README não acha a frase); o que existe de
fato é a contradição entre o `max_attempts: 3` do yaml e o teto efetivo 5,
indocumentada nos dois lugares acima. Sem mudança de código: a resolução em
`oracfit_gauntlet_resolve_max_attempts` está certa; o que faltava era a
verdade estar onde se lê.

## Pode acontecer de novo?

Em modos novos, se o autor copiar o yaml sem ler o comentário — por isso o
comentário fica colado no próprio campo, não num doc distante. Outros modos
já declaram os dois campos (aion 5, demiurgo 4, glm_smart 4, content_factory
4, deepseek_direct_flash 5) e agora herdam a explicação do card.
