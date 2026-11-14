---
id: 2026-11-14-dogfood-semantype-13-sprints-via-adapter
titulo: dogfood semantype: 13 sprints via adapter cursor, o que funcionou e o que o framework nao viu
data: 2026-11-14
recorrivel: sim
regra: pendente
status: aberto
interage_com: [24, 31, 37, 39, 42, 49, 53]
---

# dogfood semantype: 13 sprints via adapter cursor, o que funcionou e o que o framework nao viu

Relato de uso real, 13–14/11/2026. Orquestrador: Claude Code. Executor:
`grok-4.6-xhigh-fast` pelo `adapters/cursor`. Repo alvo:
`~/Projects/github/semantype` (novo, criado na sessão). Entrega: site em
`type.llms.surf` e API em `semantype-api.llms.surf`, no ar.

## Sintoma

### O que funcionou (medido)

- **13 dispatches, 13 com exit 0 e oráculo verde na 1ª tentativa** (MVP +
  sprints 1–12). Durações do ledger (só as que entraram — ver abaixo):
  597, 244, 505, 249, 411, 286, 588 s.
- Os três portões (`check-spec.sh`, `check-spec-facts.py`, `check-oracle.py`)
  rodaram antes de **todo** dispatch e pegaram defeitos reais da spec antes de
  gastar token: seção `## Oráculo` numerada (`## 11. Oráculo`) não era
  reconhecida; spec com caractere CJK solto (duas vezes); `check-oracle`
  confirmou "falha pelo motivo certo" em todos os 13.
- O padrão **suíte do dono pinada por sha256** (`.owner-suites.sha256` +
  `bin/check-owner-suites.sh`, criado nesta sessão) funcionou: em 13 sprints o
  executor nunca alterou uma suíte do dono (21 suítes no fim).
- **Grep negativo no oráculo** (GPU/WebGPU/ONNX/rede/checkout) segurou o
  escopo: nenhuma sprint trouxe dependência proibida.

### O que o framework não viu

1. **Run invisível no painel.** `dispatch.sh` simples não emitia
   `run_started`/`run_finished` e o `ledger-finalize.sh` abortava por falta de
   `DB_PATH` (o adapter cursor não define). Resultado: o dono perguntou "cadê o
   painel" / "não vejo nenhuma run". O orquestrador escreveu à mão
   `events.jsonl`, hard links de log e entradas de ledger
   (`ledger_written_by: claude-code`). Das 13 runs, **só 7 entraram no
   ledger**; as sprints 7–12 ficaram fora.
2. **Painel velho na porta.** Havia um `oracfit-panel-server.py` de outro
   worktree (`llms.surf-wt-modes`) ocupando a 8765; o painel novo morria com
   `Address already in use` e o dono via o painel errado.
3. **Painel recusa symlink de log** fora do diretório do run; só hard link
   funcionou.
4. **Oráculo verde ≠ deploy vivo.** Sprint 7 passou no oráculo (vitest +
   build) e a API **caiu em produção**: parameter property em constructor
   (`ERR_UNSUPPORTED_TYPESCRIPT_SYNTAX` no `node --experimental-strip-types`).
   O vitest transpila com esbuild; o runtime de produção não.
5. **Oráculo verde ≠ produto seguro.** Com `API_KEY` vazia a API ficava em
   "modo aberto" — sem chave e com chave **errada** respondia 200. O defeito
   estava na spec escrita pelo orquestrador, e o oráculo media o que a spec
   pedia.
6. **Artefato de teste em produção.** Sprint 10 deixou 8 linhas
   `persist-*`/`modelo-de-teste` no board público (os testes do executor
   rodaram contra o Postgres real).
7. **Erros de operação do orquestrador** (fora do framework, mas no mesmo
   fluxo): `pkill -f apps/api/src/server.ts` no oráculo matou o serviço de
   produção (502); publicar o site sem reiniciar a API deixou `/v1/eval` em
   404 no túnel; hostname de dois níveis (`api.type.llms.surf`) sem certificado
   (`*.llms.surf` só cobre um nível) → TLS falhou.
8. **Model id envelhece.** Na sessão seguinte o cursor respondeu
   `Cannot use this model: grok-4.6-xhigh-fast` — o id do registry deixou de
   existir no provider sem o registry saber (regra 55).

## Causa

- (1) `bin/dispatch.sh` não chamava `oracfit_emit_event`; `ledger-finalize.sh`
  tinha `: "${DB_PATH:?...}"` com `set -e` — exit antes de escrever. Evidência:
  `ledger/ledger.jsonl` sem nenhuma linha `semantype-*` até a escrita manual.
- (2) `ss -ltnp | grep 8765` → pid do worktree `llms.surf-wt-modes`.
- (3) `_safe_log_file` faz `resolve()` + `relative_to(gauntlet)`: symlink
  resolve para fora e é recusado.
- (4)/(5)/(6) O oráculo mede o que o repo diz, não o processo rodando nem a
  política de segurança. A lição virou check: os oráculos das sprints 7+ sobem
  a API com o mesmo `node --experimental-strip-types` de produção, fazem `curl`
  e matam pelo PID.
- (8) não determinada no detalhe; sintoma é o da regra 55 (registry estático).

## Correção aplicada

- Repo alvo: `bin/check-owner-suites.sh` (copiado para
  `llms.surf/bin/check-owner-suites.sh`, ainda não commitado); oráculos que
  sobem o runtime real; `deploy/semantype-api.service` com `Restart=always`;
  `bin/publish.sh` reinicia site **e** API; `API_KEY` obrigatória no `.env`.
- Framework: segundo a memória do orquestrador, o rung 25 tornou `DB_PATH`
  opcional (finalizador lê a sessão do log) e o rung 26 fez o `dispatch.sh`
  simples emitir `run_started`/`run_finished`. **Não reverificado neste
  incidente** — conferir com um dispatch novo antes de fechar.
- Painel na porta ocupada, symlink recusado, ledger 7–12 faltando: **sem
  correção**.

## Pode acontecer de novo?

Sim. Três classes recorríveis:

1. **Run sem superfície** (painel/ledger cego para um caminho de dispatch) —
   família da 38 e da 53. Verificar que os rungs 25/26 cobrem o adapter
   cursor; o painel deveria recusar subir se a porta tiver outro workdir, e
   aceitar hard link/symlink do próprio `LOG_DIR`.
2. **Oráculo que não sobe o runtime de produção** — família 24/31. Candidata
   a regra: *"oráculo de serviço sobe o processo com o MESMO comando do
   systemd/produção e fala com ele por HTTP; teste unitário verde não fecha
   sprint de serviço."*
3. **Suíte do dono por hash** — o mecanismo funcionou e vale promover ao
   framework (`bin/check-owner-suites.sh` + passo no preflight).

Promover depois de reverificar os rungs 25/26:

    bin/incident.sh promote 2026-11-14-dogfood-semantype-13-sprints-via-adapter "<texto da regra 2>"
