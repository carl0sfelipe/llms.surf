---
id: 2026-09-20-biggest-gap-le-a-primeira-linha-inutil-d
titulo: biggest gap le a primeira linha inutil do stderr do gradle
data: 2026-09-20
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): oracfit_gauntlet_biggest_gap em bin/lib-oracfit-gauntlet.sh pula boilerplate do Gradle (FAILURE:, "* What went wrong:", "* Try:", "> ", vazias) e prefere o bloco What went wrong/Caused by; tests/test-gauntlet-feedback.sh cobre com log de Gradle fixture
status: corrigido
---

# biggest gap le a primeira linha inutil do stderr do gradle

Dogfood real da v4.1.0 (2026-09-20): run da R03 (orquestrador Ktor) com stub.

## Sintoma

Run com 5 tentativas, fail honesto em 6s — mas o feedback de gap registrado é
`FAILURE: Build failed with an exception.` em toda tentativa. A linha útil do
Gradle (unresolved reference, task que falhou, causa real) vem DEPOIS da
primeira linha. Um modelo real receberia feedback vazio: a primeira linha do
stderr do Gradle não diz nada acionável.

## Causa

`oracfit_gauntlet_biggest_gap()` (`bin/lib-oracfit-gauntlet.sh:248-289`):
os fallbacks fazem `head -1` sobre o log combinado stdout+stderr. Para Gradle,
a primeira linha casada pelos filtros FAIL/ERROR é o cabeçalho boilerplate
"FAILURE: Build failed with an exception." — a informação real está no bloco
"* What went wrong:" / "* Caused by:" abaixo. O corte em 240 chars preserva só
o boilerplate. Consumidor: `oracfit_gauntlet_append_feedback()`
(`bin/lib-oracfit-gauntlet.sh:609-616`, "Single biggest remaining gap") →
loop de retry em `bin/dispatch-mode.sh:456-458`.

## Correção aplicada

`oracfit_gauntlet_biggest_gap()` agora, antes do `head -1`:

1. descarta boilerplate conhecido do Gradle — `FAILURE: Build failed with an
   exception.`, `* What went wrong:`, `* Try:`, `> Run with`, linhas `> ` e
   vazias;
2. prefere a primeira linha de conteúdo do bloco `* What went wrong:` /
   `* Caused by:` (ex.: `Execution failed for task ':compileKotlin'.` +
   causa na linha seguinte);
3. mantém o fallback atual (primeira linha FAIL/ERROR não-boilerplate) e o
   corte em 240 chars.

Coberto por `tests/test-gauntlet-feedback.sh` com log de Gradle fixture: o gap
escolhido deve conter a linha informativa, não o cabeçalho.

## Pode acontecer de novo?

Para boilerplate de OUTRAS ferramentas (npm, cargo, etc.), sim — o filtro é
uma lista crescente de padrões conhecidos; cada ferramenta nova que grita antes
de informar entra na lista pelo mesmo caminho (incidente novo apontando a
linha). O mecanismo de escolha (última palavra do bloco de causa, não a
primeira linha do stderr) está correto agora.
