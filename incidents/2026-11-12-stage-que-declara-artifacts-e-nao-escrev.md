---
id: 2026-11-12-stage-que-declara-artifacts-e-nao-escrev
titulo: stage que declara artifacts e nao escreve nada passa como verde
data: 2026-11-12
recorrivel: sim
regra: mecanismo aplicado
status: fechado
---

# stage que declara artifacts e nao escreve nada passa como verde

## Sintoma

O `unlock_plan` (alias `tow`) declara onde cada stage deve escrever:

```yaml
# core/modes/unlock_plan.yaml
  - role: unlock
    model_ref: tier:expensive
    artifacts: unlock/
  - role: plan
    model_ref: tier:mid
    input: prev_stage
    artifacts: plan/
```

A stage `plan` **não tem oráculo** (`oracle` ausente) e mesmo assim o run
passava com a stage do `plan` inteiramente vazia: ninguém olhava o diretório
`plan/`, e o stage seguinte (`run`) recebia a cadeia com o texto
"(the previous stage wrote no output)" e seguia como se nada tivesse
acontecido. Um `tow` que não produz plano nenhum era um `tow` verde.

## Causa

`artifacts:` era aceito pelo loader, o runtime criava o diretório e o
entregava ao modelo — e **ninguém lia**. A mesma classe do
`input: prev_stage` declarado e nunca consumido (incidente
`2026-11-12-input-prev-stage-declarado-e-nunca-consu`):

```console
$ grep -rn "artifacts" bin/dispatch-stages.sh bin/dispatch-mode.sh | grep -c find
0
```

O `dispatch-stages.sh` criava `art_dir` e exportava `ORACFIT_STAGE_ARTIFACTS`,
mas o gate do stage era só o `stage_oracle` e o oráculo da spec — e a
spec nunca menciona o diretório de artifacts. Já o `dispatch-mode.sh`
(stage único) ignorava o campo por completo: nem criava o diretório, nem
exportava nada, nem avisava o modelo.

O ponto cego era o mesmo do `plan`: uma stage **sem oráculo** só tem uma
prova de que trabalhou — o que ela escreveu. Sem gate sobre essa prova, a
stage "passa" por ter rodado.

## Correção aplicada

- `bin/dispatch-stages.sh`: uma stage que declara `artifacts:` precisa deixar
  pelo menos um arquivo não-vazio no diretório. O gate é determinístico e
  roda **antes** do oráculo da spec (como o `stage_oracle`); o motivo vai
  para o log do oráculo (o próximo attempt recebe como feedback) e para o
  stderr (o operador vê na hora). A spec composta passa a dizer ao modelo
  onde é a diretório e que ele tem que escrever algo lá.
- `bin/dispatch-mode.sh`: a mesma promessa no runtime de stage único — o
  diretório é criado, `ORACFIT_STAGE_ARTIFACTS` é exportado, o modelo é
  avisado, e a stage que não escreve falha. O recheck final (o "oráculo
  verde no disco no fechamento") não pode virar um run fail em pass: com o
  artefato ainda vazio, o run segue fail.
- `tests/test-stage-artifacts.sh` (novo): o mecanismo. Prova que a stage que
  declara `artifacts:` e não escreve falha (multi-stage e stage único), que
  quem escreve passa, que quem não declara nada não é penalizado, que o
  modelo é avisado do diretório, e que a stage **retenta** até o artefato
  existir (2 tentativas).
- `docs/modes-catalog.md` e `site/llms.txt`: a semântica escrita onde o
  agente lê.

## Pode acontecer de novo?

Sim, na mesma classe: **campo aceito pelo loader sem gate no runtime**. A
regra que fecha a classe é a da regra 32 pelo outro lado — um campo que o
runtime honra precisa de um gate que o prove. Um teste que confirma a
*forma* do YAML (`stages[0].get("artifacts") == "proof/"`) não prova nada
sobre o que aconteceu no disco; só um gate que lê o diretório prova. E a
lição do `plan` do `tow`: uma stage sem oráculo é uma stage que só tem a
prova do que escreveu — sem gate sobre essa prova, ela é decorativa.
