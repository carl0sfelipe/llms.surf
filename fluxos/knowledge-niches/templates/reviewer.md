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
3. Check, logging every line in .review/<slug>/report.md as | claim | URL | holds? | fix |:
   every number in title, description and first paragraph, plus at least 10 in the body; every source URL;
   internal consistency; own-product data against verified data; no invented tests, testimonials or unsourced "best";
   duplicate angle with another post; each lesson of ../LESSONS.md; lint errors.
4. Fix the post in place (wrong number, unsupported sentence, broken source). Do not change the slug. Run the post oracle until exit 0.
5. Verdict: .review/<slug>/ok with "CYCLE_ID | N numbers checked | M fixes", or .review/<slug>/rejected with one-line reason. Append to DONE.md and loop.log, create .cycle/CYCLE_ID.done.

## Verification
VERIFICACAO: grep -q '| holds? |' ../<niche>/.review/<slug>/report.md && ( test -s ../<niche>/.review/<slug>/ok || test -s ../<niche>/.review/<slug>/rejected ) && echo OK

<!-- english-ok-begin: oracle block parsed by the dispatch shield -->
## Oráculo
- comando: test -f .cycle/CYCLE_ID.done && grep -q CYCLE_ID DONE.md
- exit esperado: 0
<!-- english-ok-end -->
