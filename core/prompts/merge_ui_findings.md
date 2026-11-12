# Merge visual findings into one report

You receive the JSONL findings of the previous stage (one object per
screenshot). Merge them into a single report a reviewer can act on.

Output, in the stage's artifacts directory:

1. `report.json` with:
   - `overall_severity`: the worst severity across the findings
   - `pages`: the findings, grouped by `screenshot`
   - `critical_count`, `major_count`, `minor_count`
   - `top_issues`: the distinct problems, most severe first, each with
     the screenshots that show it
2. `report.md` — the same facts as prose: worst severity on the first
   line, then one bullet per top issue, then a short "what to fix first".

Do not drop a finding. Do not add a bug that was not in the JSONL.
The runtime fails this stage if the artifacts directory stays empty.
