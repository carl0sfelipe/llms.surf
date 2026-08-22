# Dispatch Spec — como o dispatcher funciona

Extraído de `SKILL.md` (regras/fluxo) e `specs/free-model-ecosystem.md` (filosofia/catálogo), reformulado para ser agnóstico de CLI. Este documento descreve o núcleo (`core/` + `bin/`); adapters por CLI são F2+.

## Filosofia (de `specs/free-model-ecosystem.md` seção 1)

> O dispatcher não pergunta "qual modelo é melhor?". Pergunta "qual modelo é melhor *para esta tarefa específica, neste momento, considerando custo e disponibilidade*?"

Regra de ouro operacional (de `SKILL.md`): o orquestrador nunca escreve bulk output. Acima de ~20 linhas de output, despacha para um modelo free via `bin/dispatch.sh`.

## Papéis: orquestrador vs executor

Todo CLI pode assumir dois papéis (PRD seção 4.4):

- **orquestrador** — lê a skill, escreve specs curtas, chama `bin/dispatch.sh`.
- **executor** — o runner que efetivamente roda o modelo free, via `adapters/<cli>/runner.sh` (fora do escopo F1).

Hoje, opencode é o único CLI orquestrador+executor. Claude Code, Hermes e qwen code são orquestradores cujo executor default é opencode.

## Fluxo de trabalho (de `SKILL.md`)

Para features/código:

```
1. Investigar (grep/read/ls o repo)
2. Escrever spec grounded (10-30 linhas, caminhos exatos)
3. Checar quota: bin/pre-dispatch-check.sh <provider_id>
4. Smoke test do modelo: bin/smoke-test.sh
5. Despachar: bin/dispatch.sh <model_id> <spec_file>
6. Ler output
7. Verificar contra código real (grep/ls)
8. Se errado: despachar DELETE/REESCREVA/ADICIONE
9. Repetir 6-8 até correto
10. Commit + push
```

## Regras absolutas (de `SKILL.md`)

1. Nunca escrever bulk output — despachar para modelo free.
2. Ler + decidir + despachar; nunca reescrever refinamento manualmente.
3. Refinamento é DELETE/REESCREVA/ADICIONE — instruções, não reescrita direta.
4. Verificar contra código real antes de despachar (grep/ls/read).
5. 1 arquivo por story/tarefa — nunca monolítico.
6. Smoke test antes de todo dispatch.
7. Nunca timeout < 30min para free models — background sem timeout curto.
8. Nunca 2 agentes no mesmo `.git` em paralelo (RNF-07, lock file em `bin/dispatch.sh`).
9. Rate limit ≠ incapacidade — checar logs antes de escalar.
10. Fork precisa de session ID real — obtido via `bin/session-health.sh`, nunca inventado.
11. Checar quota antes de despachar — `bin/pre-dispatch-check.sh <provider_id>`.

## Seleção de modelo (de `specs/free-model-ecosystem.md` seções 3-5)

O dispatcher classifica a tarefa (`code`, `reasoning`, `text`, `vision`, `audio`, `agentic`, `creative`, `long_context`) e tamanho do prompt, consulta `model-registry.json`, e escolhe `free > token-plan > pago-barato`, com fallback em cascata (campo `fallback` de cada modelo) quando o exit code do runner indica rate-limit (`exit 2`).

A implementação do classificador automático (NLP) e do aprendizado contínuo por métricas está **fora do escopo desta reformulação** (PRD seção 3.2/10) — hoje a seleção é manual, feita pelo orquestrador ao ler `model-registry.json`.

## Scripts do núcleo (`bin/`)

| Script | Função |
|--------|--------|
| `bin/dispatch.sh` | Despacha em background via `$DISPATCH_RUNNER`, com lock anti-concorrência (RNF-07) |
| `bin/new-session.sh` | Cria sessão base, captura `session_id` (sem race condition) |
| `bin/smoke-test.sh` | Testa disponibilidade de um modelo antes de despachar |
| `bin/parallel-dispatch.sh` | Sequencia forks de uma sessão base |
| `bin/poll-status.sh` | Verifica status de uma task em background |
| `bin/decide-context.sh` | Decide REUSE/FORK/FRESH para uma sessão |
| `bin/pre-dispatch-check.sh` | Gate de quota via `ai-usage-hub` |
| `bin/session-health.sh` | Dashboard de sessões, tokens, rate limit |
| `bin/attach.sh` | Anexa TUI interativa na sessão de um worker |
| `bin/watch.sh` | Lista dispatches em background ou `tail -f` do log |
| `bin/ledger.sh` | Consulta o ledger permanente |
| `bin/ledger-finalize.sh` | Finaliza e grava métricas no ledger após um dispatch |

Todos parametrizados por env (`DISPATCH_RUNNER`, `DB_PATH`, `LOG_DIR`, `PID_DIR`, `MODEL_REGISTRY`, e as `ORACFIT_USAGE_*` do hub de uso built-in — `bin/usage-hub.py`) — ver `core/runner-contract.md` para o contrato do runner e cada script para sua env obrigatória específica. `AI_USAGE_HUB_URL` (daemon HTTP do ~/ai-usage-hub) deixou de existir na v3.5. `DISPATCH_CRITIC_PROFILE` (v3.5) troca a persona do critic nos dois call sites (gauntlet do mode e escalate): aceita caminho absoluto ou nome de arquivo em `core/critic-profiles/` (ex.: `architect-revisor-akita`); o contrato JSON do critic fica fora do perfil.

## Compatibilidade reversa

`scripts/` permanece congelado e funcional (regra 11.6 do PRD — implementador nunca altera `scripts/` legado). `bin/` é o substituto ativo; `scripts/` só é removido em fase futura, fora do escopo F1-F5.
