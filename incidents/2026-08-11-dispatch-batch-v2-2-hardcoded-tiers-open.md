---
id: 2026-08-11-dispatch-batch-v2-2-hardcoded-tiers-open
titulo: dispatch-batch v2.2 hardcoded tiers openrouter ignoram roteamento v3 (free zen vivo) — lote wizard roda sequencial via overlay mode
data: 2026-08-11
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): DISPATCH_TIERS substitui os tiers hardcoded do dispatch-escalate.sh e dispatch-batch.sh aceita 4o campo opcional model_ref por item (tier unico via env so daquele item); tests/test-model-override.sh (construido via dispatch GLM 5.2 free, run 36E63816, revisado)
status: promovido
---

# dispatch-batch (2.2) nao honra o roteamento v3 — tiers hardcoded

## Sintoma

O lote do wizard TravelView (5 frentes nao-visuais) precisa rodar no tier
cheap `deepseek-v4-flash-free` (zen, confirmado vivo por smoke em 2026-08-11,
tabela do docs/prompts/PROMPT-TRAVELVIEW-V3-REFATORACAO.md). `bin/dispatch-batch.sh`
delega cada item a `bin/dispatch-escalate.sh`, cujos tiers sao fixos:

    dispatch-escalate.sh:69-73
    case "$MODE" in
      1) TIERS=("openrouter/deepseek/deepseek-v4-flash") ;;
      2) TIERS=(... v4-flash v4-pro) ;;
      3) TIERS=(... claude:opus) ;;

Nao ha como apontar o lote pro modo overlay do workdir
(`refatoracao_next_ready`, model_ref free) nem pro tier cheap do registry.

## Causa

EVIDÊNCIA: `grep -nE "flash|pro|opus|tier" bin/dispatch-escalate.sh` mostra
TIERS hardcoded openrouter/claude; nenhuma leitura de `core/modes/*.yaml` ou
env de modelo. O roteamento v3 (cheap zen free primeiro, fallback paid
`deepseek/deepseek-v4-flash-direct`) so existe via `oracfit run <mode>` com
mode overlay (AD-16). Alem disso `openrouter/deepseek/deepseek-v4-flash` tem
sucessor lancado 2026-08-01 (`deepseek-v4-flash-0731`, registry) — o batch
pode estar despachando id em fim de vida.

Consequuencia: "muitas frentes em loop" (v2.2) e "modelo barato vivo" (v3)
ainda nao combinam num unico mecanismo.

## Correção aplicada

Workaround nesta sessão (mesma familia do workaround de
`2026-08-11-prompt-v3-travelview-espera-override-dis`): loop SEQUENCIAL de
`oracfit run refatoracao_next_ready specs/<fN>.md <task> --workdir ...`
(1 por vez — RAM limitada), com gates antecipados em TODAS as specs
(check-spec + facts + check-oracle) antes do primeiro modelo ser chamado —
a garantia 3 do dispatch-batch replicada manualmente. Checkpoint/rollback =
commit por frente (o proprio modelo commita) + `git revert` se necessario.

Nenhuma mudanca no framework nesta sessao.

## Pode acontecer de novo?

Sim — todo lote v2.2 cai nisso. Candidata a regra/mecanismo: tiers do batch
configuraveis por mode yaml do workdir ou por campo no batch file
(`spec|task|workdir|model_ref`), fechando o circuito v2+v3.
