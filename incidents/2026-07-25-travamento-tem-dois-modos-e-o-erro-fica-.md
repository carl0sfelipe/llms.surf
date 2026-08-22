---
id: 2026-07-25-travamento-tem-dois-modos-e-o-erro-fica-
titulo: Travamento tem dois modos, e o erro fica no banco — não no stderr
data: 2026-07-25
recorrivel: sim
interage_com: 18 (a 18 inspeciona stderr; este incidente mostra que há erro que NUNCA passa por lá — complementa, não substitui); 22 (dá causa concreta ao "modo (c) silêncio sem erro"); 15 (o que investigar quando há silêncio); 20 (context_window do registry passa a ter uso operacional, não só informativo). RISCO: o item 5 do diagnóstico usa context_window de spec, que é dado NÃO verificado — pode acusar contexto pequeno errado.
regra: 27
status: promovido
---

# Travamento tem dois modos, e o erro fica no banco — não no stderr

## Sintoma

Toda chamada de modelo pendurando até o teto, em **quatro providers diferentes**
(opencode Zen, groq, nvidia, openrouter), sem erro nenhum no stderr. Pela manhã o
mesmo comando respondia em 3s. Diagnostiquei como rate limit — errado de novo.

## Causa

São **dois modos distintos**, e o que os separa é uma pergunta objetiva: *a sessão
existe no banco?*

**Modo 1 — sessão existe, erro gravado no banco.** `groq/llama-3.3-70b-versatile`
criou sessão (4 mensagens, 1 KB) e falhou com:

```
mode: compaction | agent: compaction
ContextOverflowError
"Session too large to compact - context exceeds model limit even after stripping media"
```

A mensagem é enganosa: a sessão tinha **1 KB**. O que não cabe é o prompt base do
opencode (sistema + ferramentas) no `context_window` de **6000 tokens** do modelo
— valor que o nosso próprio registry já declarava. **Não é incapacidade do modelo:
é incompatibilidade com o harness.** Qualquer modelo de contexto pequeno vai
reproduzir isso.

**Modo 2 — nenhuma sessão criada.** Os outros quatro testes não gravaram linha
alguma no banco. Mesma assinatura do incidente fundador de 52min. Causa
**não determinada** — rede confirmada boa (openrouter 200 em 0,13s), zero
processos concorrentes, zero órfãos, WAL zerado, leitura do banco em 0,3s.

**O que tornou tudo opaco:** no modo 1 o erro está **no banco**, não no stderr.
`--print-logs --log-level ERROR` não mostra. A detecção da regra 18 inspeciona
stderr e por isso nunca vê esse caso.

## Correção aplicada

`bin/diagnose-hang.sh` — classifica o travamento em vez de adivinhar. Cinco
verificações: concorrência (regras 8/19), órfãos (regra 21), **sessões criadas no
período** (separa modo 1 de modo 2), **erros gravados no banco** (o que o stderr
esconde) e `context_window` do modelo com aviso quando < 16K.

Verificado: aponta o `ContextOverflowError` do groq e o `context_window=6000`.

## Pode acontecer de novo?

**Sim.** O modo 1 se repete com todo modelo de contexto pequeno — e o registry tem
vários. O modo 2 segue sem causa conhecida e já apareceu 6x em dois dias.
