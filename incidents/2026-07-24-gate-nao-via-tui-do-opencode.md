---
id: 2026-07-24-gate-nao-via-tui-do-opencode
titulo: Gate de concorrência não enxergava a TUI do opencode
data: 2026-07-24
recorrivel: sim
regra: 19
status: promovido
---

# Gate de concorrência não enxergava a TUI do opencode

## Sintoma

Toda chamada de modelo pendurava e estourava o teto — Zen e OpenRouter, sem erro
nos logs. Minutos antes, o mesmo modelo respondia em ~3s.

## Causa

`ps` durante o travamento:

```
PID 67063  PPID 67024  TTY ttys001  ELAPSED 20:38  STAT S+  opencode
```

Sessão **interativa** do usuário (`S+` = primeiro plano, TTY real), aberta há 20min,
contendendo pelo mesmo store do opencode. Mesma classe do incidente fundador
(`2026-07-24-travamento-silencioso`), com agente humano no lugar do Hermes.

O gate de `bin/pre-dispatch-check.sh` deveria ter barrado, mas procurava por
`"opencode run"` — a TUI roda como `opencode` puro, sem subcomando, e passava batido.
Proteção existia e não cobria o caso mais provável do dia a dia: o usuário com o
próprio opencode aberto.

## Correção aplicada

`bin/pre-dispatch-check.sh`: padrão passa a incluir `^opencode$` além de `opencode run`.
Verificado: `WAIT agente-concorrente-ativo — opencode(pid:67063)`, exit 1.

## Pode acontecer de novo?

**Sim.** Todo CLI tem forma interativa e forma de subcomando; um padrão que só cobre
a segunda deixa a porta aberta. Vale para `hermes --tui`, `qwen`, `zcode` quando
existirem.
