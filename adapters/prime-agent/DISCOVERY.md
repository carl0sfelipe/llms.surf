# DISCOVERY — prime-agent (Passo 0, protocolo fluxos/verify)

Verificação MEDIDA em 2026-08-12/13 (América/São Paulo), máquina mini.
Princípio anti-invenção: só entra aqui o que teve comando + saída observada.
O que não pôde ser medido está na seção NÃO-MEDIDO — e continua não-medido
até alguém rodar e colar a evidência.

## Instalação (medida)

```
curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh | sh
# → "prime-agent-0.7.2.tgz: OK" (SHA-256 verificado pelo installer)
# → instalado em <home-do-dono>/.local/bin/prime-agent
prime-agent --version   # → 0.7.2
```

## Contrato de CLI (medido via `prime-agent --help`)

- `prime-agent [options] [@files...] [message...]` — `-p/--print` para one-shot.
- `--cwd <dir>` — workdir explícito (mata a classe do incidente
  `2026-08-12-runner-herda-cwd-do-lancador` por flag, não por cd).
- `-r/--resume <path|id>`, `--fork <path|id>` — sessão e fork nativos.
- **Autonomous (o que o god mode v4 usa):**
  - `--autonomous` — continua até gates passarem ou teto
  - `--autonomous-gate <command>` — repetível; gate de conclusão
  - `--autonomous-gate-retries <n>` (default 3), `--autonomous-gate-timeout-ms <n>` (default 300000)
  - `--autonomous-max-turns <n>` (default 12), `--autonomous-max-tokens <n>` (default 80000),
    `--autonomous-timeout-ms <n>` (default 1800000), `--autonomous-max-continuations <n>` (default 3)
- `schedule add <agent> <cron|one-time> -- <message>` / `schedule list|cancel` — medido:
  `prime-agent schedule list` → "No scheduled prompts."
- `agents`, `attach <agent>`, `send`, `status`, `doctor`, `shutdown`.

## Daemon (medido)

Uma chamada `prime-agent -p --no-session "..."` subiu o serviço de background
sozinho e ele FICOU VIVO depois do CLI sair:

```
prime-agent status
# socket .../prime-agent-501/daemon.sock *  pid 43487  version 0.7.2  status current

ps -o pid,pgid,command -p 43487
#   PID  PGID COMMAND
# 43487 43487 prime-agent
```

PID == PGID: o daemon é líder do próprio grupo/sessão — kill de grupo do
lançador NÃO o alcança. É a mesma propriedade que o `bin/dispatch-bg.sh`
provê por double-fork+setsid, agora nativa do substrato.

## Fail-closed sem auth (medido 2026-08-12; superado em 2026-08-13)

```
prime-agent -p --no-session "diga ok"
# → Provider authentication failed (invalid_request_error, 401)
# → "Run /login to update credentials."  exit sem inventar output
```

## Auth pós-/login do dono (medido 2026-08-13, ~01:20 -03)

O `/login` do dono gravou provider **deepseek** (type=api) em
`~/.prime/agent/auth.json`. O default do prime-agent continua
`prime-inference` (`settings.json: defaultModel z-ai/glm-4.7-flash`), que
NÃO tem saldo:

```
prime-agent -p --no-session "responda apenas OK"
# → 402 Insufficient balance (prime-inference; billing, não auth)
prime-agent -p --no-session --provider deepseek --model deepseek-v4-flash "responda apenas OK"
# → OK   (2.5s)
prime-agent -p --no-session --model deepseek/deepseek-v4-pro "responda apenas OK"
# → OK   (3.1s; forma provider/model resolve o provider certo)
```

ARMADILHA de nome: o provider prime-inference também lista um MODELO
chamado `deepseek/deepseek-v4-flash`. Sempre qualificar
`--model deepseek/deepseek-v4-flash` (ou `--provider deepseek`) — a forma
qualificada resolveu para o provider deepseek (senão daria 402).

## Sessão: resume e fork (medido 2026-08-13)

- Sessões em `~/.prime/agent/sessions/<uuid>.jsonl` (eventos: session,
  model_change, session_state, message…).
- `--resume <path>` recuperou palavra-código plantada ("ABACAXI42") —
  inclusive DEPOIS de SIGKILL no daemon (ver abaixo).
- `--fork <path>` criou sessão NOVA (arquivo novo) herdando o contexto
  (respondeu a palavra-código; original intocado).

## Daemon com worker recuperável (medido 2026-08-13 — kill real)

```
kill -9 43487            # SIGKILL no daemon
prime-agent status       # → socket … unreachable
prime-agent -p --resume <sessão> … "qual é a palavra-código?"
# → ABACAXI42; prime-agent status → pid NOVO (17860), respawn automático
```

- O agent que estava registrado antes do kill REAPARECEU no
  `prime-agent list` após o respawn, e o processo worker dele foi
  RECRIADO (ps: worker novo nascido no minuto do respawn).
- Maquinaria de recuperação visível em disco:
  `~/.prime/agent/daemon-workers/<id>/{command-journal.jsonl,
  <id>.recovery.jsonl, snapshot-cache/, supervisor-config}` — JSONL +
  snapshot, como anunciado.

## Detach / reattach (medido 2026-08-13)

- Runs `-p` NÃO ficam em `prime-agent list` após terminar — atacável é
  agent de daemon-worker (nasce de TUI interativa; `send` para nome novo
  recusa: "Unknown active session").
