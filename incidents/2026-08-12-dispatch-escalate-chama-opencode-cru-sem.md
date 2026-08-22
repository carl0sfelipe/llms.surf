---
id: 2026-08-12-dispatch-escalate-chama-opencode-cru-sem
titulo: dispatch-escalate chama opencode cru sem -- e com tiers default mortos
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo aplicado (classe C, 2026-08-12 v3.5): dispatch_model usa DISPATCH_RUNNER quando ativo (runner resolve id pelo registry, poe o `--` e reporta rate limit ao usage-hub); caminho cru ganhou o `--` que faltava; tiers default trocados por ids vivos verificados em `opencode models` (opencode/deepseek-v4-flash-free, opencode/deepseek-v4-pro); critic ganhou teto (with-timeout 300s) e model ref vivo configuravel (DISPATCH_CRITIC_MODEL); tests/test-model-override.sh atualizado
status: promovido
---

# dispatch-escalate chama opencode cru sem -- e com tiers default mortos

## Sintoma

Run scentmatch-fotos-cdn (2026-08-12 ~05:44): dois dispatch-escalate seguidos
BLOQUEADOS com 6 tentativas de 0-1s cada. Logs de TODAS as tentativas
(.dispatch/logs/scentmatch-fotos-cdn-*-N.log, 3053 bytes identicos) continham
apenas o HELP do yargs do opencode — nenhum erro, nenhuma resposta de modelo.
Oraculo reportou oracle_exit=1 e o gauntlet escalou tier achando que o modelo
estava travado.

## Causa

DOIS defeitos independentes no mesmo script, ambos com evidencia:

1. Tiers default mortos. bin/dispatch-escalate.sh linhas 70-72 hardcodam
   openrouter/deepseek/deepseek-v4-flash e openrouter/deepseek/deepseek-v4-pro.
   Verificado com `opencode models | grep deepseek`: esses ids NAO existem
   (os validos sao opencode/deepseek-v4-flash-free, opencode/deepseek-v4-pro,
   deepseek-direct/deepseek-v4-flash, openrouter/~deepseek/...-latest).
   Model id invalido faz opencode imprimir help e sair em ~0s.

2. Call site cru sem `--`. dispatch_model (linha ~100) chama
   `opencode run --auto --model "$model" "$(cat "$spec")"` DIRETO, sem o
   separador `--` antes do positional. Spec com frontmatter YAML comeca com
   `---` -> yargs interpreta como flag -> help + exit imediato. E o MESMO bug
   do incidente 2026-08-10-backtick... (tripcstory overnight), corrigido no
   adapters/opencode/runner.sh (que usa `-- "$(cat ...)"`) mas NAO neste call
   site, que alem disso viola a convencao do fluxo ("nenhum passo contem
   comando cru de CLI — sempre wrappers"). Reproduzido: runner.sh com spec
   com frontmatter funciona (respondeu OK); mesmo spec via dispatch-escalate
   morre em 0s com help no log.

Nota: o mesmo dispatch_model tem um terceiro caminho cru para claude
(`claude -p ... --dangerously-skip-permissions`) que merece a mesma auditoria.

## Correção aplicada

Nenhuma edicao no script nesta sessao — havia run vivo de dispatch-escalate
(pid 16352, CanIRunIt, via <home-do-dono>/.oracfit/current/bin) e a regra 48
proibe editar script bash que run vivo ainda vai executar. Workarounds usados:

- Tiers: override por env `DISPATCH_TIERS="opencode/deepseek-v4-flash-free
  opencode/deepseek-v4-pro"` (mecanismo ja existente, linha 78).
- Frontmatter: removido do specs/scentmatch-fotos-cdn.md (comentario HTML no
  lugar). Com os dois workarounds o flash passou na 1a tentativa (104s).

Correcao definitiva pendente (quando nao houver run vivo):
1. dispatch_model deve usar $DISPATCH_RUNNER (o runner ja resolve model id
   pelo registry e ja poe o `--`), ou no minimo adicionar `--` e validar o
   model id contra `opencode models` antes de despachar.
2. Atualizar os TIERS default das linhas 70-72 para ids existentes.

## Pode acontecer de novo?

Sim. Qualquer spec com frontmatter YAML (o proprio artefato-template gera
frontmatter!) despachada via dispatch-escalate.sh morre do mesmo jeito, e os
tiers default mortos pegam qualquer um que nao passe DISPATCH_TIERS. Pior: a
falha se disfarca de "modelo travado" e consome tiers/attempts do gauntlet.
Promover quando a correcao definitiva entrar; candidata:
"TENTATIVA QUE MORRE EM ~0s COM HELP DE CLI NO LOG E ERRO DE INVOCACAO, NAO
DE MODELO — pare o loop, nao escale tier; e todo call site que sobe modelo
usa $DISPATCH_RUNNER, nunca CLI crua" (familia das regras 39 e 42).
