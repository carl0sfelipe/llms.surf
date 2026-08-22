---
id: 2026-08-12-dispatch-de-shell-de-agente-morre-com-o-
titulo: dispatch de shell de agente morre com o grupo — runner sobrevive orfao sem watchdog
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/dispatch-bg.sh (double-fork + os.setsid = sessao propria, imune a SIGHUP e a kill de grupo do lancador; pid em <log>.pid); smoke validado em 2026-08-12
status: promovido
interage_com: "regra 42 (mesma familia: job longo sem watchdog; aqui o job FOI lancado pelo dispatch e o watchdog morreu por fora)"
interage_com: "2026-08-12-runner-herda-cwd-do-lancador-modelo-desp.md (mesmo run 36E63816, evento distinto)"
---

# dispatch de shell de agente morre com o grupo — runner sobrevive órfão

## Sintoma

Run `36E63816`, lançado de um shell de agente (Cursor) com
`nohup bash bin/dispatch-stages.sh ... & `. Minutos depois:
`dispatch-stages.sh` e `runner.sh` mortos; o `opencode` seguia vivo com
PPID 1 (órfão adotado pelo launchd). Consequências: sem watchdog de
silêncio, sem oráculo ao final, sem `run_finished` — e um filho pendurado
(`uv run ... mcp_server`) segurou o opencode indefinidamente até kill manual.

## Causa

EVIDÊNCIA: `ps -o pid,ppid -p <opencode>` → PPID 1; cadeia bash ausente do
`ps`; log do gauntlet parado sem evento terminal.

O harness do shell de agente encerra o process group do comando ao fim do
turno. `nohup` protege de SIGHUP, não de kill de grupo. O opencode escapou
por criar pgid próprio; a cadeia bash (dispatch-stages → runner → watchdog)
compartilhava o pgid do lançador e morreu junto. O trabalho seguiu SEM
nenhuma das proteções do dispatch.

## Correção aplicada

`bin/dispatch-bg.sh`: lançador que faz double-fork + `os.setsid()` (python3)
— o dispatch roda em SESSÃO própria, fora do alcance do harness; stdout e
stderr vão para o log dado; PID final em `<log>.pid`. Smoke: processo
sobreviveu ao fim do shell lançador com pgid/sess próprios.

Uso: `bin/dispatch-bg.sh /tmp/run.log bin/dispatch-stages.sh <modo> <spec> <task> --workdir <dir>`

## Pode acontecer de novo?

Só se o lançador ignorar o dispatch-bg.sh e voltar ao `nohup ... &` cru.
Todo dispatch lançado de shell de agente (Cursor, CI, hook) deve passar por
`bin/dispatch-bg.sh`. Neste run o dano foi contido porque o trabalho do
modelo estava íntegro em disco e o oráculo foi executado manualmente.

## 2ª ocorrência (2026-08-12 ~10:14Z) — shell GERENCIADO do harness também não basta

Dispatch `panel-usage-api` (run C553E05B, mode deepseek_direct_flash) lançado
como shell de background GERENCIADO do Cursor (não chamada pontual): a árvore
inteira (bash → oracfit → dispatch-mode → runner → opencode) morreu ~60s
depois do início, logo após o modelo escrever o arquivo-alvo — sem
`attempt_finished`, sem `run_finished`, sem linha de ledger (o epílogo
melhor-esforço não sobrevive a SIGKILL de grupo). O arquivo de terminal do
harness congelou e o pid sumiu do ps. O painel classificou o run como
`abandonado` (correto).

Dano contido por dois mecanismos do próprio framework: (1) o trabalho já
estava no disco e o julgamento releu o disco (ADR-0002) — oráculo verde,
trabalho aproveitado; (2) o run seguinte (`panel-usage-cards`), idêntico no
lançamento, completou e emitiu telemetria cheia.

Lição operacional: para dispatch a partir de shell de agente Cursor, o
mecanismo deste incidente (`bin/dispatch-bg.sh`, double-fork + setsid) é o
ÚNICO lançamento à prova de limpeza de grupo — shell "gerenciado" do harness
reduz mas NÃO elimina a classe (garante o arquivo de log, não a vida do
grupo). Complementa a regra 49 (lá: processo de longa duração; aqui: o
próprio dispatch).
