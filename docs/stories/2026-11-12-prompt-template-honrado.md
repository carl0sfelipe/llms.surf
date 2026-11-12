# Honrar `prompt_template` no runtime do llms.surf

## Objetivo

Fazer o llms.surf **honrar** o campo `prompt_template` de uma stage: o
arquivo que a stage declara é lido pelo runtime e o conteúdo é entregue ao
modelo como o prompt daquela stage.

Hoje o campo é aceito pelo loader e **não tem consumidor nenhum**: uma stage
que declara `prompt_template: X` recebe exatamente a mesma spec de qualquer
outra stage — o runtime não sabe que o campo existe. Este é o quarto caso da
mesma classe (campo aceito pelo loader, sem gate no runtime), depois de
`input: prev_stage` (PR #38), `artifacts:` (PR #39) e `rate_limit_s` (PR #40).

O efeito prático: hoje **não existe lugar no YAML do modo para dizer ao
modelo o que aquela stage tem que fazer**. O `prompt_template` é esse lugar —
e ele precisa funcionar de verdade.

## Dados verificados

- `bin/lib-oracfit-mode-loader.py:18` — `"prompt_template"` está na lista
  `ALLOWED_STAGE` (campo aceito). O `validate()` não diz nada sobre ele.
- `grep -rn "prompt_template" bin/` — o único resultado é o loader. Nenhum
  runtime lê o campo.
- Quatro stages já declaram o campo, com nomes de arquivo que **não existem
  em lugar nenhum da árvore**:
  - `core/modes/vision_catalog.yaml:14` → `vision_product_fields`
  - `core/modes/vision_catalog.yaml:21` → `group_photos_write_store_assets`
  - `core/modes/ui_visual_qa.yaml:15` → `ui_visual_findings`
  - `core/modes/ui_visual_qa.yaml:22` → `merge_ui_findings`
- Onde a spec da stage é montada (o ponto de injeção):
  - multi-stage: `bin/dispatch-stages.sh:399-464` — `cat "$spec_file"`, depois
    `## Stage context (Oracfit multi-stage)`, depois a cadeia de
    `input: prev_stage`, depois o ground truth, o accum e a mensagem do
    humano.
  - stage única: `bin/dispatch-mode.sh:473-525` — ground truth, `artifacts:` e
    a mensagem do humano.
- `docs/modes-catalog.md:70` documenta o campo como
  `prompt_template: ...   # file with the prompt for this stage`.
- Regras do repositório (obrigatórias):
  - todo código novo **em inglês** (`bin/check-english.py` roda em CI);
  - `incidents/` em **português**;
  - os números do `README.md`, `site/app.js` e `site/llms.txt` derivam da
    árvore (`bin/check-docs.sh`, `tests/test-site-honesty.sh`) — hoje são
    **125 incidentes** e **52 suítes**;
  - o commit e a PR são do orquestrador: **não** commitar, **não** dar push,
    **não** abrir PR. Deixar as mudanças no workdir.

## Semântica decidida (não inventar outra)

1. `prompt_template: <nome>` significa: o prompt da stage vive no arquivo
   `<nome>.md`.
   - Se o valor já tiver extensão `.md` ou conter `/`, ele é um caminho
     relativo ao workdir.
   - Senão, resolver nesta ordem, primeira que existir vence:
     - `$ORACFIT_WORKDIR/core/prompts/<nome>.md`
     - `$ORACFIT_ROOT/core/prompts/<nome>.md`
2. **Arquivo ausente → a stage falha.** Mensagem no stderr e no log do
   oráculo: `PROMPT TEMPLATE NOT FOUND: <nome>`. Não é aviso: um prompt
   declarado e não entregue é uma promessa quebrada, e a stage reprova
   (mesma doutrina de `artifacts:` — ver
   `incidents/2026-11-12-stage-que-declara-artifacts-e-nao-escrev.md`).
3. **Arquivo presente → o conteúdo entra no spec da stage**, numa seção
   `## Stage prompt (prompt_template: <nome>)`, logo depois do spec base e
   **antes** da cadeia de `input: prev_stage`, do ground truth e da mensagem
   do humano.
4. **Loader**: `prompt_template` tem que ser string não-vazia (como
   `stage_oracle`). Nada além disso — o loader não conhece o workdir do
   usuário e não pode exigir que o arquivo exista.
5. **Criar os 4 templates** que os modos de visão já declaram, em
   `core/prompts/` (sem eles os 2 modos passariam a reprovar na primeira
   stage):
   - `core/prompts/vision_product_fields.md` — extrair, de cada foto de
     produto, os campos do produto (nome, marca, preço, categoria, sku...),
     um objeto JSON por foto.
   - `core/prompts/group_photos_write_store_assets.md` — agrupar os registros
     por produto e escrever os assets de loja prontos para publicar.
   - `core/prompts/ui_visual_findings.md` — findings visuais de storefront,
     um JSON por linha (JSONL), um por screenshot.
   - `core/prompts/merge_ui_findings.md` — mesclar os findings num relatório
     final.
   Cada template diz o que pedir ao modelo, o formato da saída e onde
   escrever. Texto curto e direto, sem placeholders vazios.
6. **Mecanismo**: `tests/test-prompt-template.sh` (novo) provando:
   - o runtime injeta o template no spec entregue ao runner;
   - template declarado e ausente → a stage falha com
     `PROMPT TEMPLATE NOT FOUND`;
   - stage que **não** declara `prompt_template` não é afetada;
   - os **dois** runtimes (multi-stage e stage única) honram o campo;
   - o loader recusa `prompt_template` vazio ou não-string.
7. **Docs**: `docs/modes-catalog.md` (parágrafo novo, no mesmo estilo dos
   parágrafos de `artifacts:` e `input: prev_stage`) e `site/llms.txt`
   (fato novo na lista "Six facts about a mode file").
8. **Incidente em português**:
   `incidents/2026-11-12-prompt-template-declarado-e-nunca-honr.md`,
   no formato dos outros incidentes (frontmatter + Sintoma / Causa /
   Correção aplicada / Pode acontecer de novo?).
9. **Contagens da árvore**: `README.md`, `site/app.js` (`DATA.stats`) e
   `site/llms.txt` — 125 → **126** incidentes e 52 → **53** suítes.
   `bin/check-docs.sh` e `tests/test-site-honesty.sh` têm que ficar verdes.
10. `json_schema` fica **fora** do escopo (campo irmão, próximo PR).

## Verificação

Antes de terminar, rodar e deixar tudo verde:

```bash
python3 bin/check-english.py
bash bin/check-docs.sh
bash tests/test-site-honesty.sh
bash tests/test-prompt-template.sh
git add -A   # o gate test-first-wave.sh copia só o que está no índice:
             # arquivo novo não staged quebra o "clone virgem"
git status --short
```

`git add -A` é obrigatório (não commitar): `tests/test-first-wave.sh` monta
uma cópia do repositório só com arquivos `git ls-files`, e um arquivo novo
fora do índice faz o `dispatch-mode.sh` daquela cópia dar erro de
`source` — foi exatamente assim que o `rate_limit_s` quebrou o clone virgem
no PR #40.

## Oráculo

- comando: test -f tests/test-prompt-template.sh && bash bin/check-saude.sh && for t in tests/test-*.sh; do bash "$t" >/tmp/oracfit-suite.log 2>&1 || { tail -30 /tmp/oracfit-suite.log; exit 1; }; done
- exit esperado: 0

## Barra

- nome: o mesmo dos PRs #38, #39 e #40 — a promessa tem que ser cumprida por
  um mecanismo que o teste prova, não por um campo que o loader aceita.

NUNCA use declare const como workaround — importe de verdade. Não invente
número, prazo ou fonte além dos listados acima.
