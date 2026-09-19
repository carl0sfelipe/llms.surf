---
id: 2026-09-19-dispatch-sh-recusa-tier-cheap-sem-mode-yaml
titulo: tier:cheap não despacha via bin/dispatch.sh sem mode YAML — runner recusa com exit 3
data: 2026-09-19
recorrivel: sim
regra: nao — caminho de correção declarado no D-DISPATCH (T20 + hint de uma linha no dispatch.sh)
status: aberto
interage_com: "2026-08-30-unlock-plan-passa-tier-ao-runner-sem-res (mesma família: ref tier:* literal chega ao runner → exit 3 em ~0s; lá a correção cobriu o caminho de modo, aqui a frente única ficou sem)"
interage_com: "kernel/test-specs/README.md regra 2 (recomenda exatamente o comando que falha: bin/dispatch.sh tier:cheap kernel/test-specs/<ID>-*.md p1-<ID>)"
interage_com: "docs/research/specs/P1-dispatch-policy-rust.md (integração do kernel torna o binário o resolvedor único do ramo tier:*)"
interage_com: "docs/research/bend2-convergence-2026-09-19.md §6 E5 (o experimento central da pesquisa depende deste caminho existir)"
---

# tier:cheap não despacha via `bin/dispatch.sh` sem mode YAML — runner recusa com exit 3

Promovido do D-DISPATCH item 1 (`kernel/test-specs/DECISIONS-wave1-2.md`,
2026-09-19): a bateria do kernel (T01–T10) precisa rodar DENTRO do produto
com ledger — e o comando que o próprio README da bateria recomenda não
despacha em runner de verdade. Registro primeiro, correção neste turno NÃO
aplicada.

## Sintoma

Reproduzido em 2026-09-19, worktree `p1-inc-1` @ 87a12a1, sem gastar token
(todos os gates recusam ANTES de qualquer dial):

1. O ref literal na porta do contrato do runner:

```
$ bash adapters/zcode/runner.sh tier:cheap tests/fixtures/oracfit-smoke-unlock-plan.md
modelo tier:cheap ausente do model-registry.json
# exit 3
```

   Exatamente o que `core/runner-contract.md` manda: "id ausente do
   registry → exit 3 (nunca inventar model id)". O adapter está certo; quem
   chama está errado.

2. O comando documentado, ponta a ponta — `bin/dispatch.sh tier:cheap
   <spec> <task>` com runner real (`DISPATCH_RUNNER=adapters/zcode/runner.sh`):
   o despacho é aceito (fire-and-forget, exit 0), o `run-with-fallback.sh`
   até expande a cadeia do tier, mas TODA perna viva morre na mesma porta do
   runner ("modelo X não tem cli_hint para zcode" → exit 3) e a cadeia
   esgota:

```
✖ cadeia de fallback esgotada para tier:cheap (último motivo: exit 3)
# EXIT_FILE dispatch-<task>.exit = 3 — nenhum modelo chamado, nenhum token
```

Sintoma adjacente no mesmo caminho (evento distinto — não é a causa acima):
as specs do kernel (`kernel/test-specs/T01-*.md`) nem chegam ao runner — o
preflight `check-spec` reprova por falta de cláusula anti-invenção/## Oráculo
(exit 1). Gate separado, porta separada.

## Causa

Duas camadas no mesmo caminho. Não misturar.

### 1. `bin/dispatch.sh` não conhece `tier:*` (esta falha)

O cabeçalho do script declara o contrato: "o model_id vem pronto do
model-registry.json". `tier:cheap` não é id — medido no registry: **27
modelos, nenhum ref `tier:*`** (zero ocorrências da string no arquivo).
A resolução de tier existe, mas vive FORA da frente única:
`bin/lib-oracfit-mode-loader.py resolve-tier` funciona (devolve os 11 refs
do catálogo free carimbado, keyless primeiro) e é chamada pelo
`run-with-fallback.sh` — que por sua vez só é roteado pelo
`bin/dispatch-mode.sh` no caminho de MODO (`core/modes/*.yaml`, caso
`tier:*) → STAGE_RUNNER=run-with-fallback.sh`). `bin/dispatch.sh` não tem
ramo `tier:*` nem uma linha que aponte o usuário para
`bin/dispatch-mode.sh` — quem segue o README da bateria descobre o exit 3
sozinho, no log.

### 2. Mesmo com a cadeia expandida, só existe hint para um CLI

Os 11 refs do `data/free-catalog.json` carregam exclusivamente
`cli_hints.opencode`. Em qualquer outro adapter o runner recusa perna por
perna (contrato: "id presente sem hint para aquele CLI → exit 3") e a
cadeia inteira esgota em exit 3 — medido acima com o runner zcode. O stub
mascara o furo (aceita qualquer `MODEL_ID`), mesmo padrão da smoke verde
do incidente 2026-08-30.

## Correção proposta (não aplicada — D-DISPATCH item 1)

1. **T20 dá um lar de modo à bateria**: `core/modes/kernel_test.yaml`
   (schema v1, `mode validate`) com stage `run` em `tier:cheap` + oráculo
   mecânico `kernel/test-specs/oracle.sh <ID>` — a bateria vira feature do
   produto e cada run vira ponto de dados do E5
   (`kernel/test-specs/T11-T20-second-wave.md`).
2. **Hint de uma linha no `bin/dispatch.sh`**: quando o ref do modelo for
   `tier:*`, apontar `bin/dispatch-mode.sh` (que roteia tier via
   run-with-fallback e é a entrada dona de mode YAML). Uma linha de
   mensagem, não um resolvedor novo — resolução duplicada é o que o E5-M4
   já pagou pra limpar.
3. Quando a integração P1 existir
   (`docs/research/specs/P1-dispatch-policy-rust.md`), o binário do kernel
   vira o resolvedor único do ramo `tier:*` — o hint sobrevive, o Python
   embutido vai embora.

## Pode acontecer de novo?

Sim — hoje, todo despacho da bateria do kernel pelo comando do próprio
README falha em runner real (exit 3, cadeia esgotada, zero token). E5,
o experimento central da pesquisa, **segue não medido até o T20 existir**
(D-DISPATCH: "E5 stays unmeasured until T20 exists" — anotado e datado em
`docs/research/bend2-convergence-2026-09-19.md` §6). Enquanto o hint não
existir, quem chegar por `bin/dispatch.sh` com `tier:*` vai refazer a
descoberta deste incidente a partir de um log de 3 linhas.
