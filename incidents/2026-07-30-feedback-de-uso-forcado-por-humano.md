---
id: 2026-07-30-feedback-de-uso-forcado-por-humano
titulo: Feedback/incidente de uso do dispatch foi forçado por humano — harness não coletava sozinho
data: 2026-07-30
recorrivel: sim
regra: 41
status: promovido
interage_com: |
  reforça 16 (problema recorrente → regra), 23 (identificar candidato é contínuo),
  32 (regra declara mecanismo), 38 (fonte nova entra no relatório no mesmo commit —
  usage.jsonl é fonte; relatório ainda não lê — dívida menor), 40 (classificar
  task). Não supera 16/23: continua exigindo julgamento humano para PROMOVER;
  o que muda é a COLETA, que deixa de depender de pedido.
---

# Feedback de uso forçado por humano

## Sintoma

O incidente `incidents/2026-07-30-cursor-grok-primeiras-impressoes-do-disp.md`
(e a regra 40) só existiu porque o **humano pediu** feedback sobre o primeiro
uso do dispatch a partir do Cursor/Grok. Ledger e logs já existiam, mas nada
gerava incidente de uso automaticamente. Sem o pedido, a constituição não
crescia a partir do uso real.

## Causa

Evidência: o fluxo de feedback (`core/feedback-protocol.md` + regra 16/23)
assume identificação humana/orquestrador. `dispatch-escalate` / `batch` /
`dispatch.sh` gravavam ledger, mas **não** emitiam artefato de uso revisável
nem incidente. Coleta ≠ promoção — e a coleta estava ausente.

## Correção aplicada

1. `bin/emit-usage-feedback.sh` — coleta host/harness/git/spec/oracle/logs/env
   DISPATCH_*/ledger e grava:
   - `.dispatch/usage/usage.jsonl`
   - `incidents/uso/<id>.md` (`kind: uso-dispatch`, `recorrivel: nao`)
2. Ligado nos exits de `dispatch-escalate.sh`, fim de `dispatch-batch.sh`, e
   `ledger-finalize.sh` (dispatch simples).
3. Default `DISPATCH_USAGE_FEEDBACK=1`; opt-out `=0`.
4. `incidents/uso/*` gitignored (volume); README versionado.

## Correção proposta (regra)

Enquanto o dispatch está em desenvolvimento (`DISPATCH_USAGE_FEEDBACK≠0`),
**todo** modo de dispatch coleta o máximo de dados possível e gera incidente
de feedback de uso automaticamente — sem esperar o humano pedir.
