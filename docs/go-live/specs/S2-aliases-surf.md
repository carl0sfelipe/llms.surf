# S2 — aliases de surf na UI (paddle / tow / surfcheck)

Decisão D2: os ids do tree ficam (`normal`, `unlock_plan`, `ui_visual_qa`
seguem canônicos em YAML, ledger, eventos e testes); a UI ganha apelidos de
surf. Alias é apelido — nunca um modo-irmão (colisão de id é incidente; ver
lint de shadow no loader).

## O que fazer

Estado exigido (implementado neste corte; oráculo abaixo é gate permanente):

1. `bin/oracfit` carrega o mapa ÚNICO `MODE_ALIASES`:
   paddle=normal, tow=unlock_plan, surfcheck=ui_visual_qa.
2. `oracfit alias` sem argumento imprime o mapa; com argumento resolve um
   nome (alias, id de modo existente em root ou workdir) e recusa desconhecido
   com exit 2.
3. `oracfit run <alias> …` resolve o alias ANTES de qualquer resolução de YAML
   — o runtime grava sempre o id canônico.
4. A TUI (`bin/llms-surf-tui.sh`) mostra o trio de surf como default (uma
   fonte só: `oracfit alias`), e os 17 god modes continuam acessíveis por id
   e listados no CLI (`oracfit modes`) — D7.

## Regras

Nao invente numero, prazo ou fonte alem dos listados. Nao use declare const
como workaround — resolução de alias é código bash rodando, não texto de help.

## Dados verificados

- Existe `bin/oracfit` neste tree.
- Existe `bin/llms-surf-tui.sh` neste tree.
- Existe `core/modes/normal.yaml` neste tree.
- Existe `core/modes/unlock_plan.yaml` neste tree.
- Existe `core/modes/ui_visual_qa.yaml` neste tree.

## Verificação

O mapa resolve e recusa o que não existe:

VERIFICACAO: test "$(bin/oracfit alias paddle)" = "normal" && ! bin/oracfit alias onda_fantasma

## Oráculo

- comando: test "$(bin/oracfit alias paddle)" = "normal" && test "$(bin/oracfit alias tow)" = "unlock_plan" && test "$(bin/oracfit alias surfcheck)" = "ui_visual_qa" && ! bin/oracfit alias onda_fantasma && grep -q "surf aliases" bin/llms-surf-tui.sh
- exit esperado: 0 — os três aliases resolvem para o id canônico, alias
  desconhecido recusa (exit não-zero), e a TUI anuncia o trio de surf.

## Barra

`bin/llms-surf` sem argumentos abre a TUI; opção 3 mostra o trio e diz onde
ficam os god modes. Referência nomeada: docs/go-live/DECISIONS-D1-D10.md (D2).
