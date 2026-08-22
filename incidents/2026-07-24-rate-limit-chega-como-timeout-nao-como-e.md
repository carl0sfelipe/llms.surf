---
id: 2026-07-24-rate-limit-chega-como-timeout-nao-como-e
titulo: Rate limit chega como timeout (124), não como exit 2
data: 2026-07-24
recorrivel: sim
regra: 18
status: promovido
---

# Rate limit chega como timeout (124), não como exit 2

## Sintoma

Modelo "parou de responder": toda chamada estourava o teto e voltava `exit 124`.
Diagnóstico inicial (meu) foi vago — "opencode parou" — sem evidência.

## Causa

Com `--print-logs --log-level ERROR`, o erro real aparece na hora:

```
error="AI_APICallError: Rate limit exceeded. Please try again later."  (deepseek-v4-flash-free)
error="AI_APICallError: Insufficient balance."                          (gpt-5.4-nano, modelo auxiliar)
```

`adapters/opencode/runner.sh` detecta rate limit com `grep -qiE '429|rate.?limit'`
sobre `$OUTPUT` — mas `OUTPUT=$(...)` só existe **depois** que o processo termina.
Em rate limit o processo fica pendurado, então a deteção nunca roda: o teto mata
antes e devolve 124. O erro estava no stderr o tempo todo e o framework ficou cego.

Consequência prática: a cadeia de fallback do RF-08 (que dispara em `exit 2`)
nunca é acionada justamente no caso para o qual foi criada.

## Correção aplicada

Nenhuma ainda — registrado antes de corrigir porque a sessão foi encerrada.

Correção proposta: runner lê o output em streaming (ou roda com `--print-logs`
e inspeciona stderr incrementalmente) e devolve `exit 2` assim que casar
`Rate limit|429`, sem esperar o processo terminar. Complemento: `exit 4` para
`Insufficient balance`, que é quota/saldo, não rate limit.

## Pode acontecer de novo?

**Sim**, em todo provider que pendura em vez de fechar a conexão no rate limit.
Enquanto não corrigido, todo rate limit se disfarça de travamento — e travamento
disfarçado foi o que custou 52min neste mesmo dia.
