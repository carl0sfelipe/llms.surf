# ESCALADA-5 — Fable: o caminho FREE é o produto (prioridade do dono)

> URGENTE, 2026-08-31. Incidente entregue por sessão externa
> (incidents/2026-08-30-free-models-sao-a-prioridade-do-dono-e-o.md) e
> NUMEROS VERIFICADOS por mim na árvore do main hoje:
> `resolve-tier tier:cheap` → deepseek-v4-flash-free; audit-registry-ids:
> 21 NAO-ENCONTRADO + 25 FANTASMA de 69 ids (46/69 quebrados).

## A diretriz do dono (tese do produto)

O default do llms.surf é o caminho FREE: modelo caro pensa, modelos
grátis suam. Hoje o default resolve pra fantasma, 46/69 ids do registry
estão mortos, e o catalogo autenticado na prática é PAGO (118 Bedrock +
36 Copilot vs 6 opencode free). O README promete o que o código não
entrega — isso é a classe de incidente mais grave da casa.

## A fonte nova que o dono quer usar

https://github.com/open-free-llm-api/awesome-freellm-apis — lista
curada de APIs LLM gratuitas. O dono quer isto INTEGRADO: o registry
alimentado a partir dessa lista (ids alcançáveis, endpoints, limites),
com proveniência carimbada por fonte — o mesmo espírito do import S28
(localmaxxing carimbado como `reported`): fonte declarada, nunca id
solto.

## O caminho de correção proposto (6 itens, todos gate/script — classe C)

1. Preflight que separa: catalogo inalcançável / id inexistente /
   provider não autenticado (mensagens distintas, fail loud).
2. lib-free-credentials.sh ÚNICA: descobrir TODOS os providers do
   auth.json (~/.local/share/opencode/auth.json) em vez de só OpenRouter
   hardcoded (a captura existe 3x nos scripts de vision, nunca no caminho
   principal — dívida regra 32).
3. Plug do audit-registry-ids no dispatch (fantasma não despacha).
4. tier:cheap resolve para LISTA com fallback, não id único.
5. provider_efetivo no ledger (o run registra quem atendeu de verdade).
6. Allowlist de provider por run.

## O que o Fable entrega

1. **Desenho da integração awesome-freellm-apis → registry**: mapeamento
   da lista pra entries do registry com proveniência (fonte + data de
   coleta), o que vira tier:cheap, e como evita-los virarem os próximos
   25 fantasmas (o mecanismo que impede id morto no caminho default).
2. **Ordem e gate dos 6 itens de correção** com oráculo por item (classe
   C, todos gate/script, $0) — sequência pra fechar o caminho free ANTES
   do anúncio de lançamento.
3. **Definição de "fechado"**: o gate que prova que o default free
   despacha de verdade sem credencial paga (a promessa do README medida,
   não assumida).

## Restrições

- NADA de disciplina/prompt: tudo mecanismo (regra 32).
- Não tocar em bestmodel-prod/Vast/rig Paraguai.
- A sessão externa que achou isso NÃO corrigiu nada — só registrou
  (fluxo correto); a implementação é nossa, com oráculo congelado.
