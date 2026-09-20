---
id: 2026-09-20-run-with-fallback-reimprime-pulando-sem-
titulo: run-with-fallback reimprime pulando sem credencial a cada tentativa
data: 2026-09-20
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/run-with-fallback.sh lista as pernas sem credencial em detalhe só na 1ª tentativa (DISPATCH_ATTEMPT exportado pelo loop em bin/dispatch-mode.sh / bin/dispatch-stages.sh); nas seguintes, uma linha resumida; tests/test-credential-noise.sh cobre duas tentativas → detalhe 1x
status: corrigido
---

# run-with-fallback reimprime pulando sem credencial a cada tentativa

Dogfood real da v4.1.0 (2026-09-20): 45 linhas de "pulando sem credencial"
acumuladas num único run de 5 tentativas.

## Sintoma

Cada tentativa do loop re-imprime a listagem completa de pernas puladas:

```
  ↳ pulando <REF> — provider '<PROVIDER>' sem credencial em arquivo (E5-M5: env herdada não conta)
```

9 pernas sem credencial × 5 tentativas = 45 linhas do mesmo aviso no console
do run. O conteúdo não muda entre tentativas (credencial ou existe no arquivo
ou não existe) — é ruído puro que empurra o sinal (gap, veredito) para fora da
tela.

## Causa

`bin/run-with-fallback.sh:170-174` emite a linha incondicionalmente por perna,
sem latch. O processo é re-executado inteiro por tentativa: loop
`bin/dispatch-mode.sh:323` → `:414-416` re-invoca `run-with-fallback.sh` a
cada attempt (idem `bin/dispatch-stages.sh:302` → `:423-427`), então qualquer
latch em memória morre com o processo e a listagem renasce por tentativa.

## Correção aplicada

1. Loops de tentativa (`bin/dispatch-mode.sh`, `bin/dispatch-stages.sh`)
   exportam `DISPATCH_ATTEMPT` (número da tentativa corrente) para o runner.
2. `bin/run-with-fallback.sh` — na tentativa 1 (ou sem `DISPATCH_ATTEMPT`
   setado, caminhos legados/chamada direta): listagem detalhada como hoje.
   Nas seguintes: uma linha resumida por run
   ("↳ N pernas sem credencial — detalhes na tentativa 1") em vez de N linhas.
3. `tests/test-credential-noise.sh` — duas invocações com `DISPATCH_ATTEMPT=1`
   e `=2`: detalhe aparece uma vez, resumo na segunda.

## Pode acontecer de novo?

A condição (perna sem credencial) continua sendo reportada — o que para de
acontecer é a repetição idêntica por tentativa. Se um dia o console ganhar
deduplicação global, este latch sai junto; até lá, o sinal volta a caber na
tela.
