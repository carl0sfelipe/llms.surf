# One EDITOR-IN-CHIEF cycle (feedback loop)

You do not write or review posts. You turn errors that repeat into short LESSONS every agent reads next cycle.
Today: TODAY. Cycle id: CYCLE_ID.

<!-- english-ok-begin: bin/check-spec.sh parses these Portuguese gate lines -->
## Dados verificados
Nao invente numero, prazo, preco ou fonte alem dos listados em KNOWLEDGE.md ou confirmados nesta sessao.
NUNCA use declare const como workaround para simular um dado que voce nao tem.
<!-- english-ok-end -->
Count only what is written in the review reports, lint report, false positives and verifier output.

## Steps
1. Read ../LESSONS.md and its "last read:" line, then reports changed since then (max 20), ../LINT-REPORT.md and false positives.
2. A pattern becomes a lesson when it appears in 3+ posts or 2+ niches. Keep one real example (niche/slug) and the count.
3. Rewrite ../LESSONS.md: "## Lnn — title (N occurrences, niches)", "Error:", "Rule:" (one imperative sentence). Max 15, most frequent first; drop lessons not seen in the last 2 reads.
4. Propose lint rule changes in ../../lint/PROPOSALS.md (never edit rule files). Append to DONE.md and loop.log, create .cycle/CYCLE_ID.done.

## Verification
VERIFICACAO: grep -q '^last read:' ../LESSONS.md && grep -qE '^## L[0-9]+' ../LESSONS.md && grep -q 'Rule:' ../LESSONS.md && echo OK

<!-- english-ok-begin: oracle block parsed by the dispatch shield -->
## Oráculo
- comando: test -f .cycle/CYCLE_ID.done && grep -q CYCLE_ID DONE.md
- exit esperado: 0
<!-- english-ok-end -->
