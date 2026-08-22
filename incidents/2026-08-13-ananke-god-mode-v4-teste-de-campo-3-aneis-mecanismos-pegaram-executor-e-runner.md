---
id: 2026-08-13-ananke-god-mode-v4-teste-de-campo-3-aneis-mecanismos-pegaram-executor-e-runner
titulo: ANANKE (god mode v4) 3/3 anéis verdes em 13min — os mecanismos pegaram o executor mentindo E dois bugs do próprio runner no primeiro uso real
data: 2026-08-13
recorrivel: sim
regra: nao — 4 regras candidatas no corpo; 2 já viraram código na sessão
status: aberto
interage_com: "2026-08-13-ring-ledger-central-dividido-por-env-herdado-de-shell"
interage_com: "2026-08-13-ring-retest-nao-disparou-regex-sem-convencao-python"
interage_com: "2026-08-12-aion-god-mode-1-anel-com-mecanismo-real-mas-perpetuidade-morreu-com-a-sessao"
---

# ANANKE (god mode v4) — teste de campo da Fase 4

## FICHA TÉCNICA

| Campo | Valor |
|---|---|
| Modo (config) | ananke — `core/modes/ananke.yaml` (primeiro a passar `mode validate` E `mode lint`) |
| Alvo | `/tmp/ananke-field-1` (fifoq: fila FIFO limitada, sandbox criado para o campo; /tmp = efêmero, evidência durável no ledger central) |
| Substrato | HOST (Cursor/Fable) — prime-agent instalado (0.7.2) mas BLOQUEADO em `/login` (ação de dono); a espinha é agnóstica e foi exercitada pelo host |
| Duração / anéis | 13min01s de parede (`date` 00:11:17→00:24:18 -03) · 3/3 anéis fechados (teto do run) |
| Papéis | plan/build/notas: frontier host (contexto quente) · critic: SUBAGENT FRESCO por anel (A-1 e A-2 subagents novos; A-3 rounds 1–2 no mesmo subagent retido — espelho do `rlm(name=...)`) |
| Oráculo mecânico | `ring/oracle.sh` → `python3 -m unittest -q test_fifoq` (5→6→6 testes); runs por close: A-1 1x, A-2 2x (retest), A-3 1x |
| Quem pegou cada bug | ver tabela "sensores" abaixo — 4 achados por mecanismo, 3 por critic fresco, 0 por autoauditoria do executor |
| Ledger (contado via rg/python) | workdir: 7 linhas {open:3, close:3, close_attempt:1} · central: 10 linhas do run {open:3*, close:3, checkpoint_commit:3, close_attempt:1} (*1 backfilled — ver satélite do env) |
| Granularidade | 1 anel = 2 commits (build + checkpoint), 9 commits totais no alvo, árvore limpa no fim (`git status --porcelain` vazio) |
| Falhas de ambiente | disco real 6GB<10GB (preflight recusou o 1º open); browser MCP indisponível na sessão (fallback: `qlmanage` WebKit nativo); warn de identidade git (falso-positivo da regex `.local` no e-mail proposital `ananke@oracfit.local`) |
| Decisões autônomas | `min_disk_gb` 10→5 (commit `03106d2` + notas A-1, com pendência de dono); qlmanage como renderizador; backfill de 1 linha no central (documentado no satélite) |
| Custo | 4 chamadas de critic subagent (frontier, mesma classe do host); anéis mecânicos (open/close/preflight/gate) = 0 tokens |

## Contexto

Primeira execução real do v4 pós-implementação (Fases 1–3 da mesma sessão):
`oracfit ring open|close` com gates fail-closed, modo ananke, critic fresco
por anel gravando veredito em arquivo validado por `bin/check-verdict.py`.
Alvo sintético mas trabalho real: a fila foi implementada, criticada,
corrigida e instrumentada anel a anel. Resultado bruto: 3/3 anéis, oráculo
verde em todos os closes, 1 recusa visual medida, 1 REJECTED de critic
revertido por correção real, 2 bugs do runner achados e corrigidos.

