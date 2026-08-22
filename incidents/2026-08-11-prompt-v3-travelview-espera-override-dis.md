---
id: 2026-08-11-prompt-v3-travelview-espera-override-dis
titulo: PROMPT v3 travelview espera override DISPATCH_MODEL_REF que nao existe — fallback cheap→paid exige workdir-overlay mode
data: 2026-08-11
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): DISPATCH_MODEL_REF honrada por dispatch-mode.sh (vence YAML e default) e por dispatch-stages.sh (so em stage com model_ref nao-vazio; stage mecanico nunca ganha modelo); tests/test-model-override.sh (construido via dispatch GLM 5.2 free, run 36E63816, revisado)
status: promovido
---

# Override de modelo por env nao existe — fallback cheap→paid do prompt v3 exige mode overlay

## Sintoma

O `docs/prompts/PROMPT-TRAVELVIEW-V3-REFATORACAO.md` (seção ROTEAMENTO DE MODELOS) instrui:
despachar o tier cheap e, em falha de transporte 2x, re-despachar com
`DISPATCH_MODEL_REF=deepseek/deepseek-v4-flash-direct`. A env nao e lida por
nenhum script do oracfit.

## Causa

EVIDÊNCIA: `grep -n "MODEL_REF" bin/dispatch-mode.sh bin/dispatch-stages.sh
bin/lib-oracfit-mode-loader.py` → zero matches (rc=1). O `model_ref` vem
EXCLUSIVAMENTE do YAML do modo (`dispatch-stages.sh:163` le
`stages[i].model_ref` do JSON do mode-loader). Nao ha mecanismo de override
por env em 2026-08-11.

Consequuencia: o fallback cheap→paid documentado no prompt e inexequível como
escrito; a unica via e criar modo distinto (ou workdir-overlay AD-16) com o
model_ref desejado.

## Correção aplicada

Workaround nesta sessão: workdir-overlay mode
`~/tripstory-mvp1/core/modes/refatoracao_next_ready.yaml` (resolucao AD-16:
workdir tem precedencia sobre ROOT em dispatch-mode.sh:173) com
`model_ref: deepseek-v4-flash-free`. Nenhuma mudanca no framework.

## Pode acontecer de novo?

Sim — toda sessao que seguir o prompt v3 cai na mesma instrucao inexequível.
Candidata a regra/mecanismo pra v3 oficial: `DISPATCH_<STAGE>_MODEL_REF` (ou
campo `model_ref_override`) honrado pelo dispatch-stages.sh, cobrindo o
fallback cheap→paid que hoje e manual e depende de criar modo.
