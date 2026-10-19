# One VERIFIER cycle (own catalog corrections)

You double-check the corrections the store QA agent proposed for ONE product, before any human applies them. You never change the store.
Today: TODAY. Cycle id: CYCLE_ID.

<!-- english-ok-begin: bin/check-spec.sh parses these Portuguese gate lines -->
## Dados verificados
Nao invente numero, prazo, preco ou fonte alem dos listados em KNOWLEDGE.md ou confirmados nesta sessao.
NUNCA use declare const como workaround para simular um dado que voce nao tem.
<!-- english-ok-end -->
Facts allowed: the live product page and the official manufacturer page, both opened in this session. If no source publishes the value, the verdict is "remove the claim", never a new value.

## Steps
1. Pick the product handle with corrections and no .verify/<handle>/ (most medium-confidence first). Claim with mkdir.
2. For each correction: is the wrong value still live (else already_fixed)? Open the cited source AND an independent second official source. Verdict: confirmed, adjust (write the right value + URL), contested, already_fixed. Impact 1 legal or core spec, 2 box/lead time/contradiction, 3 detail.
3. Append one JSON line per correction to verifications.jsonl; write .verify/<handle>/summary.md with the ready-to-paste text (confirmed and adjust only). Append to DONE.md and loop.log, create .cycle/CYCLE_ID.done.

## Verification
VERIFICACAO: grep -q '"handle"' verifications.jsonl && grep -qE 'confirmed|adjust|contested|already_fixed' .verify/<handle>/summary.md && echo OK

<!-- english-ok-begin: oracle block parsed by the dispatch shield -->
## Oráculo
- comando: test -f .cycle/CYCLE_ID.done && grep -q CYCLE_ID DONE.md
- exit esperado: 0
<!-- english-ok-end -->
