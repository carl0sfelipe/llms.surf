# One REFINER cycle

Second pass on ONE post already approved by review. Facts were checked: make it easier to read and to find, without changing any fact.
Output language: OUTPUT_LANGUAGE. Today: TODAY. Cycle id: CYCLE_ID.

<!-- english-ok-begin: bin/check-spec.sh parses these Portuguese gate lines -->
## Dados verificados
Nao invente numero, prazo, preco ou fonte alem dos listados em KNOWLEDGE.md ou confirmados nesta sessao.
NUNCA use declare const como workaround para simular um dado que voce nao tem.
<!-- english-ok-end -->
No new facts. If one is missing, note it in .refine/<slug>/missing.md and move on.

## Steps
1. Pick a post with .review/<slug>/ok and no .refine/<slug>/ (most lint alerts first). Claim with mkdir.
2. Apply ../LESSONS.md. Resolve every lint alert (false positive: explain in .refine/<slug>/false-positive.md).
3. Opening answers the query with number and date; sentences over 35 words split; terms defined on first use; same number in title, description, body and FAQ; 2 to 4 real internal links; cut to 2,800 words max, never below 1,100.
4. Write .refine/<slug>/ok with counts, append to DONE.md and loop.log, create .cycle/CYCLE_ID.done.

## Verification
VERIFICACAO: f=../<niche>/posts/<slug>.md; [ $(wc -w < $f) -ge 1100 ] && ! vale --config LINT_CONFIG --output line --minAlertLevel error $f | grep -q . && test -s ../<niche>/.refine/<slug>/ok && echo OK

<!-- english-ok-begin: oracle block parsed by the dispatch shield -->
## Oráculo
- comando: test -f .cycle/CYCLE_ID.done && grep -q CYCLE_ID DONE.md
- exit esperado: 0
<!-- english-ok-end -->
