---
id: 2026-11-12-stage-mecanica-de-stage-unico-chama-mode
titulo: stage mecanica de stage unico chama modelo em vez do comando
data: 2026-11-12
recorrivel: sim
regra: mecanismo aplicado
status: fechado
---

# stage mecanica de stage unico chama modelo em vez do comando

## Sintoma

Um modo customizado com UMA stage mecânica — `command:` e nenhum `model_ref` —
não rodava o comando. O run disparava um modelo:

```
▶ tentando: mimo-v2.5-free
stub runner: wrote /tmp/.../.dispatch/stub-proof
status: pass
```

A stage foi escrita para rodar um script, não para chamar uma LLM. O comando
nunca foi executado — e o run ainda terminava `pass`, porque o oráculo do spec
era satisfeito pelo stub, não pelo trabalho da stage.

O mesmo modo com DUAS stages (`mecanical stage run: running command`) rodava
correto. A diferença era só a contagem de stages.

## Causa

O roteador em `bin/oracfit` (`cmd_run`) escolhe o runtime pelo NÚMERO de stages:

```bash
if [ "${stage_n:-1}" -gt 1 ] 2>/dev/null; then
  exec "$SCRIPT_DIR/dispatch-stages.sh" "$mode" "$@"
fi
exec "$SCRIPT_DIR/dispatch-mode.sh" "$mode" "$@"
```

`dispatch-stages.sh` sabe rodar stage mecânica (`command:` sem `model_ref`).
`dispatch-mode.sh` **não sabe** — ele só despacha modelo: o `model_ref` do YAML
ou, na falta, o default `tier:cheap`. Uma stage mecânica de stage única caía no
runtime errado, que ignorou o `command:` e chamou um modelo.

O mecanismo que decide "isto é mecânico" era o número de stages, não a
presença de `command:` — proxy errado para a propriedade.

## Correção aplicada

- `bin/oracfit` (`cmd_run`): o runtime agora é escolhido também quando
  QUALQUER stage declara `command:`. Uma stage mecânica isolada vai para
  `dispatch-stages.sh`, que a executa.
- `tests/test-mode-tooling.sh`: seções 7 e 8 — a stage mecânica roda o comando
  (e nenhum modelo é chamado), e um comando que falha não vira `pass`.

## Pode acontecer de novo?

Sim, na mesma família: qualquer proxy de decisão que não seja a propriedade
mesma vira proxy de contagem. A regra aplicada aqui é a da própria
`dispatch-stages.sh`: **o que decide é o campo que declara** (`command:`), não
o número de itens. O mecanismo aplicado está no roteador e o teste trava o
comportamento — um modo com `command:` não pode chamar modelo.
