---
id: 2026-11-12-input-prev-stage-declarado-e-nunca-consu
titulo: input prev_stage declarado e nunca consumido pelo runtime
data: 2026-11-12
recorrivel: sim
regra: mecanismo aplicado
status: fechado
---

# input prev_stage declarado e nunca consumido pelo runtime

## Sintoma

O modo `unlock_plan` (alias `tow`) — o polo *elevate* do flywheel — declara
`input: prev_stage` em duas stages, e a stage `plan` continua produzindo um
plano como se não tivesse visto o `unlock`:

```yaml
# core/modes/unlock_plan.yaml
stages:
  - role: unlock
    model_ref: tier:expensive
  - role: plan
    model_ref: tier:mid
    input: prev_stage
  - role: run
    model_ref: tier:cheap
    input: prev_stage
```

A stage `plan` recebe uma spec composta que contém apenas o papel e o
`artifacts_dir` da própria stage:

```
## Stage context (Oracfit multi-stage)
- role: plan
- artifacts_dir: `.../artifacts/<run_id>/plan/`
```

Não há uma linha sequer do `unlock`: o desbloqueio caro foi comprado e o
plano não o lê. O mesmo vale para `examples/elevate.yaml`,
`examples/outside_set.yaml`, `core/modes/vision_catalog.yaml` e
`core/modes/ui_visual_qa.yaml`.

## Causa

O campo `input` era aceito pelo loader e documentado, mas **nenhum consumidor
existia**. No `HEAD` deste incidente:

```console
$ grep -rln "prev_stage" core/modes examples
core/modes/ui_visual_qa.yaml
core/modes/vision_catalog.yaml
core/modes/unlock_plan.yaml
examples/elevate.yaml
examples/outside_set.yaml

$ git show HEAD:bin/dispatch-stages.sh | grep -n "prev_stage"
(nenhuma linha com prev_stage em bin/dispatch-stages.sh no HEAD)
```

`bin/lib-oracfit-mode-loader.py` lista `input` em `ALLOWED_STAGE` (o campo é
legal) e `validate()` nunca o olha; `bin/dispatch-stages.sh` compunha a spec
com `role`, `artifacts_dir`, ground truth, feedback e a mensagem do humano —
e nenhuma vez com a saída da stage anterior. A spec composta só existia
quando havia feedback/ground truth/pergunta/inbox, de modo que mesmo o
esqueleto do encadeamento não estava no código.

A lição é a da regra 32 pelo outro lado: um campo aceito pelo loader e
declarado por 5 modos é uma promessa com corpo vazio. E o teste que existia
(`tests/test-priority-modes.sh`) só olhava a **forma** do YAML
(`d["stages"][1].get("input") == "prev_stage"`), nunca o **efeito** — por isso
o buraco sobreviveu a três leituras do catálogo.

## Correção aplicada

- `bin/lib-oracfit-stage-input.py` (novo): renderiza a saída de uma stage —
  a resposta que ela produziu e os arquivos que escreveu no `artifacts_dir` —
  como um bloco markdown, sem esconder o vazio (uma stage que não escreveu
  nada diz isso).
- `bin/dispatch-stages.sh`: lê `input` por stage; quando o valor é
  `prev_stage`, monta a cadeia com o que **cada stage que rodou** produziu
  (a cadeia é o estado do run, não a ordem do YAML: `loop_target` reexecuta
  stages), força a composição da spec mesmo num run limpo, injeta o bloco na
  spec e exporta `ORACFIT_PREV_STAGE_INPUT_FILE` /
  `ORACFIT_PREV_STAGE_ROLE` / `ORACFIT_PREV_STAGE_ARTIFACTS` para a stage
  mecânica — que roda comando e nunca lê a spec.
- `bin/lib-oracfit-mode-loader.py`: `validate()` recusa `input: prev_stage`
  na primeira stage (não existe stage anterior para ler) e recusa `input` que
  não seja string.
- `tests/test-stage-input.sh` (novo): o mecanismo. Prova que a stage que
  declara `input: prev_stage` recebe a resposta e os arquivos da anterior,
  que a stage que **não** declara não recebe nada, que a cadeia acumula
  (unlock → plan → run), que a stage mecânica recebe a cadeia pelo
  ambiente, que o loader recusa a primeira stage e que o helper diz quando
  não há saída.
- `docs/modes-catalog.md`: a semântica de `input` agora está escrita no
  catálogo, com os três nomes de ambiente.

## Pode acontecer de novo?

Sim, na mesma classe: **campo aceito pelo loader sem consumidor no runtime**.
A verificação é do tipo "o YAML declara e o runtime faz", e o teste novo é
justamente essa verificação, no nível do efeito (a spec que o runner recebeu)
e não do formato (o YAML). A lição geral: um teste que confirma a *forma* de
uma promessa não protege a promessa — só um teste que confirma o *efeito*
protege. E a cadeia, não a stage imediatamente anterior, é o que um
`prev_stage` promete: o `run` do `unlock_plan` precisa do `unlock` tanto
quanto do `plan`.
