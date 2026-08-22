---
id: 2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback
titulo: run com attempt_finished + oraculo passou nunca grava ledger nem usage-feedback
data: 2026-08-10
recorrivel: sim
regra: 39
status: promovido
interage_com: "2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca, 2026-07-26-spec-sem-clausula-anti-invencao-gera-num, 2026-08-01-emit-usage-feedback-nao-chamado-pelo-modo (achado citado no proprio bin/dispatch-mode.sh)"
---

# Run com `attempt_finished` + oráculo passou nunca grava ledger nem usage-feedback

## Contexto de uso (relatório de eficácia desta sessão)

Rodei `oracfit run deepseek_direct_flash <spec> <task>` de dentro do repo `<repo-cliente>.live-imports`
(BMAD PM/Architect gerando plano técnico de um pivot de produto), com `ORACFIT_ROOT=$PWD`
(`<home-do-dono>/oracfit`) e `DISPATCH_RUNNER=$PWD/adapters/opencode/runner.sh`. Três tentativas:

1. **Primeira spec** — reprovada no preflight por `bin/check-spec.sh`: faltava cláusula
   anti-invenção, bloco de dados verificados, `## Oráculo` com linha `comando:`. **Funcionou
   como projetado** — zero tokens de modelo gastos, erro apontado com precisão cirúrgica
   (linha por linha do que faltava).
2. **Segunda tentativa**, spec corrigida — reprovada de novo, agora por
   `bin/check-oracle.py`: `^\|` no comando do oráculo era pipe **literal**, não alternação
   (exatamente o defeito descrito em `2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca.md`,
   regra 39). **Preflight pegou de novo, antes de rodar** — mecanismo da regra 39 confirmado
   funcionando num contexto totalmente novo (spec de documentação, não código).
3. **Terceira tentativa**, oráculo corrigido para `^[|]` — rodou limpo: modelo (DeepSeek Flash
   direto, `deepseek-direct/deepseek-v4-flash`) explorou o repo de verdade (grep/ls/cat em
   ~15 chamadas de bash/read antes de escrever), produziu documento de 265 linhas mapeado a
   caminhos reais do monorepo, oráculo passou de primeira (`exit=0`, sem refinamento). 118s de
   execução (`run_id=574E18F9-40DE-4F5B-962C-BD2989F092DE`, evento `attempt_finished` às
   `2026-08-10T06:55:25Z`, `runner_exit=0`).

**Isso tudo foi bom** — as duas reprovações de preflight são o sistema funcionando (barato,
rápido, sem queimar modelo); a terceira tentativa entregou documento correto de primeira.

## Sintoma

O run que passou não deixou rastro em nenhum ledger nem gerou incidente de uso automático:

```
$ tail -1 <home-do-dono>/oracfit/.dispatch/ledger/mode.jsonl
{"ts": "2026-08-10T04:36:25Z", ..., "task": "release-unlock-smoke", ...}   # 2h20min ANTES do meu run
```

```
$ find <home-do-dono>/oracfit/.dispatch/logs/events.jsonl -exec tail -1 {} \;
{"ts": "2026-08-10T06:55:25.428580+00:00", "type": "attempt_finished", "attempt": "1",
 "runner_exit": "0", "duration_s": "118.207"}
```

`attempt_finished` é o último evento do run inteiro em `events.jsonl` — não existe
`run_finished` depois dele, embora `bin/dispatch-mode.sh` emita esse evento explicitamente
logo após a chamada de `oracfit_emit_metric_and_ledger` (linha ~421). O ledger workdir-scoped
(`ORACFIT_WORKDIR/.dispatch/ledger/mode.jsonl` — que nesse caso acabou sendo o próprio
`<home-do-dono>/oracfit`, ver causa nº2 abaixo) também não recebeu a linha. Nenhum arquivo em
`incidents/uso/` foi gerado por `bin/emit-usage-feedback.sh`, apesar do comentário no próprio
`dispatch-mode.sh` linha 431-436 prometer isso "em todo modo de dispatch".

Confirmado por artefato colateral: o run **claramente terminou e teve sucesso** — os
artefatos de inbox existem (`inbox/574E18F9-*.task-name`, `.spec-file`, `.mode-id`,
`.gauntlet/ground-truth.md`, `.gauntlet/feedback.md`), o arquivo pedido foi escrito com 265
linhas corretas, e o comando de oráculo (visível no log de tool_call) rodou e teria de
retornar `exit=0` pra explicar o `thinking` final do modelo confirmando sucesso. Só a cauda
de telemetria (ledger + usage-feedback) ficou muda.

**Achado secundário, não confundir com o principal:** `inbox/574E18F9-*.gauntlet/oracle-attempt-1.log`
existe mas está **vazio**, apesar do comando de oráculo ter rodado de fato (visível via
`tool_call` no `events.jsonl`). Log do oráculo não capturado — gap de sensor menor, mesma
família dos incidentes "sensor mentiu/ficou cego" já catalogados.

