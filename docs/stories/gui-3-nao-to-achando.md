# Story GUI-3 — cartão que leva pela mão: micro-passos, data e "Não tô achando" (print → IA)

Status: contrato (Opus) · implementação: Cursor · oráculo: `tests/test-gui-ajuda.sh`
Depende de: GUI-2 (`docs/stories/gui-acoes-do-dono.md`).

## Feedback do dono (2026-09-29, TDAH alto)
- "A primeira coisa que eu vi foi 'Abra a Cloudflare' — cadê o link?" → todo cartão
  que manda abrir algo TEM que ter o link direto para a tela exata.
- Um cartão pode precisar de link E de texto para copiar (DNS); o v1 proíbe.
- "Tem que ter a data que foi gerado o script, pra eu ter certeza que é o da vez
  e foi gerado com contexto atualizado, ou se é velho."
- "Ideal: opção 'não tô achando', colo um print e o servidor responde a partir do print."

## 1. Ação v2 (retrocompatível com v1)
Linha `add` ganha campos opcionais:
- `steps: [{text, href?, copy?}]` — micro-passos (≤ 6), cada `text` ≤ 90 chars.
- `artifact: "<caminho absoluto>"` e `context: ["<caminho>", …]` — o que foi gerado e
  de que arquivos dependeu.
- `priority: "alta"|"normal"` (default normal).
- `decision: true` — cartão de decisão (único caso em que ação sem link/cópia/steps vale).
CLI `oracfit acao add` ganha: `--step "texto[|href=URL][|copy=TEXTO]"` (repetível),
`--artifact P`, `--context P` (repetível), `--prioridade alta|normal`, `--decisao`,
e passa a aceitar `--href` junto com `--command`. Recusa (exit 2, nada gravado):
ação sem `--href`, `--command`, `--step` e sem `--decisao`; step com text > 90;
mais de 6 steps; href que não começa com `https://` ou `http://127.0.0.1`/`http://localhost`.

## 2. Ordem
Abertas ordenadas por `priority` (alta primeiro) e depois pela mais antiga.

## 3. `/api/gui/steps` — passo `dono` expõe
`item.asked_at` (ISO do add) e `item.asked_ago` ("há 2 h", "há 3 dias", pt-BR);
`item.steps` (lista acima, `[]` se v1); `action` com `href` e/ou `command` quando
existirem; e, se houver `artifact`:
`item.artifact = {path, exists, generated_at, generated_ago, status}` onde
`status` = `"sumiu"` (não existe) · `"velho"` (algum `context` modificado DEPOIS do
artifact, e então `item.artifact.stale_because = "<caminho do context mais novo>"`) ·
`"ok"`. (Datas = mtime do arquivo.)

## 4. `POST /api/gui/ajuda` — "Não tô achando"
Corpo: `{id, image: "data:image/png|jpeg;base64,…", note?}` (imagem ≤ 4 MB).
- 400 sem gravar: id não aberto, imagem ausente/inválida/grande demais.
- Chama o modelo de visão OpenAI-compatível em `ORACFIT_VISION_URL`
  (default `http://127.0.0.1:8000/v1`) com `ORACFIT_VISION_MODEL`
  (default `gemma-4-12b`), `max_tokens` 300, timeout 60 s. Prompt de sistema:
  o dono tem TDAH; responda em pt-BR, no máximo 3 frases numeradas curtas, dizendo
  ONDE clicar no print (posição + texto do botão); se o print não é a tela certa,
  diga qual abrir (use o link da ação). Mensagem do usuário: título, plain, steps,
  why e href da ação + `note` + a imagem.
- Grava `<logs-dir>/ajuda/<ts>-<id>.png|jpg` + `<ts>-<id>.json` (pergunta, resposta,
  modelo, duração) e 1 linha em `<logs-dir>/ajuda.jsonl`. (Regra do dono: toda falha
  de uso vira incidente — esse log é a evidência.)
- 200 `{ok:true, answer, model, seconds}`. Modelo fora/timeout → 502
  `{ok:false, error:"<mensagem em português, sem stack>"}` — MAS o print e a nota
  ficam gravados mesmo assim (o dono já fez o esforço).

## 5. UI (passos.html, cartão do dono)
- Topo do cartão: "pedido há 2 h · 29/09 19:51" (`.tech` some no Simplificar? NÃO —
  data fica visível sempre, pequena). Se `artifact`: selo verde "gerado há 10 min",
  laranja "VELHO — mudou <arquivo> depois", ou vermelho "arquivo sumiu".
- Micro-passos: mostra UM por vez ("1 de 3"), com o link como botão grande "Abrir"
  (nova aba) e/ou "Copiar"; "Próximo" avança; o último passo mostra "Já fiz".
- Link e Copiar lado a lado quando a ação tem os dois.
- Botão sempre visível "Não tô achando": abre área para colar print (Ctrl+V na
  página inteira), arrastar ou escolher arquivo, + campo opcional "o que você vê?";
  "Enviar" mostra "olhando seu print…" e depois a resposta em letra grande, com
  "Resolveu" (fecha) e "Ainda não" (manda outro print). Funciona no celular
  (input file com `accept="image/*"` e `capture` opcional).

## 6. Conteúdo
`docs/gui-pipeline.md` ganha a regra: cartão que manda abrir algo tem link direto
(deep link da tela exata); se gerou arquivo, passa `--artifact` e `--context`.

## Regras
Python stdlib (urllib para o modelo), JS vanilla, `esc()` em tudo. Não enfraquecer
suítes existentes. Teste NUNCA chama modelo real (servidor fake).
VERIFICACAO: `bash tests/test-gui-ajuda.sh && bash tests/test-gui-acoes.sh && bash tests/test-gui-passos.sh && bash tests/test-gui.sh && bash tests/test-gui-todo.sh && bash tests/test-gui-remote.sh`