## Sensores: quem pegou o quê (o eixo mecanismo×protocolo)

| Achado | Sensor | Classe |
|---|---|---|
| disco 6GB<10GB antes do 1º open | `ring-preflight.sh` via `ring open` | MECANISMO (recusou) |
| `FifoQueue(True)` passa (bool⊂int) | critic fresco A-1 (claims-check ao vivo) | PROTOCOLO julgando, canal mecânico |
| retest não disparou em `test_fifoq.py` | campo `oracle.runs=1` no ledger do close | MECANISMO (sensor) — ver satélite |
| notas do executor com fatos futuros no passado | critic fresco A-3 round 1 → REJECTED | PROTOCOLO julgando; `check-verdict.py` segurou o close |
| claim "histórico no git" falso (arquivo untracked) | critic fresco A-3 round 2 | PROTOCOLO julgando |
| close sem screenshot com diff tocando `*.html` | gate visual do `ring close` | MECANISMO (recusou, `close_attempt` no ledger) |
| ledger central dividido por env herdado | contagem workdir≠central no fechamento | MECANISMO (sensor) — ver satélite |

A autoauditoria do executor (eu) pegou ZERO dos sete — consistente com o
pythia ("autoauditoria no mesmo contexto é o elo fraco"). A diferença do
v4: nada dependia dela.

## O que funcionou (com evidência e contraprova)

1. **Veredito em arquivo + critic fresco pegou o executor inventando.**
   As notas de A-3 descreviam close_attempt e screenshot no PASSADO antes
   de existirem; o critic round 1 gravou REJECTED com dois CRITICAL e o
   `check-verdict.py` teria recusado o close (contraprova: no ouroboros o
   mesmo tipo de prosa passou 6 anéis sem contestação — era protocolo).
2. **Gate visual recusou de verdade**: `close_attempt reason=visual_sem_screenshot`
   no ledger; close só passou com PNG renderizado real (qlmanage, 56KB,
   conferido visualmente). Contraprova: autarca shipou 3 telas sem render.
3. **Teto e transação**: 3/3 anéis, tentativa de abrir 4º recusaria
   (provado na suíte T9); todo close deixou árvore limpa com ledger DENTRO
   do commit (satélite do aion fechado).
4. **Ledger como sensor do próprio runner**: `oracle.runs=1` num close que
   deveria ter retest expôs a regex furada minutos depois do fato — sem
   instrumentação seria invisível para sempre.

## Contraste com os irmãos

| | ouroboros | aion | autarca | pantocrator | **ananke (campo)** |
|---|---|---|---|---|---|
| proteções | protocolo | 1 script no workdir | cláusulas YAML | protocolo em comentário validado | **executáveis no core, lintados** |
| veredito | prosa | arquivo (contrato local) | prosa 2/3 | prosa estruturada | **arquivo validado fail-closed** |
| quem conta anéis | modelo | script | modelo | modelo | **ledger (open recusa no teto)** |
| executor mentiu e...? | passou | — | passou (números manuscritos) | — | **REJECTED no round 1** |
| bug do próprio runner | — | — | — | — | **2, achados pelo ledger no 1º uso** |

## O que quebrou / ficou frágil

1. **Retest descorrelacionado não disparou no A-1** — regex sem a convenção
   python `test_*.py`. MECANISMO APLICADO na sessão: `bin/oracfit-ring.sh`
   (regex) + `tests/test-ring-runner.sh` T14. Satélite próprio.
2. **Ledger central dividido** — `ORACFIT_CENTRAL_LEDGER` herdado de shell
   de smoke antiga desviou o open do A-1. MECANISMO APLICADO:
   `bin/oracfit-ring.sh` resolve o central do `state.json` (env só no init).
   Satélite próprio.
