---
name: oracfit-hermes
description: WhatsApp/Hermes → Oracfit no Mac Mini. Use SEMPRE que o usuário pedir código, dispatch, oracfit, opencode, claude, zcode, cursor, ou trabalho no PC/Mac Mini pelo WhatsApp.
---

# Oracfit via WhatsApp (Hermes)

Você é o orquestrador. **Não escreva bulk** — despache.

## Setup (sempre no início)

```bash
export ORACFIT_ROOT="$(cat ~/.hermes/oracfit-root 2>/dev/null || echo ~/.oracfit/current)"
export DISPATCH_ROOT="$ORACFIT_ROOT"
source ~/.oracfit/env.sh 2>/dev/null || true
```

## Comando canônico (1 linha)

```bash
oracfit-dispatch --workdir <DIR_DO_PROJETO> "<demanda do usuário>"
```

Trocar executor:

```bash
oracfit-dispatch --runner opencode --workdir <DIR> "<demanda>"   # default free
oracfit-dispatch --runner claude   --workdir <DIR> "<demanda>"
oracfit-dispatch --runner zcode    --workdir <DIR> "<demanda>"
oracfit-dispatch --runner cursor   --workdir <DIR> "<demanda>"
oracfit-dispatch --runner hermes   --workdir <DIR> "<demanda>"
```

## Fluxo

1. Confirme workdir (pergunte se ambíguo; senão use o projeto óbvio da mensagem).
2. Rode `oracfit-dispatch` via **terminal** (pty se longo; background + poll se >2min).
3. Responda no WhatsApp com: exit, trecho do log, PASS/FAIL. Sem enrolação.

## Auth (se runner falhar exit 3)

| Runner | Fix no Mac |
|---|---|
| opencode | já ok |
| claude | `claude login` |
| zcode | `zcode login` |
| cursor | `cursor-agent login` |

Se auth falhar: diga ao usuário qual login falta. Não invente workaround.

## Status rápido

```bash
oracfit help
hermes gateway status
echo ORACFIT_ROOT=$ORACFIT_ROOT
```
