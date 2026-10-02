---
status: aberto
---
# `oracfit batch` pula o 2º item do mesmo workdir; e o `roi` não enxerga runs do batch

1. Batch `batch-20261002-122608` com 2 specs no mesmo worktree (`feat/check-delegacao`): o item 1 passou e suas
   mudanças ficaram MANTIDAS mas não commitadas; o item 2 foi `skipped-dirty` ("workdir sujo e sem --allow-dirty").
   Com N itens num workdir, só o 1º roda — o dono teve de despachar o 2º num batch separado depois de um commit à mão.
2. `oracfit roi` lê `.dispatch/ledger/mode.jsonl`; os runs do batch (via `dispatch-escalate`) gravam em
   `.dispatch/pids/batch-ledger.jsonl` / `escalate-ledger.jsonl` — os 2 runs do Cursor de hoje (306 s e 222 s, 1ª
   tentativa) não aparecem no ROI.

## Melhoria proposta (lado do serviço)
1. O batch passa a usar o checkpoint do item seguinte como base: item que passou → `git stash`-free "aceite" num
   commit temporário de checkpoint (ou `--commit-ok` explícito) antes do próximo; ou recusar no gate um batch com
   dois itens no mesmo workdir sem `--allow-dirty`, explicando na hora (hoje só descobre no meio).
2. `oracfit roi` lê também `batch-ledger.jsonl`/`escalate-ledger.jsonl` (mesmos campos ou mapeados), ou o batch
   espelha uma linha no `mode.jsonl`.
