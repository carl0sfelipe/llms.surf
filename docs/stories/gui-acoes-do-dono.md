# Story GUI-2 — "Ações do dono": todo "faça isto" de um agente vira um passo na GUI

Status: contrato (Opus) · implementação: Cursor · oráculo: `tests/test-gui-acoes.sh`
Depende de: GUI-1 (`docs/stories/gui-passo-a-passo.md`, PR #17).

## Problema
Os agentes terminam relatórios com "Ação sua: crie o OAuth App…, apague o CNAME…,
mergeie #18…". Isso some no chat. A GUI-1 só enxerga o estado do oracfit.
Queremos um **pipeline**: agente registra a ação → GUI mostra como passo → dono
marca feito → some.

## 1. Fonte: arquivo append-only
Caminho: flag `--owner-actions PATH` do servidor, senão env `ORACFIT_OWNER_ACTIONS`,
senão `~/.config/llms-surf/acoes-do-dono.jsonl`. Arquivo ausente = nenhuma ação
(não é erro). Uma linha JSON por evento:
```json
{"type":"add","id":"oauth-github","ts":"…","title":"…","plain":"≤140 chars",
 "why":"…","action":{"kind":"copy|link|none","label":"…","command":"…","href":"…"},
 "source":"quem pediu (ex.: opus/cloud C1)", "blocks":"o que destrava (opcional)"}
{"type":"done","id":"oauth-github","ts":"…"}
{"type":"snooze","id":"oauth-github","ts":"…","until":"<ISO>"}
```
Estado = replay em ordem: `add` com id repetido substitui; `done` fecha;
`snooze` esconde até `until`. Linha inválida é ignorada (sem derrubar a API).
`id` casa `^[a-z0-9][a-z0-9-]{0,63}$`.

## 2. CLI `oracfit acao`
- `oracfit acao add <id> --title T --plain P [--why W] [--command C | --href H] [--source S] [--blocks B]`
  → grava `add` (kind = copy se --command, link se --href, senão none). Recusa (exit 2,
  nada gravado) id inválido, title vazio, plain > 140.
- `oracfit acao done <id>` · `oracfit acao snooze <id> <horas>` (id inexistente/fechado → exit 2).
- `oracfit acao list [--json]` → abertas, mais antiga primeiro (TAB: id, idade, title).
Usa o mesmo caminho do §1 (env/flag `--file`).

## 3. Passo `dono` no `/api/gui/steps`
Nova ordem fixa: `modelos`, `dono`, `falhas`, `notas`, `despachar`, `pronto`.
- Sem ações abertas → `feito`. Com ações → `agora`/`depois` pela regra de GUI-1 (o
  primeiro não feito é o `agora`), com `item` = a ação aberta MAIS ANTIGA
  (`{id,title,plain,why,source,blocks,age_days}`), `remaining` = quantas abertas
  além dela, `title` do passo = title da ação, `plain` = plain da ação, e
  `action` = a da ação + `secondary: [{id:"feito",label:"Já fiz"},{id:"depois",label:"Me lembre amanhã"}]`.
- `POST /api/gui/acao {id, choice:"feito"|"depois"}` → grava `done` ou `snooze`
  (+24 h). 400 sem gravar se id não está aberto ou choice inválida. Mesma auth dos
  outros POSTs. Responde `{ok, next}`.

## 4. UI (passos.html)
Cartão do passo `dono`: título, frase, comando/botão da ação, e dois botões
grandes "Já fiz" (primário depois que o comando foi copiado ou o link aberto) e
"Me lembre amanhã". Mostra "pedido por <source>" e "destrava: <blocks>" como `.tech`
(some no Simplificar). Ajuste do GUI-1: no celular o botão Simplificar não
sobrepõe o título (cabeçalho em fluxo, não fixo, abaixo de 480px).

## 5. Pipeline (documento)
`docs/gui-pipeline.md`: como nasce um passo user-friendly —
(1) contrato em `docs/stories/` com o JSON do passo e frases ≤140 sem jargão;
(2) oráculo em `tests/test-gui-*.sh`; (3) implementação delegada; (4) revisão Opus
com screenshot desktop + 390px + modo Simplificar; (5) PR. E a regra: **todo
relatório de agente que pede algo ao dono roda `oracfit acao add`**.

## Regras
Python stdlib, JS vanilla, `esc()` em todo texto do arquivo. Não enfraquecer as
suítes existentes; a única mudança permitida em `tests/test-gui-passos.sh` é a
lista de ordem (inclui `dono`), já feita pelo Opus.
VERIFICACAO: `bash tests/test-gui-acoes.sh && bash tests/test-gui-passos.sh && bash tests/test-gui.sh && bash tests/test-gui-todo.sh && bash tests/test-gui-remote.sh`
