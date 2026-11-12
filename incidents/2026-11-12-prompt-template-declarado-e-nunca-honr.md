---
id: 2026-11-12-prompt-template-declarado-e-nunca-honr
titulo: prompt_template declarado no modo e nunca honrado pelo runtime
data: 2026-11-12
recorrivel: sim
regra: mecanismo aplicado
status: fechado
---

# prompt_template declarado no modo e nunca honrado pelo runtime

## Sintoma

Uma stage pode declarar o prompt que o modelo deveria receber, e o runtime
entregar a mesma spec de qualquer outra stage:

```yaml
# core/modes/vision_catalog.yaml
  - role: map
    prompt_template: vision_product_fields
  - role: reduce
    prompt_template: group_photos_write_store_assets
```

Quatro stages já vêm no repositório com o campo preenchido
(`vision_catalog` e `ui_visual_qa`). Os arquivos que elas nomeiam **não
existiam em lugar nenhum da árvore**, e mesmo assim o run seguia: o loader
aceitava o campo e ninguém lia. Não havia lugar no YAML do modo para dizer
ao modelo o que aquela stage tinha que fazer — o campo existia no papel.

## Causa

`prompt_template` entrou na gramática do modo como campo aceito
(`ALLOWED_STAGE` em `bin/lib-oracfit-mode-loader.py`) e como linha no
catálogo (`prompt_template: ...  # file with the prompt for this stage`),
mas **nenhum runtime o consumia**:

```console
$ grep -rn "prompt_template" bin/
bin/lib-oracfit-mode-loader.py:18:    "prompt_template", "json_schema", "artifacts", "max_attempts",
```

É o quarto caso da mesma classe: campo aceito pelo loader, sem consumidor
no runtime — depois de `input: prev_stage`
(`2026-11-12-input-prev-stage-declarado-e-nunca-consu`), `artifacts:`
(`2026-11-12-stage-que-declara-artifacts-e-nao-escrev`) e `rate_limit_s`
(`2026-11-12-rate-limit-s-declarado-e-nunca-honr`). A validação do loader
dava a impressão de que o campo valia alguma coisa — e não valia.

## Correção aplicada

- `bin/lib-oracfit-prompt-template.sh` (novo): o mecanismo. Resolve o
  arquivo (nome nu em `core/prompts/<nome>.md`, workdir primeiro, depois
  `ORACFIT_ROOT`; valor com `.md` ou `/` é caminho relativo ao workdir) e
  emite a seção `## Stage prompt (prompt_template: <nome>)` para a spec
  composta. Os dois runtimes importam esta lib — não há cópia da regra.
- `bin/dispatch-stages.sh` e `bin/dispatch-mode.sh`: os dois runtimes honram
  o campo. Arquivo presente → o conteúdo entra na spec logo depois do spec
  base e antes da cadeia de `input: prev_stage`, do ground truth e da
  mensagem do humano. Arquivo ausente → a stage falha com
  `PROMPT TEMPLATE NOT FOUND: <nome>` no stderr e no log do oráculo, antes
  de qualquer chamada ao modelo. Stage que não declara o campo não é
  afetada.
- `bin/lib-oracfit-mode-loader.py`: `prompt_template` tem que ser string
  não-vazia (como `stage_oracle`). O loader não conhece o workdir do
  usuário e não exige que o arquivo exista.
- `core/prompts/` (novo): os quatro templates que os modos de visão já
  declaravam, para o run desses modos não passar a reprovar na primeira
  stage.
- `tests/test-prompt-template.sh` (novo): o mecanismo. Prova que os dois
  runtimes injetam o arquivo na spec, que o arquivo ausente reprova a
  stage, que quem não declara não é penalizado, e que o loader recusa
  vazio ou não-string.
- `docs/modes-catalog.md` e `site/llms.txt`: a semântica escrita onde o
  agente lê.

## Pode acontecer de novo?

Sim, na mesma classe: **campo aceito pelo loader sem consumidor no
runtime**. O próximo da fila é `json_schema`, irmão deste campo no YAML
da stage. A regra 32 pelo outro lado — uma afirmação de que o modo entrega
um prompt precisa apontar para um mecanismo que lê o arquivo e o teste
prova o efeito, não a forma do YAML. Um teste que confirma
`stages[0].get("prompt_template") == "vision_product_fields"` não prova
nada sobre o que o modelo recebeu.
