---
id: 2026-07-25-dispatch-saiu-com-exit-0-sem-fazer-nada-
titulo: Dispatch saiu com exit 0 sem fazer nada — e a tarefa não precisava de modelo
data: 2026-07-25
recorrivel: sim
interage_com: 1 (relativiza a "nunca escreva bulk, despache": ela vale para trabalho que exige julgamento, não para transformação determinística); 22 (exit 0 não é o mesmo que trabalho feito — a classificação de falha precisa cobrir o no-op silencioso); 9 (checar log antes de escalar foi o que evitou escalada desnecessária). RISCO: usada como desculpa, esta regra vira licença para o orquestrador escrever tudo — o critério é "a entrada é conhecida e a transformação é mecânica?", não "acho mais rápido fazer eu".
regra: 31
status: promovido
---

# Dispatch saiu com exit 0 sem fazer nada — e a tarefa não precisava de modelo

## Sintoma

Despachei ao `deepseek-v4-flash-free` a inclusão de 16 modelos no
`model-registry.json`. O dispatch retornou **exit 0** — sucesso — e o registry
ficou **idêntico**: 31 modelos, 5 hints, nenhum commit novo.

## Causa

Duas, independentes.

**(1) Exit 0 não significa trabalho feito.** O log mostra o modelo fazendo duas
chamadas de `read` e encerrando no primeiro step:

```
tool_use ... "tool":"read" ...
tool_use ... "tool":"read" ...
step_finish ... "reason":"tool-calls"
```

Ele desistiu cedo. Não travou, não errou, não avisou — terminou limpo sem
produzir nada. É um **no-op silencioso**, e o exit code não distingue isso de
sucesso real. Só o diff do arquivo distingue.

**(2) A tarefa nunca precisou de modelo.** Transformar uma lista conhecida
(`/tmp/ok-models.txt`, 19 linhas) em 16 entradas JSON com campos fixos é
transformação **determinística**. Escrevi o script em um passo e rodou certo de
primeira: 16 adicionados, 22 hints, zero campo inventado.

Despachar isso custou um ciclo inteiro de dispatch, produziu nada, e adicionou
risco que o script não tem — modelo pode inventar `accuracy` onde a regra manda
`null`.

## Correção aplicada

Nenhuma no código. É critério de decisão, e por isso vira regra: antes de
despachar, perguntar se a entrada é conhecida e a transformação é mecânica. Se
for, é código, não modelo.

E toda verificação de dispatch passa a exigir **evidência de mudança** (diff,
contagem, hash), nunca exit code.

## Pode acontecer de novo?

**Sim.** A regra 1 do `SKILL.md` ("nunca escreva bulk, despache") empurra na
direção oposta e não distingue trabalho de julgamento de trabalho mecânico.
Enquanto essa distinção não estiver explícita, o orquestrador vai continuar
despachando transformação determinística — e aceitando exit 0 como prova.
