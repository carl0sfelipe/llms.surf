# One REVIEWER cycle

You verify ONE written post, fix it in place and give a verdict. Quality over speed.
Output language: OUTPUT_LANGUAGE. Today: TODAY. Cycle id: CYCLE_ID.

<!-- english-ok-begin: bin/check-spec.sh parses these Portuguese gate lines -->
## Dados verificados
Nao invente numero, prazo, preco ou fonte alem dos listados em KNOWLEDGE.md ou confirmados nesta sessao.
NUNCA use declare const como workaround para simular um dado que voce nao tem.
<!-- english-ok-end -->

## Steps
1. Pick the OLDEST post without ../<niche>/.review/<slug>/. Claim with mkdir (same rule as writers).
2. Read ../LOOP.md, ../DIRECTIVE.md, ../LESSONS.md, SPEC.md, the post and ../<niche>/.lint/<slug>/lint.txt.
3. Start from ../<niche>/posts/<slug>.claims-check.md (run ../../bin/check-claims.py on the post first if it is missing or older than the post).
   Every claim marked source_changed, value_not_in_snippet, fetch_failed or not_in_post, every "number without a claim" and every "fact with two values" MUST be resolved; the claims marked ok need only the sampled spot check, unless the lint or a lesson points at them.
   Posts without a manifest (written before the manifest existed): build one while you review, then run the checker.
4. Then check, logging every line in .review/<slug>/report.md as | claim | URL | holds? | fix |:
   the numbers the checker could not settle; every source URL;
   internal consistency; own-product data against verified data; no invented tests, testimonials or unsourced "best";
   duplicate angle with another post; each lesson of ../LESSONS.md; lint errors.
5. Fix the post in place (wrong number, unsupported sentence, broken source). Do not change the slug. Run the post oracle until exit 0.
6. Verdict: .review/<slug>/ok with "CYCLE_ID | N numbers checked | M fixes", or .review/<slug>/rejected with one-line reason. Append to DONE.md and loop.log, create .cycle/CYCLE_ID.done.

## Verification
VERIFICACAO: grep -q '| holds? |' ../<niche>/.review/<slug>/report.md && ( test -s ../<niche>/.review/<slug>/ok || test -s ../<niche>/.review/<slug>/rejected ) && echo OK

<!-- english-ok-begin: oracle block parsed by the dispatch shield -->
## Oráculo
- comando: test -f .cycle/CYCLE_ID.done && grep -q CYCLE_ID DONE.md
- exit esperado: 0
<!-- english-ok-end -->
