---
id: 2026-08-30-unlock-plan-passa-tier-ao-runner-sem-res
titulo: unlock_plan passa tier: ao runner sem resolver
data: 2026-08-30
recorrivel: sim
regra: pendente
status: aberto
classe: C
interage_com: "core/runner-contract.md (quem chama passa id do registry; id ausente → exit 3)"
interage_com: "bin/lib-oracfit-mode-loader.py resolve-tier (existe e não é chamado por dump/dispatch-stages)"
interage_com: "2026-08-12-pick-aprova-model-ref-ausente-do-registr.md (mesma família: id inválido → runner recusa em ~0s)"
---

# unlock_plan passa tier: ao runner sem resolver

Halt pedido pelo dono (2026-08-30): incidente registrado, **sem correção
neste turno**. O despacho S25 do bestmodel (`llms-surf run tow`) não rodou.

## Sintoma

Boot Cursor em workdir alheio (`ORACFIT_WORKDIR=~/Work/bestmodel`,
`DISPATCH_RUNNER=adapters/cursor/runner.sh`). O modo `tow` (= `unlock_plan`)
não pode ser despachado: o primeiro stage (`unlock`) chamaria o runner com
`model_ref` literal `tier:expensive`.

Reprodução (cwd = checkout llms.surf, `ORACFIT_WORKDIR` unset):

```
$ python3 bin/lib-oracfit-mode-loader.py dump core/modes/unlock_plan.yaml
# stages[].model_ref =
#   ['tier:expensive', 'tier:mid', 'tier:cheap']

$ grep -nE 'resolve.tier|resolve_tier' bin/dispatch-stages.sh
# (nenhuma chamada)

$ bash adapters/cursor/runner.sh tier:expensive tests/fixtures/oracfit-smoke-unlock-plan.md
modelo tier:expensive ausente do model-registry.json
# exit 3
```

O contrato do runner (`core/runner-contract.md`) manda exatamente isso:
id ausente do registry → exit 3, nunca inventar model id. O adapter está
certo. Quem chama está errado.

Sintoma adjacente no mesmo boot (evento distinto — não é a causa acima):
`bash bin/llms-surf ledger s25-plan` → `'ledger' não é subcomando conhecido`
(exit 2). O help aponta `status --task`. `bin/ledger.sh` existe e não está
na fachada.

## Causa

Duas camadas no mesmo caminho `tow` + adapter Cursor. Não misturar.

### 1. dump/stages não resolvem `tier:` (esta falha)

`core/modes/unlock_plan.yaml` declara `model_ref: tier:expensive|mid|cheap`.
`bin/lib-oracfit-mode-loader.py dump` devolve o YAML cru. `bin/dispatch-stages.sh`
lê `stages[i].model_ref` (linha 208) e passa essa string a `$DISPATCH_RUNNER`
(linha 404). Não chama `resolve-tier`.

O loader **tem** `resolve-tier`. Medido no mesmo checkout:

```
$ python3 bin/lib-oracfit-mode-loader.py resolve-tier tier:cheap --registry model-registry.json
deepseek-v4-flash-free
$ python3 bin/lib-oracfit-mode-loader.py resolve-tier tier:mid --registry model-registry.json
deepseek/deepseek-v4-chat
$ python3 bin/lib-oracfit-mode-loader.py resolve-tier tier:expensive --registry model-registry.json
deepseek-v4-pro-direct
```

O stub (`adapters/stub/runner.sh`) aceita qualquer `MODEL_ID` e grava
`model_id=$MODEL_ID` no stub-proof — por isso a smoke `unlock_plan` fecha
verde sem nunca exercitar o registry. Qualquer runner que cumpra o contrato
(cursor, opencode, zcode, hermes, prime-agent) recusa no primeiro stage.

### 2. Mesmo resolvido, o id caro não tem hint Cursor (a próxima recusa)

Só dois ids no registry têm `cli_hints.cursor`:

- `cursor-sonnet-4-thinking` → `sonnet-4-thinking`
- `cursor-gpt-5` → `gpt-5`

`deepseek-v4-pro-direct` (saída de `tier:expensive`) tem
`cli_hints: {prime-agent: deepseek/deepseek-v4-pro}` e nenhum `cursor`.
O runner Cursor, com id presente sem hint, também é exit 3 (contrato:
"modelo X não tem cli_hint para cursor").

Camada 1 dispara primeiro (`tier:expensive` nem é id). Camada 2 ficaria
exposta no dia em que alguém só plugar `resolve-tier` no dump.

## Correção aplicada

Nenhuma. Dono: registrar incidente e parar. Não despachar S25. Não promover
regra neste turno. Não editar `bin/dispatch-stages.sh` nem o registry.

Caminho de correção (classe C, para quem retomar): `dispatch-stages.sh`
resolver `tier:*` via `lib-oracfit-mode-loader.py resolve-tier` **antes**
de invocar `$DISPATCH_RUNNER`, e o registry precisa de `cli_hints.cursor`
(ou um id Cursor) no alvo de `tier:expensive`/`mid`/`cheap` — senão o tow
no adapter Cursor continua exit 3 na camada 2. Teste que hoje só passa no
stub não cobre isto.

## Pode acontecer de novo?

Sim, em todo `llms-surf run tow` (e qualquer modo cujo YAML use `tier:`)
com adapter que olha o registry. A smoke verde no stub esconde o furo.

Observação relacionada, evento distinto (não conflatar; não é a causa
deste exit 3): `unlock_plan.yaml` marca `oracle: true` no stage unlock.
O runtime então roda o `## Oráculo` da spec de tarefa no unlock. Spec
cujo oráculo mede trabalho que só o stage `run` grava reprova o unlock
e `on_fail: halt` nunca chega no barato. A smoke passa porque todos os
stages escrevem o mesmo `.dispatch/stub-proof`.
