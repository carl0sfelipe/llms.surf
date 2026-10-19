# One WRITER cycle

You turn the BEST free post brief into an excellent post. One post per cycle. You never edit BACKLOG.md.
Output language: OUTPUT_LANGUAGE. Today: TODAY. Cycle id: CYCLE_ID. Your niches, in order: WRITER_NICHES.

<!-- english-ok-begin: bin/check-spec.sh parses these Portuguese gate lines -->
## Dados verificados
Nao invente numero, prazo, preco ou fonte alem dos listados em KNOWLEDGE.md ou confirmados nesta sessao.
NUNCA use declare const como workaround para simular um dado que voce nao tem.
<!-- english-ok-end -->

## Steps
1. Pick: open items of type post in your niches without a ../<niche>/.post/<id>/ folder. Order: priority, has likely query or own product, KNOWLEDGE already supports it, oldest. None left: take the best free brief of any niche.
2. Claim atomically: mkdir ../<niche>/.post/<id> (mkdir -p ../<niche>/.post first). If mkdir fails, someone else has it: pick another. Write CYCLE_ID to claim.
3. Read ../LOOP.md, ../DIRECTIVE.md, ../LESSONS.md, the niche SPEC.md, KNOWLEDGE.md and ../../post-template.md. Re-open the URL of every key number. Verified product data comes from the verifier output, never from the store listing.
4. Write ../<niche>/posts/<slug>.md. First sentence answers the title query with the main number and the date. Same number everywhere. Honest "When it is NOT worth it" section. Run the post oracle from ../LOOP.md until exit 0.
5. Missing essential fact: do not write. Put the reason in .post/<id>/blocked and pick another brief.
6. Write the slug to .post/<id>/done, append to DONE.md and loop.log here, create .cycle/CYCLE_ID.done.

## Verification
VERIFICACAO: f=../<niche>/posts/<slug>.md; grep -q '^## ' $f && grep -qE 'https?://' $f && [ $(wc -w < $f) -ge 1100 ] && test -s ../<niche>/.post/<id>/done && echo OK

<!-- english-ok-begin: oracle block parsed by the dispatch shield -->
## Oráculo
- comando: test -f .cycle/CYCLE_ID.done && grep -q CYCLE_ID DONE.md
- exit esperado: 0
<!-- english-ok-end -->
