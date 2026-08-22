---
id: 2026-08-10-gauntlet-loop-biggest-gap-vazio-faz-buil
titulo: gauntlet-loop-biggest-gap-vazio-faz-builder-refasar-as-cegas
data: 2026-08-10
recorrivel: sim
regra: 45
status: promovido
---

# Gauntlet loop: biggest_gap vazio faz builder refazer às cegas (loop não converge)

## Sintoma

O piloto `<host-local>-ser5-max-radeon-680m-igpu` rodou **5 iterações do gauntlet
T1-JUDGE → T1-HUNT sem convergir** (max 20). A nota do juiz não subiu de 2.38
em nenhuma iteração. Investigando o `events.jsonl` e o log do pipeline: o
campo `biggest_gap` veio **vazio (`""`) em TODAS as 5 iterações** — o builder
recebeu `_biggest_gap: ""` e refaz sem saber o que corrigir.

Evidência (log `run-radeon680m-resume-20260810-021400.log`):
```
"biggest_gap": ""   # 5 ocorrências, todas vazias
```

## Causa

**Incompatibilidade de schema entre 3 arquivos** — nenhum mecanismo garante
que eles concordam:

1. `config/tasks.yaml` (T1-JUDGE `expected_output.required_fields`) define:
   `verdict, confidence_score, overall_score, dimension_scores, critical_issues,
   improvement_requirements, feedback_for_hunter`. **NENHUM campo se chama
   `biggest_gap`.**

2. `config/agents.yaml` (prompt do `judge_hunter_pm`) **pede** `biggest_gap:
   "string"` no output — mas o agente DeepSeek flash, ao gerar, segue o
   `expected_output` do tasks.yaml (que não tem o campo) e **não produz
   `biggest_gap`**. Conflito não-detectado: tasks.yaml e agents.yaml discordam
   sobre o schema do output do juiz, e nada enforceia a concordância.

3. `src/bmad_crew.py:_extract_biggest_gap` (linha 1180) procura SÓ por
   `biggest_gap`, `single_biggest_gap`, `primary_gap` no output. Esses campos
   **não existem** no que o agente produz. O juiz escreve `improvement_requirements`
   e `feedback_for_hunter` (o feedback real, rico), mas o extrator **ignora**
   esses campos — só procura `biggest_gap`.

Resultado: o gauntlet "funciona" (loop dispara, builder refaz), mas o feedback
**não chega** ao builder. Ele refaz às cegas, a nota não sobe, o loop só para
no teto de 20 (escalation humana) — desperdiça tokens e tempo.

## Impacto medido (piloto radeon-680m)

- 5 iterações sem convergir (de 20 máximas).
- ~100-125k tokens DeepSeek (~$0.02-0.04 — barato, mas inútil: trabalho descartado).
- ~30 min de wall-clock desperdiçados.
- O gauntlet de barra alta, que DEVERIA convergir com feedback específico,
  virou um "refaz até o teto" — indistinguível de não ter gauntlet.

## Correção aplicada

Fazer `_extract_biggest_gap` cair pros campos que o juiz **realmente produz**
(quando `biggest_gap` não vier): `improvement_requirements`, `feedback_for_hunter`,
`critical_issues` — nessa ordem de preferência. Mais: o `tasks.yaml` e
`agents.yaml` devem concordar — adicionar `biggest_gap` ao `required_fields`
do tasks.yaml T1-JUDGE pra que o agente seja enforced a produzi-lo. Sync dos
2 schemas (não basta consertar o extrator; o agente tem que saber que deve
produzir o campo).

## Pode acontecer de novo?

**SIM** — e VAI, em todo gauntlet de T1 e T4, enquanto o extrator e o schema
do agent discordarem. Sem mecanismo que valide "agent produz o campo que o
extrator procura", toda nova task/agent pode recair. **DEVE virar regra.**

Candidata a regra:

> O campo que o `_extract_biggest_gap` (e qualquer extrator de feedback do
> gauntlet) procura DEVE estar no `expected_output.required_fields` do task
> YAML — senão o agent não produz e o feedback chega vazio. Incompatibilidade
> de schema entre tasks.yaml (expected_output) e agents.yaml (prompt) é o bug;
> o extrator tolerante (cair pros campos que existem) é a mitigação, mas a raiz
> é sync. MECANISMO: `_extract_biggest_gap` agora procura múltiplos campos
> (biggest_gap, improvement_requirements, feedback_for_hunter, critical_issues)
> + os required_fields do tasks.yaml incluem biggest_gap explicitamente.

Interage com: regra 43 (fairness — também é "check sobre output do juiz"),
regra 44 (verdict íntegro — mesma família: o output do juiz tem que ter o
campo esperado), regra 16 (recorrente vira mecanismo), regra 32 (regra sem
mecanismo é dívida — aqui o mecanismo é o extrator tolerante + sync de schema).

interage_com: 43 (MESMA FAMÍLIA — ambas são "check sobre output do juiz"; 43
verifica honestidade comercial, 45 verifica que o feedback chega ao builder;
juntas cobrem o ciclo juiz→builder), 44 (MESMA FAMÍLIA — "output do juiz tem
que ter o campo esperado"; 44 enforceia integridade do verdict, 45 enforceia
que o gap chegue; ambas detectam output defeituoso do juiz), 32 (SATISFEITA —
mecanismo existe: extrator em cascata + sync de schema no tasks.yaml), 16
(INSTANCIA — virou regra 45 com mecanismo real). Sobreposição de termo
alertada: 43/testes (ambas têm testes pytest — domínio igual, sem conflito),
43/textual (ambas têm marker textual fallback — complementares, não conflitam).
O que pode quebrar: o extrator em cascata pode pegar `critical_issues` (uma
LISTA) e devolver string longa como gap — limitei a 800 chars; se o builder
receber gap muito genérico, convergência ainda é lenta (mas não mais às cegas).
Dívida residual: validador automático de schema cross-arquivo (tasks.yaml
↔ agents.yaml) que enforceie concordância ANTES do run — hoje é manual.
