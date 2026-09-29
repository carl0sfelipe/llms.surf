# Story GUI-1 — "Passo a passo": a GUI diz a próxima coisa a fazer, uma por vez

Status: contrato (Opus) · implementação: Cursor · oráculo: `tests/test-gui-passos.sh`

## Problema (visto rodando em 2026-09-29)
A GUI (`oracfit gui`) é bonita mas é um painel de observação: 9 páginas, jargão
(anel, ledger, escalate), e nenhuma diz "faça isto agora". Bugs de campo:
- B1 `bin/oracfit-gui.sh` rodado de dentro do repo morre com
  `cannot resolve Oracfit root` se não existe `~/.oracfit/current`.
- B2 toda página chama `/api/rings`, que dá 404 sem `--target` (erro no console).
- B3 linhas de escalate mostram `tier=None attempt=None`, modelo `?`, `— · —`.
- B4 `tests/test-gui-todo.sh` falha em "gui.css não servido".
- B5 `/favicon.ico` 404.

## O que entra

### 1. `GET /api/gui/steps` (em `bin/oracfit-panel-server.py`)
Calcula os passos a partir do estado REAL (ledgers, registry, alvo). Resposta:
```json
{"ok": true, "current": "falhas", "total": 4, "position": 2,
 "steps": [{"id": "modelos", "state": "feito|agora|depois|pulado",
            "title": "...", "plain": "1 frase, ≤140 chars, sem jargão",
            "why": "1–2 frases", "action": {...}}]}
```
Ordem FIXA dos ids: `modelos`, `falhas`, `notas`, `despachar`, `pronto`.
Exatamente UM passo tem `state == "agora"` (o primeiro não feito e não pulado);
`current` é o id dele; `position` = índice 1-based dele entre os não pulados;
`total` = nº de passos não pulados.

- `modelos` — feito se `model-registry.json` tem ≥1 modelo não aposentado
  (sem `retired: true` e `id_status` sem `APOSENTADO`). Senão `agora` com
  `action {kind:"copy", label:"Copiar comando", command:"oracfit models"}`.
- `falhas` — runs que falharam (as 3 fontes já normalizadas por
  `normalize_dispatch`: status falhou; falha cuja task tem run PASSADO mais
  recente não conta) e SEM decisão em
  `<logs-dir>/decisions.jsonl`. Nenhum → `feito`. Se houver: `agora`, com
  `item: {run_key, task, when, why_failed}` do MAIS RECENTE e
  `remaining` (quantas faltam), e
  `action {kind:"choice", options:[{id,label,hint,recommended}]}` com ids
  exatamente `tentar-de-novo`, `eu-faco`, `descartar`; só `tentar-de-novo`
  tem `recommended: true`. `run_key` = string estável por run
  (`<source>:<task>:<started_at|ts>`).
- `notas` — sem `--ring-target` → `pulado`. Com alvo: `to_score > 0` → `agora`
  com `action {kind:"link", label:"Dar notas agora", href:"hitl.html"}`;
  senão `feito`.
- `despachar` — specs `.md` sob `<workdir>/docs/**/specs/` e
  `<workdir>/.dispatch/specs/` cuja task (nome do arquivo sem `.md`) NÃO tem
  run passado nos ledgers. Nenhuma → `feito`. Com specs: `agora`, com
  `specs: [{path (relativo ao workdir), task}]` (retentadas por decisão
  `tentar-de-novo` vêm primeiro) e:
  - dispatch ligado → `action {kind:"post", label:"Despachar", endpoint:"/api/dispatch",
    payload:{mode:"normal", adapter:"opencode", spec, task}}` (1ª spec);
  - dispatch desligado → `action {kind:"copy", label:"Copiar comando",
    command:"oracfit run normal <spec> <task>"}`.
- `pronto` — `agora` só quando todos os outros estão feito/pulado:
  "Tudo em dia." `action {kind:"none"}`. Caso contrário `depois`.

### 2. `POST /api/gui/decide` `{run_key, choice}`
Grava 1 linha `{"ts","run_key","choice"}` em `<logs-dir>/decisions.jsonl` e
responde `{ok:true, next:<id do passo agora depois da decisão>}`.
400 (sem gravar nada) se `choice` fora dos 3 ids, se `run_key` não é uma falha
existente sem decisão, ou corpo inválido. Mesma regra de auth dos outros POSTs.
Não despacha nada sozinho.

### 3. Página `panel/passos.html` (e `/` serve ela)
- `<main id="passos">`. Topo: "Passo 2 de 4" + barra de progresso.
- UM cartão grande: título, frase simples, e a ação:
  - choice → 3 botões grandes (`button.option`, o recomendado com selo
    "recomendado" e foco inicial); clique → POST decide → recarrega passos e
    mostra aviso curto "Feito. Agora: <título do próximo>" (`role="status"`).
  - copy → comando em `<code>` + botão Copiar (clipboard; fallback: seleciona).
  - post → botão Despachar; resposta de erro aparece em texto legível.
  - link → botão que navega.
- "Por quê?" em `<details>`. Passos feitos: linhas ✓ recolhidas; `depois`: cinza.
- Enter aciona a ação principal. Atualiza a cada 15 s sem perder foco.

### 4. Botão "Simplificar" (em TODAS as páginas, via `gui.js`)
- `button#simplify` fixo no topo, `aria-pressed`, rótulo alterna
  "Simplificar" ↔ "Mostrar detalhes". Estado em `localStorage["oracfit.simple"]`
  (try/catch; sem storage funciona com default desligado).
- `body.simple`: esconde `.tech` (caminhos, runner=, oracle=, ids), a barra
  lateral, os tiles de telemetria, o glossário e o `<details>` "Por quê?";
  em passos.html mostra só o cartão do passo atual com fonte maior.
- Sidebar: novo 1º item "Passo a passo" (grupo Agir). A home ("Agora") ganha
  no lead um botão para passos.html.

### 5. Bugs B1–B5
- B1: `oracfit_resolve_root` cai para o repo do próprio script (`$SCRIPT_DIR/..`
  se tiver `panel/` e `bin/oracfit`) antes de falhar.
- B2: gui.js lê a contagem de notas de `/api/gui/steps` (ou `/api/gui/home`),
  nunca de `/api/rings` sem alvo.
- B3: null/None vira omissão (não imprime `tier=None`, `?`, `— · —`).
- B4: faça `test-gui-todo.sh` passar sem enfraquecer a asserção.
- B5: `<link rel="icon">` apontando para um favicon servido pelo painel.

## Regras
- Python stdlib, JS/CSS vanilla, sem build, sem CDN novo. Segue `esc()` para
  todo texto vindo do estado. Estilo e tokens de `panel/gui.css`.
- Não alterar asserções existentes das suítes GUI (só B4 conforme dito).
- VERIFICACAO: `bash tests/test-gui-passos.sh && bash tests/test-gui.sh && bash tests/test-gui-todo.sh && bash tests/test-gui-remote.sh`
