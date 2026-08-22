---
id: 2026-07-25-grupo-nao-basta-neto-com-set-m-escapa
titulo: Kill de grupo não basta — neto com set -m escapa e vira órfão
data: 2026-07-25
recorrivel: sim
regra: 21
status: promovido
---

# Kill de grupo não basta — neto com `set -m` escapa e vira órfão

## Sintoma

O gate de concorrência barrou um dispatch acusando **9 processos** `opencode run`
ativos. Eram órfãos das minhas próprias rodadas de benchmark, vivos por até
**16 minutos** depois de os timeouts terem "matado" tudo:

```
 4320 ??  16:50 S  opencode run --print-logs --log-level ERROR --model qwen-token-plan/qwen3.8-max-pr
 4943 ??  15:50 S  opencode run ...
 ... (9 processos, TTY ??, todos qwen3.8-max-preview)
```

Consequência real: órfãos contendem pelo store e **causam** o travamento que as
proteções existem para evitar. A proteção estava criando o problema.

## Causa

A regra 17 mandou matar o **grupo** (`kill -PID`). Não alcança este caso:

1. `with-timeout.sh` roda o filho com `setpgrp` → filho é líder do grupo A
2. o filho é `adapters/opencode/runner.sh`, que faz **`set -m`** (job control) e
   sobe `opencode run` em background → o neto vira líder do **próprio grupo B**
3. `kill -A` mata o grupo A; o grupo B **sobrevive**
4. `runner.sh` só mata o grupo B quando *ele* detecta erro (regra 18) — num
   SIGKILL externo ele morre sem limpar, e o neto fica órfão

Ou seja: as duas correções (17 e 18) interagiram e abriram um furo que nenhuma
das duas tinha sozinha.

## Correção aplicada

`bin/with-timeout.sh`: mata a **árvore** — descobre descendentes com `pgrep -P`
recursivamente, filhos antes do pai, e só então `kill -PID` + `kill PID`.

Regressão (wrapper com `set -m` subindo neto, teto de 4s):

```
⏱️  TIMEOUT: comando excedeu 4s — árvore de processos morta.
exit=124
✅ arvore morta — neto com grupo proprio tambem
```

Antes do fix, o mesmo teste deixava o `sleep 300` vivo.

## Pode acontecer de novo?

**Sim.** Qualquer wrapper na cadeia pode chamar `setsid`/`set -m` e criar um novo
grupo. Só matar por árvore (ou por cgroup, indisponível no macOS) é robusto.
Vale também para o watchdog de `bin/dispatch.sh`, que ainda mata por grupo.