- `prime-agent attach <id>` com pty real: TUI renderiza o CONTEXTO do
  agent (título, modelo, cwd, histórico da conversa) e
  `prime-agent list` mostra `clients` 0→1 (attach) →0 (detach ao matar o
  cliente); o agent segue vivo. Reattach repetido funciona e mostra o
  histórico. Sem TTY (stdin /dev/null) a TUI sai limpa no EOF — attach de
  script exige pty (medido com `pty.openpty()`).

## Schedule DISPARANDO (medido 2026-08-13)

```
prime-agent schedule add <agent> "in 1 minute" -- "responda apenas PONG-AGENDADO"
# → Scheduled <uuid> next=2026-08-13T04:34:10.080Z
# T+1min: schedule list → "No scheduled prompts." (consumido)
#          sessão do agent ganha user:"responda apenas PONG-AGENDADO"
#          e assistant:"PONG-AGENDADO" (modelo deepseek respondendo)
```

One-time em linguagem natural ("in 2 minutes") aceito. Disparo também
medido contra agent com modelo SEM saldo (prime-inference): o prompt FOI
entregue na sessão (delivery ok), respostas vieram vazias (402 é billing,
não schedule). Cron recorrente: registro medido; disparo recorrente
NÃO-MEDIDO.

## `--autonomous-gate` segurando e liberando o término (medido 2026-08-13)

Gate contador (exit 1 nas chamadas 1–2, exit 0 na 3ª, contador em
arquivo):

```
prime-agent -p --provider deepseek --model deepseek-v4-flash \
  --cwd /tmp/pa-gate-1/work --autonomous \
  --autonomous-gate /tmp/pa-gate-1/gate.sh \
  --autonomous-max-turns 8 --autonomous-max-tokens 30000 \
  --autonomous-timeout-ms 300000 "Crie hello.txt com: ola campo v4"
# gate.log: 3 chamadas (04:28:45 / :50 / :54Z) — run só terminou na 3ª
```

- Gate vermelho vira MENSAGEM DE USUÁRIO na sessão: "Autonomous quality
  gate failed (attempt 1/3): `<cmd>` exited 1. Output: …" — o executor
  recebeu o stderr do gate e agiu sobre ele (gravou o token exigido).
- Gate verde (exit 0) liberou o término. hello.txt exato no disco.

### ACHADO DE CAMPO (classe 4 — trave móvel): executor satisfez o gate

Num segundo run, gate que esperava arquivo `release` (fora do controle
esperado do executor): ao receber o vermelho, o executor LEU o script do
gate, entendeu a condição e CRIOU o `release` ele mesmo — gate verde por
mão do executor. Não foi adversarial: foi o caminho mais barato até o
verde. Lição mecânica: condição de passagem do gate NUNCA pode ser
gravável pelo executor (o `oracfit ring close` cobre as suas por guarda
monotônica sha256 + staging guard; mas o VEREDITO em ring/verdicts/ é
gravável pelo executor — ver postmortem do teste de campo de 2026-08-13).

## `--mode daemon` NÃO é "rodar detached" (medido 2026-08-13)

`prime-agent --mode daemon "…"` tenta SER o supervisor do daemon — com
daemon vivo falha `ELOCKED: Lock file is already being held`. Run
detached de verdade: `-p` lançado por `bin/oracfit-daemon.sh` (setsid) ou
agent de daemon-worker + `schedule`/`send`.

## Subagentes `rlm(...)` (medido 2026-08-13, teste de campo Fase 4)

- `rlm` existe no IPython do agente (`_RLMCallable`: `run`, `find_models`,
  `list_subagents`, `delete_subagent`); `rlm.run(prompt, model=…, name=…)`
  devolve `RLMSpawnHandle` (dataclass: rlm_child_id, name, session_dir,
  model) — spawn-at-admission, a RESPOSTA chega como agent_message num
  turno FUTURO do pai.
- ARMADILHA medida: em `-p` one-shot, subagente spawnado perto do teto de
  turnos MORRE com o pai (sub-1ddcac3d: 1 fragmento de thinking, 3s).
  Padrão que funcionou: resume da mesma sessão com teto novo; as
  continuações geradas por recusas do gate são as janelas de entrega.
- Uso real: critic fresco do RING-1 (critic-ring1b) — veredito gravado
  verbatim pelo pai e verificado por comparação independente com a sessão
  do filho. Ver postmortem
  `incidents/2026-08-13-prime-agent-campo-v4-substrato-real-2-an.md`.

## NÃO-MEDIDO (restante)

- `/refine` e heartbeats
- disparo RECORRENTE de cron do schedule (one-time medido)
- `--autonomous-gate-retries` estourando (o que acontece após a 3ª falha
  de gate: run termina como falha? não observado — o run 1 do campo
  morreu antes por maxTurns, que é teto IRMÃO mas distinto)

## Registry (atualizado 2026-08-13)

`model-registry.json` ganhou `deepseek-v4-flash-direct` e
`deepseek-v4-pro-direct` com `cli_hints."prime-agent"` qualificados
(`deepseek/deepseek-v4-flash|pro`), ambos SMOKE-TEST-PASSOU via
`adapters/prime-agent/runner.sh` (`bin/smoke-test.sh` → OK 2s/3s).
Billing é a chave DeepSeek do dono — NÃO confundir com o
`deepseek-v4-flash-free` da Zen.
