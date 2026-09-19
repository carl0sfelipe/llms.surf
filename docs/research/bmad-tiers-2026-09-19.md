# BMAD × llms.surf: uma orquestração por tier, não um prompt por tier

Fable, 2026-09-19. Casa do time: `~/Work/bmad` (destino `/data/bmad`).
Modos validados pelo loader deste repo (`bin/lib-oracfit-mode-loader.py`).
T20 deve caber nesta mesma gramática.

## O que muda quando o tier muda

| | CTO (`tier:expensive`) | Winston (`tier:mid`) | Dev (`tier:cheap`) |
|---|---|---|---|
| **Entrada** | ponteiros (job card) + arquivo de escalada; **nunca** a árvore | brief + decisões vigentes + leis + o `AGENTS.md` da área | **uma** spec com footprint e comando de aceitação |
| **Saída** | decision-record (prosa estruturada, sem código) | spec executável | commits na branch da spec |
| **Oráculo** | `decision-record.sh`: seções, sem blocos de código, números com fonte | `spec.sh`: seções, `writes:`/`reads:`, comando de aceitação, números com fonte | o comando de aceitação da spec (stage `command:`) |
| **Retry** | 1 tentativa; `owner_question: once` | 2 tentativas; gauntlet injeta a falha do oráculo | 3 tentativas; gauntlet `until_approved`; falhou 2× → escala |
| **Pode** | decidir, rejeitar, reordenar | especificar, dividir footprint, pedir decisão | implementar dentro do footprint |
| **Não pode** | código, testes, builds, deploy | mudar decisão sem novo record; código | merge, editar leis, sair do footprint |
| **Contexto** | ~40k tokens | ~120k | ~60k |

A diferença não é "prompt mais educado para o modelo caro": é **forma da
entrada, forma da saída e oráculo diferentes**. O caro vê pouco e decide; o
médio traduz decisão em spec verificável; o barato vê só a spec e é julgado
por comando. Escalada só sobe (dev → winston → cto); cheap nunca chama
expensive (ORG-L1/L2 em `~/Work/bmad/laws/ORG.md`).

## Modelos específicos (custom)

`modes/custom/*.yaml`: `model_ref` pode ser `tier:vision` ou um id do
registry. Mesma regra: oráculo mecânico declarado no modo. Exemplo
entregue: `vision_qa.yaml` (vision_gate sobre capturas).

## Como o T20 se encaixa

`core/modes/kernel_test.yaml` = o modo `dev_build` com a spec da bateria
como entrada e `kernel/test-specs/oracle.sh <ID>` como stage `command:`.
Quando existir, os modos do BMAD passam a ser despacháveis por
`bin/dispatch-mode.sh` com ledger — e o E5 (fechamento por tier) sai de
graça de cada rodada de Winston/Dev.

## O que ainda não é mecanismo

- Revisão do médio sobre o barato antes do dono ver (candidato a stage
  `plan` de revisão no `dev_build.yaml`).
- Budget de contexto por papel é declarado em `team.yaml`, não imposto:
  o dispatcher não conta tokens do prompt hoje. Candidato: `preflight`
  que mede o input e recusa acima do budget.
