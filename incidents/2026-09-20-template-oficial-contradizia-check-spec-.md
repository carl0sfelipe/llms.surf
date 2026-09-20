---
id: 2026-09-20-template-oficial-contradizia-check-spec-
titulo: template oficial contradizia check-spec: crase no comando do oraculo
data: 2026-09-20
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): fluxos/_comum/artefato-template.md sem crase nas linhas comando:/como fetchar + tests/test-artefato-template.sh instancia o template numa spec mínima e roda bin/check-spec.sh exigindo exit 0
status: corrigido
interage_com: "2026-08-10-backtick-no-comando-do-oraculo (recorrência direta: aquele incidente criou a regra 46 e o gate em bin/check-spec.sh:73-80, mas o template seguiu ensinando o padrão errado — o gate protegeu as specs existentes, não quem nasce do template)"
---

# template oficial contradizia check-spec: crase no comando do oraculo

Dogfood real da v4.1.0 (clone limpo da tag, caminho de 2 minutos, 2026-09-20).

## Sintoma

Spec escrita copiando `fluxos/_comum/artefato-template.md` reprova no
`bin/check-spec.sh` na primeira rodada. A S32 (bestmodel, PR #12) veio inteira
com crase nas linhas `comando:` herdadas do template e levou reprovação antes
de qualquer despacho. O mesmo valeu para as specs do rawpack na primeira
passada.

## Causa

O template ensinava exatamente o que a regra 46 reprova:

- `fluxos/_comum/artefato-template.md:43` — `` - comando: `<comando shell exato, ...>` ``
- `fluxos/_comum/artefato-template.md:24` — `como fetchar:` com crase
- `fluxos/_comum/artefato-template.md:48` — exemplo de oráculo com crase

Contra o gate em `bin/check-spec.sh:73-80`
(`grep -qE '^[-*][[:space:]]*comando:.*`' "$SPEC"` → reprovação "contém CRASE
(backtick) — vira substituição no eval e gera exit 127 fantasma"). Quem copia o
template oficial leva reprovação garantida. Nenhum teste validava o próprio
template contra o gate que o consome — recorrência da família do incidente
2026-08-10: o conserto protegeu as specs da árvore, não a origem de specs novas.

## Correção aplicada

1. `fluxos/_comum/artefato-template.md` — crases removidas dos placeholders
   `comando:`, `como fetchar:` e do exemplo de oráculo (linhas 24, 43, 48):
   texto cru, como a regra 46 manda.
2. `tests/test-artefato-template.sh` — proteção: instancia o template numa
   spec mínima válida e roda `bin/check-spec.sh` contra ela exigindo exit 0.
   Template que voltar a contradizer o gate reprova a bateria no CI.

## Pode acontecer de novo?

Não pelo template — o teste trava a contradição no CI. Crase digitada à mão
continua sendo pega pela regra 46 no check-spec, como antes. Por isso
mecanismo, não regra nova.