3. **Open recusado não deixa rastro no ledger** — a recusa por disco só
   existe no stdout da sessão. Candidata 1 abaixo.
4. **Round rejeitado do critic é sobrescrito** — o REJECTED do A-3 round 1
   só sobrevive porque o critic o descreveu no round 2; o arquivo foi
   sobrescrito antes do primeiro commit. Candidata 4 abaixo.
5. **Substrato prime-agent NÃO exercitado** — `/login` é do dono. O gate
   segurando término do `--autonomous` continua NÃO-MEDIDO
   (`adapters/prime-agent/DISCOVERY.md`). O campo provou a espinha com
   host; a perpetuidade fora de sessão segue promessa de contrato de CLI.

## Causa raiz (dos itens 1–2)

Gate condicional novo entrou em produção sem ter sido exercitado com dado
REAL do seu caso de disparo (regex nunca viu um `test_*.py`; resolução de
central nunca viu um shell com env sujo). A suíte da casa cobria o caminho
feliz de cada gate, não o gatilho na convenção do mundo real.

## Regras candidatas para a v4

CONVERGENTES (reforçam o já implementado):
- Preflight mecânico no open (classe 9) — disparou de verdade na primeira
  tentativa com disco real baixo. Mantém.

NOVAS (evidência desta sessão):
1. **`open` recusado grava evento `open_refused` no ledger** (workdir se
   possível, central sempre) — sintoma 3; custo ~10 linhas no runner.
2. **Recurso compartilhado resolve por STATE, nunca por env em runtime** —
   sintoma 2, já aplicado ao central; generalizar a auditoria para outros
   scripts do bin/ que leem env ambiente em runtime. Custo: grep + revisão.
3. **Todo gate condicional grava no ledger se disparou ou não** — sintoma 1
   (o campo `oracle.runs` foi o sensor; `visual` já grava nota). Custo:
   campos extras no evento close.
4. **Rounds do critic preservados** — copiar `verdicts/<RING>.json` para
   `verdicts/<RING>.round<N>.json` antes de sobrescrever, ou evento
   `verdict_round` no ledger. Sintoma 4; custo ~5 linhas.

## Evidência preservada

- Ledger central (durável): `rg 'ananke-20260813-0011' ledger/ledger.jsonl`
  → 10 linhas (3 open, 3 close, 3 checkpoint_commit, 1 close_attempt).
- Alvo: `/tmp/ananke-field-1` (efêmero até reboot) — git log com 9 commits,
  `fc6686d` (checkpoint A-3) o último; árvore limpa.
- Vereditos com biggest_gap reais: transcritos nos eventos close do ledger
  central (o campo viaja no evento — legível sem o /tmp).
- Screenshot: `ring/screens/A-3/status.html.png` (56.903 bytes, qlmanage),
  commitado no checkpoint A-3 do alvo.
- Suíte pós-correções: `tests/test-ring-runner.sh` → 29 PASS, 0 FAIL.

## O que este incident PROVA pra v4

1. A dupla canal-mecânico + julgamento-fresco funciona NO CAMPO: o critic
   pegou invenção de prosa do executor e a máquina teria segurado o close —
   a falha que definiu ouroboros/autarca não passa mais em silêncio.
2. Instrumentação mecânica paga a si mesma: os dois bugs do próprio runner
   foram achados pelo LEDGER que o runner escreve, no primeiro uso real.
3. Proteção nova SEM teste de campo é promessa: 2 de ~8 gates novos
   falharam no primeiro contato com o mundo (e nenhum dos dois apareceu na
   suíte sintética que os cobria).

## Pode acontecer de novo?

Sim, nas duas formas: (a) próximo gate condicional novo sem sensor de
disparo no ledger repete o sintoma 1 em silêncio; (b) qualquer script do
bin/ que resolva recurso compartilhado por env ambiente em runtime repete
o split-brain do sintoma 2. As candidatas 1–3 fecham as duas rotas;
promover é decisão de dono.