## Causa (parcial — não totalmente isolada ainda)

Duas causas prováveis, não excludentes:

1. **Bug de emissão pós-loop:** `dispatch-mode.sh` roda sob `set -euo pipefail` (linha 3) e
   de novo `set -e` na linha 233. Entre o `attempt_finished` (linha 383, dentro do loop) e a
   chamada de `oracfit_emit_metric_and_ledger` (linha ~415-424, fora do loop) existem
   substituições de comando (`python3 -c ...` pra `t_run1`/`frontier_wait_s`) que, sob `-e`,
   matam o script silenciosamente se qualquer uma retornar não-zero — e nenhum `trap ERR`
   visível nesse trecho pra registrar a causa antes de morrer. Não reproduzi isoladamente
   ainda (precisa rodar `bash -x` num novo dispatch e capturar o ponto exato de saída).
2. **Erro meu de invocação, mas revelador de um gap de UX:** exportei `WORKDIR=...` em vez
   de `ORACFIT_WORKDIR=...` (nome certo, confirmado em `bin/oracfit --help` → "ROOT vs
   workdir"). A variável errada foi silenciosamente ignorada — sem warning, sem fallback
   avisado — e tudo (`events.jsonl`, `ledger/mode.jsonl`, inbox) foi escrito dentro do
   `ORACFIT_ROOT` (`<home-do-dono>/oracfit`) em vez do workdir real do projeto
   (`<home-do-dono>/<repo-cliente>.live-imports/.dispatch/`, que ficou intocado — confirmado, ainda tem
   `ledger/mode.jsonl` de 4 de agosto). Isso por si não explica a ausência da linha de
   ledger (o `mode.jsonl` errado também não recebeu nada), mas é um gap de validação
   separado: `oracfit` não valida nem avisa sobre env var de workdir não reconhecida.

## Por que registrar sem causa isolada

Regra do próprio projeto (regra 32: mecanismo sem prova é dívida) pede não prometer conserto
que não foi verificado — então este incidente fica **aberto**, não **promovido**. O valor de
registrar agora, mesmo incompleto: é a segunda vez que o padrão "`attempt_finished` sem
`run_finished` companheiro" aparece (a primeira foi hipotetizada no comentário de código do
próprio `dispatch-mode.sh` sobre `emit-usage-feedback.sh` nunca ter sido chamado do fluxo
principal — achado de 2026-08-01, corrigido só parcialmente). Este caso mostra que mesmo após
aquela correção, ainda existe caminho onde a telemetria do modo principal se perde.

## Pode acontecer de novo?

Sim — não isolei se é 100% dos runs de `oracfit run <mode>` ou só sob a condição de env var
errada. Próximo passo pra fechar: rodar `bash -x bin/dispatch-mode.sh normal <spec-smoke> t`
com `ORACFIT_WORKDIR` correto e comparar se a linha de ledger aparece; se sim, a causa é
puramente a var errada (grave, mas menor); se não, é bug real na emissão pós-loop (mais
grave, afeta todo mundo que usa `oracfit run` certo).

## Resumo de eficácia desta sessão (o que pediu o relatório)

| O que | Avaliação |
|---|---|
| Preflight `check-spec.sh` (anti-invenção/dados verificados) | ✅ funcionou, pegou spec fraca antes de gastar modelo |
| Preflight `check-oracle.py` (pipe escapado) | ✅ funcionou, pegou de novo o mesmo padrão de bug do incidente de 07-29 — mecanismo generaliza pra spec de doc, não só código |
| Qualidade do output do DeepSeek Flash direto | ✅ alta — explorou repo real antes de escrever, zero número/caminho inventado, oráculo passou de primeira |
| Velocidade | ✅ 118s pra doc de 265 linhas grounded |
| Telemetria pós-run (ledger + usage-feedback) | ❌ silenciosamente ausente — achado principal deste incidente |
| Log do oráculo (`oracle-attempt-1.log`) | ❌ vazio apesar do comando ter rodado |
| Validação de `ORACFIT_WORKDIR` vs var errada | ❌ nenhum aviso quando nome de env var não é reconhecido |

## Correção no core (2026-08-12, v3.5)

As duas causas prováveis ganharam mecanismo em `bin/dispatch-mode.sh`:

1. **Causa nº1 (morte muda no epílogo):** tudo depois do loop de attempts
   roda sob `set +e` — substituição de comando falhando não mata mais o
   script antes de `oracfit_emit_metric_and_ledger` + `run_finished` +
   usage-feedback. Não isolei qual substituição matava; tornei a classe
   inteira incapaz de matar (a telemetria é melhor-esforço por definição).
2. **Causa nº2 (env `WORKDIR` ignorada em silêncio):** aviso alto no início
   do run quando `WORKDIR` está setada e diverge de `ORACFIT_WORKDIR`,
   apontando o nome certo.
