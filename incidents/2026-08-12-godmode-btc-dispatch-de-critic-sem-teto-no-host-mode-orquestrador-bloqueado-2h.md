---
id: 2026-08-12-godmode-btc-dispatch-de-critic-sem-teto-no-host-mode-orquestrador-bloqueado-2h
titulo: GODMODE-BTC dispatch de critic travou 2h04m sem heartbeat e o orquestrador ficou bloqueado síncrono até o dono voltar — recorrência do critic-sem-teto de 2026-08-11, agora no canal Task do host (que a regra do core não cobre)
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo aplicado (bin/critic-guard.sh run --budget / arm --budget + watch); destino das 3 candidatas na seção "Convergência v4"
status: incorporado
interage_com: "2026-08-12-godmode-btc-critic-read-only-commitou-o-trabalho-e-travou-2h-sem-relatorio"
interage_com: "2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-run-finished"
interage_com: "2026-07-24-travamento-silencioso"
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
---

# GODMODE-BTC — critic sem teto no host-mode (falha de PROCESSO)

Satélite do incident de contrato (critic commitou — ver
`interage_com`). Este cobre só o modo de falha de processo: dispatch
sem teto, sessão parada, humano como watchdog.

## O que aconteceu

- ~21:38: orquestrador (Fable, host-mode Cursor) despachou o critic do
  loop E e ficou aguardando o retorno da Task de forma síncrona.
- O critic fez writes indevidos até 21:55 (incident irmão) e depois não
  produziu mais nada observável.
- Nenhum teto, nenhum heartbeat, nenhum watchdog: a Task só morreu às
  23:43, quando o DONO voltou e interrompeu — "interrupted by the user
  after 7494833ms" (2h04m53s).
- Custo: ~1h48m de parede perdidos após o último evento observável
  (21:55), numa sessão cujos 4 critics anteriores devolveram relatório
  em minutos.

## Por que é recorrência (e o que tem de novo)

O incident `2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-
run-finished` já registrou exatamente esta classe no CORE: critic sem
teto trava o stage e o run morre sem `run finished`. A resposta de lá
protege o caminho `bin/oracfit`. **Este aqui aconteceu no canal Task
do host (Cursor)** — que não passa por `bin/oracfit` e portanto ficou
fora do alcance daquela regra. É a mesma lição do ouroboros/pythia
("host-mode é invisível aos mecanismos"), terceira ocorrência da
família em dois dias, agora no órgão dispatch-de-subagent.

Agravante específico: o orquestrador tinha BASELINE para desconfiar —
os critics dos loops A, C e D da mesma sessão retornaram em minutos.
Não havia regra nem hábito de converter essa baseline em teto.

## Regras candidatas para a v4

1. **Teto de parede para todo dispatch host-mode** (extensão da regra
   do critic-sem-teto do core para o canal Task): critic de diff tem
   orçamento na casa de minutos, não horas; estourou → mata, registra
   incident automático e o orquestrador decide (re-despachar fresco ou
   auditar ele mesmo — a recuperação daqui provou que a segunda opção
   custa ~25 min).
2. **Orquestrador nunca bloqueia síncrono em dispatch sem vigia**:
   dispatch em background + watchdog paralelo (o host já oferece
   notificação de conclusão e lembrete agendado; usar). O papel do
   dono NÃO é ser o timeout do sistema.
3. **Heartbeat obrigatório em dispatch de longa duração**: sem output
   observável por N minutos = anomalia, não paciência. Aqui o último
   evento observável (os commits rogue de 21:55) antecedeu 1h48m de
   silêncio absoluto.

## Evidência preservada

- Duração: "Task was interrupted by the user after 7494833ms"
  (mensagem do host na sessão do orquestrador).
- Janela de silêncio: últimos eventos observáveis às 21:55 (commits
  `6ae4844`/`7ae7384` no alvo); interrupção às 23:43 pelo dono.
- Baseline dos critics da sessão: loops A/C/D com relatório entregue
  em minutos (mesma sessão, mesmo tipo de dispatch).
- Recuperação em ~25 min: auditoria manual + gates completos +
  push `dde015c` (00:10).

## Pode acontecer de novo?

Sim — qualquer dispatch host-mode de hoje repete o cenário. Enquanto o
teto for "o dono voltou e estranhou", o watchdog do god mode é uma
pessoa dormindo.

(2026-08-13: superado — mecanismo abaixo. O parágrafo acima fica como
registro histórico.)

## Convergência v4 (2026-08-13) — destino das 3 regras candidatas

Mecanismo: os subcomandos de teto/vigia de `bin/critic-guard.sh` (a mesma
janela do incident irmão de contrato). Simulação adversarial em
`tests/test-critic-guard.sh`: dispatch dormindo com `--budget 2` é morto
em ~3s (exit 124) e o incident aparece em `incidents/` sem intervenção
humana; vigia do canal Task com teto vencido grava incident e sai 124.

| Candidata | Destino | Mecanismo / motivo |
|---|---|---|
| 1. Teto de parede para todo dispatch host-mode | MECANISMO | canal shell: `bin/critic-guard.sh run` embrulha o dispatch em `bin/with-timeout.sh` com teto DEFAULT de 900s (nunca sem teto — o default existe para o call-site que esquece); estouro = árvore de processos morta + incident automático + `guard_timeout` no ledger central. Canal Task: `arm --budget` lança o vigia em daemon (`bin/dispatch-bg.sh`, double-fork) que grava incident na expiração. LIMITE DECLARADO: o vigia não consegue MATAR uma Task do host (o processo pertence ao harness) — ele mata o SILÊNCIO (alarme + incident), e a saída manda interromper a Task e rodar `check` |
| 2. Orquestrador nunca bloqueia síncrono sem vigia | MECANISMO parcial + rejeição registrada | o vigia em daemon É o vigia da candidata: dispara mesmo com o orquestrador preso na Task (sobrevive à sessão — mesmo substrato de `bin/oracfit-daemon.sh`). A metade comportamental ("despache em background, use notificação do host") foi REJEITADA como regra-texto nova: seria mais uma cláusula sem mecanismo (a classe que o autarca provou degradar), e com o vigia armado a violação dela deixa de ter dano — o alarme dispara de qualquer jeito. Motivo registrado aqui, não silêncio |
| 3. Heartbeat obrigatório em dispatch longo | CONVERGIDA no teto do vigia + rejeição parcial registrada | heartbeat por OUTPUT foi rejeitado para o canal Task: a Task do host não expõe stream observável ao repo — não há byte para medir (o watchdog de silêncio de `bin/dispatch.sh` continua cobrindo os caminhos `bin/`, onde há log). O que o repo consegue observar do host-mode é a ÁRVORE, e o vigia já a vigia por drift a cada intervalo; anomalia de duração é o teto. Se o host um dia expuser log de Task, reabrir |

Baseline→teto (o agravante do incident): `arm --budget` transforma a
baseline dos critics anteriores em número — critics dos loops A/C/D
voltaram em minutos, então a janela do loop E teria teto de minutos e o
alarme soaria ~1h40 antes do dono.
