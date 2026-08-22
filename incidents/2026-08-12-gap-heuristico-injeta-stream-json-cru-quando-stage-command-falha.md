---
id: 2026-08-12-gap-heuristico-injeta-stream-json-cru-quando-stage-command-falha
titulo: "STAGE COMMAND FAILED: oracle_log carrega o tail do stream --format json do opencode e a heurística de gap injeta um blob JSON inútil no feedback"
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo (classe C): exclusão '^[[:space:]]*\{\"' nos dois fallbacks de oracfit_gauntlet_biggest_gap + teste 9 em tests/test-gauntlet-feedback.sh
status: corrigido — working tree, aguardando commit
interage_com: "2026-08-12-biggest-gap-heuristic-pega-boilerplate-em-vez-do-gap-real"
interage_com: "2026-08-12-loop-target-nao-transporta-feedback-entre-stages"
---

# Gap heurístico injeta stream JSON cru quando o STAGE COMMAND falha

## Sintoma

Run `AA26BEB2` (infografico_v3, 2026-08-12 06:18): o builder flash estourou o
contexto lendo o `infografico.html` inteiro (218KB/8137 linhas) e o runner
morreu com exit 1/2 ANTES de qualquer oráculo, em 3 attempts. O feedback
injetado nesses attempts foi lixo:

```
gauntlet stage=run attempt=1 gap={"type":"tool_use","timestamp":1786526318523,"sessionID":"ses_..."...
```

## Causa raiz

Quando o STAGE COMMAND falha, o `oracle_log` recebe o tail do output do
runner — que em `--format json` é stream JSON do opencode. Linhas
`{"type":"tool_use",...}` contêm tokens como `"status":"error"` que casam o
grep positivo (`-iE 'FAIL|ERROR|...'`) da heurística. `head -1` devolve o
blob. Nenhum dos filtros de exclusão existentes (boilerplate, ^slice,
freshness) cobria linhas JSON.

## Correção

`bin/lib-oracfit-gauntlet.sh`, `oracfit_gauntlet_biggest_gap`: exclusão
`^[[:space:]]*\{"` adicionada aos DOIS fallbacks. Linha de erro legível
(ex: `opencode: error: context length exceeded ...`) continua passando.
Teste 9 novo em `tests/test-gauntlet-feedback.sh` cobre o cenário exato.
Suítes pós-fix: feedback 9/9 · stage-runner 16/16 · critic 10/10.

## Causa-gatilho (fix separado, nível spec)

O estouro de contexto em si é problema do SPEC, não do core: monolito de
8k linhas + builder flash lendo inline. Fix aplicado em
`tripstory-mvp1/specs/infografico-refino-v3.md`: seção "Regras de edicao —
OBRIGATORIO" (grep + fatias de 40-80 linhas, edição cirúrgica, nunca ler o
arquivo inteiro, máx 2-3 edições por attempt) + `run_attempt_budget` 5→10 no
modo (attempt 1 perdido por estouro não pode consumir metade do budget).

## Observação positiva do mesmo run

O critic estruturado RODOU para o stage run (driver_ref existe) e
diagnosticou sozinho a causa ("dumping the entire infografico.html ...
bloated the session"), com must_fix acionável. O diagnóstico do critic foi
usado como base do fix de spec acima.
