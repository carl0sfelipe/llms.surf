---
id: 2026-08-11-vision-gate-gap-nao-injetado-no-feedback-do-gauntlet
titulo: vision_gate articula biggest_gap no verdict.txt mas o gauntlet injeta feedback generico no builder
data: 2026-08-11
recorrivel: sim
regra: nao — mecanismo aplicado (classe C) no core: oracfit_gauntlet_biggest_gap prefere a linha VISION GATE REJECTED do logfile (commit 995ff67) — o gap articulado pelo juiz chega ao feedback do builder sem depender de mitigacao por modo
status: promovido
interage_com: "2026-08-11-t3-judge-biggest-gap-vazio-max-iterations-20-loop-patologico"
interage_com: "docs/architecture/ADR-0005-iteracao-sem-gap-e-falha-de-contrato"
---

# vision_gate articula biggest_gap mas o gauntlet não injeta — builder refaz às cegas

## Contexto

Dispatch do modo `card_redesign` (tripstory-mvp1, run_id `C3E847DF`).
Pipeline: run (Flash edita CSS) → render (screenshot) → vision_gate (gemma free
julga). O `loop_target: run` faz o vision_gate reprovar voltar pro build.

## Sintoma

O juiz gemma **articulou o gap** corretamente no verdict.txt:

```json
{"verdict":"REJECTED","biggest_gap":"The text on the step cards is extremely small and illegible, and the content is cramped at the bottom of the viewport."}
```

Mas o `feedback.md` injetado de volta no builder continha:

```
## GAUNTLET FEEDBACK (attempt 1)
Oracle exit: 1
Single biggest remaining gap: STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1
```

O gap articulado pelo juiz ("text is extremely small") **não chegou** no builder.
O modelo foi re-despachado sem saber o que corrigir.

## Causa raiz

`oracfit_gauntlet_append_feedback` chama `oracfit_gauntlet_biggest_gap(oracle_log)`,
que lê o **logfile do oráculo**. O logfile do vision_gate é produzido por
`oracfit_gauntlet_run_oracle_capture`, que roda o `stage_oracle` (um grep por
APPROVED). O grep falha (REJECTED), e o logfile contém só:

```
STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1
```

O `biggest_gap` heuristic procura por `FAIL|ERROR|REJECTED` no logfile —
encontra "FAILED", mas não o gap específico. O verdict.txt com o gap articulado
**nunca é lido pelo mecanismo de feedback**.

O juiz produz a informação correta, mas ela morre no arquivo de verdict sem
chegar ao loop. É o espelho do incidente t3-loop (regra 45): ali o juiz
produzia `biggest_gap` vazio; aqui o juiz produz `biggest_gap` correto mas o
gauntlet não lê.

## Por que o loop queima iterações sem convergir

O `safety_ceiling: 3` dá 3 loops. Sem o gap articulado, cada iteração do builder
recebe "STAGE ORACLE FAILED" — feedback não-acionável. O modelo refaz o CSS às
cegas e o juiz provavelmente rejeita pelos mesmos motivos. 3 iterações gastas
sem melhoria direcionada = desperdício de compute.

## Mitigação aplicada (não no core — no mode YAML)

O `stage_oracle` do `card_redesign.yaml` foi alterado para extrair o gap do
verdict.txt e escrevê-lo no logfile do oráculo:

```yaml
stage_oracle: >
  if grep -qi APPROVED verdict.txt; then exit 0;
  else
    echo "VISION GATE REJECTED — biggest_gap:";
    python3 -c "...extrai biggest_gap do JSON...";
    exit 1;
  fi
```

Assim o `oracfit_gauntlet_biggest_gap` lê o gap no logfile e o injeta no
feedback. **Mas isso é mitigação por modo, não no core.**

## Regra candidata

> **O stage_oracle de um vision_gate (ou qualquer stage com juiz LLM que
> produz gap estruturado) DEVE extrair o gap do verdict e escrevê-lo no
> logfile do oráculo, para que `oracfit_gauntlet_biggest_gap` o injete no
> feedback do builder. Sem isso, o loop visual não converge — o builder
> refaz às cegas.**

Alternativa de fix no core: `oracfit_gauntlet_run_critic` poderia ler
diretamente o verdict.txt (ou um arquivo configurado via env
`ORACFIT_VERDICT_FILE`) e extrair o gap de lá, sem depender do stage_oracle.

## Pode acontecer de novo?

Sim — qualquer modo novo com vision_gate que use o pattern "grep APPROVED no
stage_oracle" sem extrair o gap vai cair no mesmo buraco. A mitigação é por
modo (frágil); o ideal é o core garantir a extração.

## Relação com regras/ADRs existentes

- **ADR-0005**: "iteração sem gap articulado é falha de contrato". Aqui o gap
  É articulado pelo juiz, mas o pipeline não o transporta — mesma consequência
  (builder sem gap), causa diferente (transporte, não contrato).
- **Regra 45**: "extrator de feedback deve procurar os campos que o agent
  realmente produz". Aqui o extrator lê a fonte errada (logfile do grep, não
  o verdict do juiz).
