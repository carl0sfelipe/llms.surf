---
id: 2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-run-finished
titulo: critic dispatch sem teto trava o stage loop e o run morre sem run_finished
data: 2026-08-11
recorrivel: sim
regra: 12
status: promovido
interage_com: "regra 12 (nenhum comando sem teto de tempo), regra 42 (job longo sem watchdog fica órfão), 2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback"
---

# Critic dispatch sem teto trava o stage loop e o run morre sem `run_finished`

## Sintoma

Run `43DF3F6F` (`content_factory` e2e via `bin/dispatch-stages.sh`) morreu
silenciosamente depois do attempt 1 do stage 1. No `events.jsonl`, o último
evento do run é a reprovação do attempt 1 — não existe `run_finished`, o ledger
(`.dispatch/ledger/mode.jsonl`) não recebeu linha, e o stdout nunca imprimiu as
linhas finais `run_id:` / `status:`. O attempt 2, que o `max_attempts` prometia,
nunca rodou. Para qualquer consumidor de telemetria, o run simplesmente não
terminou — mesma assinatura do incidente
`2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback` (lá em
`dispatch-mode.sh`, aqui em `dispatch-stages.sh`: segunda manifestação da
família "run acaba sem cauda de telemetria").

## Causa

Três defeitos que se somam, mais um agravante a montante:

1. **Critic dispatch sem teto (violação da regra 12).** Depois da reprovação do
   attempt 1, `dispatch-stages.sh` (linha ~361) chama
   `oracfit_gauntlet_run_critic`, que despacha
   `"$runner" "$critic_ref" "$crit_spec"` (`bin/lib-oracfit-gauntlet.sh`,
   linha ~448) **sem nenhum `bin/with-timeout.sh`** — a regra 12 manda todo
   comando que toca rede/modelo rodar sob teto, e esse call site nunca ganhou o
   mecanismo. O provider estava degradado (DeepSeek devolvendo respostas
   vazias / nunca respondendo), o dispatch do critic bloqueou indefinidamente e
   o processo acabou morto de fora. O attempt 2 nunca começou.

2. **Epílogo não garantido.** O `run_finished` + ledger + prints finais
   (linhas ~417-433 do `dispatch-stages.sh`) só executam se o script chega vivo
   ao fim do loop. Kill externo (ou morte por `set -e`) pula tudo — é o buraco
   de observabilidade já descrito no incidente de 2026-08-10, que ali ficou
   aberto sem causa isolada; aqui a causa é concreta: processo morto no meio do
   stage loop.

3. **`tee` sem `pipefail` mascarando exit code.** A invocação do e2e passava o
   output por `... | tee log`. Sem `set -o pipefail` (ou leitura de
   `PIPESTATUS`), o chamador enxerga o exit do `tee` (0), não o do
   `dispatch-stages.sh` — a morte anormal virou "terminou" para o invocador.

Agravante a montante (dívida, ver abaixo): antes do erro classificado, o
gauntlet **interno** do content-factory rodou 8 loops de juiz (~45 min) contra
o provider já degradado — cada volta era resposta vazia/truncada virando
`REVISIONS_REQUIRED`, queimando tempo e cota sem chance de sucesso.

## Correção (aplicada)

1. **Teto no critic (`bin/lib-oracfit-gauntlet.sh`).** O dispatch do critic em
   `oracfit_gauntlet_run_critic` agora roda sob `bin/with-timeout.sh` (resolvido
   via `ORACFIT_ROOT/bin` com fallback para o diretório da própria lib). Teto
   env-overridable: `ORACFIT_CRITIC_TIMEOUT`, default 180s. No estouro (exit
   124) o critic **falha aberto**: retorna gap vazio, o feedback heurístico já
   anexado permanece, uma linha de stderr nomeia o timeout, e o stage loop segue
   para o próximo attempt. O call site em `dispatch-stages.sh` mantém o
   `|| true` (critic nunca derruba o loop) e deixou de engolir o stderr
   (`2>/dev/null` removido) para a linha de timeout ser observável.

2. **Epílogo garantido (`bin/dispatch-stages.sh`).** Trap em EXIT/TERM/INT,
   instalado logo após o mint do `run_id`: se o script terminar antes do
   epílogo normal, emite `run_finished status=fail reason=abnormal_exit`,
   appenda a linha de ledger (best effort, `|| true`) e imprime `run_id:` /
   `status: fail`. Idempotente: o epílogo normal seta `epilogue_done=1` e o
   trap vira no-op no caminho feliz. Handler defensivo (tudo `|| true`, nada de
   `set -e` matando o trap no meio).

3. **Testes (`tests/test-stage-runner.sh`).** Dois novos casos: (a) critic
   pendurado (stub que dorme só quando chamado com o `critic_model_ref`) com
   `ORACFIT_CRITIC_TIMEOUT=2` — attempt 2 roda, o stage passa, wall time
   limitado e o stderr menciona o timeout do critic; (b) SIGTERM no meio de um
   stage — `events.jsonl` contém `run_finished` com `status=fail` e o stdout
   contém `status: fail`.

O item 3 da causa (tee sem pipefail) não ganhou mecanismo — é do invocador, não
do repo; a defesa é `set -o pipefail` / `PIPESTATUS` em quem canaliza o output
(o próprio `bin/dispatch-batch.sh` já faz certo com `${PIPESTATUS[0]}`).

## Dívida registrada (não implementada)

O gauntlet interno do content-factory rodou **8 loops de juiz (~45 min)**
contra provider degradado antes de qualquer erro classificado aparecer.
Candidato a mecanismo: **abort precoce por transporte repetido** — N respostas
vazias/truncadas consecutivas do mesmo provider deveriam encerrar o loop cedo
com erro de transporte, em vez de queimar o teto de iterações como se fossem
reprovações de mérito. Mesma família de
`2026-07-24-rate-limit-chega-como-timeout-nao-como-e` (degradação de provider
chegando disfarçada de outra coisa). Registrado aqui; não implementado neste
fit.

## Pode acontecer de novo?

No `dispatch-stages.sh`, as duas pontas fecharam: o critic tem teto (e o teto
tem teste), e qualquer morte pós-mint-de-run_id agora deixa `run_finished` +
ledger + `status: fail` para trás. Permanece possível fora daqui: a regra 12
segue "R" no mapa (nada obriga call sites novos a usar `with-timeout.sh`), o
incidente de 2026-08-10 no `dispatch-mode.sh` continua aberto (a correção deste
fit não tocou aquele script), e o abort precoce por transporte repetido no
gauntlet interno do content-factory é dívida declarada acima.
