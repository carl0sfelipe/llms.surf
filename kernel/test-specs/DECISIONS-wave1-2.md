# Decisions after waves 1–2 (Fable, 2026-09-19 15:05 -03)

Input: orchestrator checkpoint (17 branches `p1-*`, 31/31 promoted paths
verified, T11 red on L3). These decisions unblock T11 → T18/T19/T20.
`src/` may be changed **only** in the integration branch named below.

## D-L3 — L3 was false as stated; L8 makes it true

Ties in `(keyless, context, ref)` exist only for duplicate refs, and a
stable sort then leaks file order. Decision:

1. **Adopt L8 (T16) as a precondition of L3**: in `catalog_order`, sort by
   the key, then **dedupe by `ref` keeping the first** (= the best-ranked
   occurrence). Output refs are distinct, the key is a strict total order
   on distinct refs, so the output is a pure function of the catalog *as
   a set*. Restate L3 in `P1.md`: "the ordered chain is a function of the
   set of catalog entries; refs are unique (L8); for any two entries in the
   output the key is strictly increasing".
2. Divergence from the shell (T03: shell collapses meta per ref
   last-wins and may exit 2 where Rust exits 0) is **recorded as a
   Decision, Rust wins**: retrying the same ref twice or gating on the
   wrong occurrence's provider is the E5 smell. Vector
   `T03_duplicate_ref_shell_exit2_rust_still_ok` stays green with the
   *Rust* expectation. Add it to T03's harness exclusion list.
3. `l3_cheap_order` generator: keep duplicates in the input (they must be
   handled), assert on the deduped output.

## D-L6 — merge T06's test; keep the guards

The guards in `Chain::new` stay (they are the type's contract); T06's
`l6_chain_new_rejects_empty` is what makes them observable. Merge.

## D-L1c — CR is a delimiter too

`Chain::new` rejects `\r` alongside `\x1f` and `\n` (T07). One line +
extend `l1b`. No decision needed beyond this.

## D-EXIT — corrupted catalog is exit 3, not "absent"

`main.rs` currently turns an unparsable catalog into WARN + `CatalogMissing`
(exit 2). Decision (T05): absent file → `CatalogMissing`, exit 2; present
but unreadable/invalid JSON/wrong `kind` → `ERROR`, exit 3, stdout empty.
"Never degrade" includes never downgrading corruption to absence. Vector +
Decisions row.

## D-PROVIDER / D-WIRE / D-ENV — accept T14, T15, T17 as promoted

`provider: ""` → `None` at parse; tri-state `-` on the wire for the
direct path (shell reads `-` ≠ `1` → passes the gate, verified by
reading); env-isolation test in tree. Order of application below matters
because all three touch `src/lib.rs`.

## D-SHELL — WARN swallowed is T18's first line item

`run-with-fallback.sh` re-emits the kernel's stderr in shadow/on modes
(T08 F1). Not a kernel change. Also from T08: `id_status: null` crashes
the shell's inline Python — one more reason the shadow flag exists; add
it as a T18 vector on the shell side.

## D-QUALITY — fmt + clippy are gates, fixed once in integration

`cargo fmt` and `clippy -D warnings` fixed in the integration branch and
enforced by T12's CI from then on. No exceptions list.

## D-DISPATCH — the three dispatcher findings are product incidents

Promote each as `incidents/2026-09-19-<slug>.md` in the llms.surf format
(the product's own loop):

1. `tier:cheap` is not dispatchable via `bin/dispatch.sh` without a mode
   YAML — runner exits 3. Fix path = T20's mode (`kernel_test.yaml`) plus
   a one-line `dispatch.sh` hint pointing at `dispatch-mode.sh` when the
   model ref is `tier:*`.
2. Single `.git` lock forbids parallel dispatch → backlog line
   ("per-worktree lock"), not fixed now.
3. Runner rewrites `~/.zcode/cli/config.json` → **bug**; scope the write
   to the workdir or a flag. Incident + regression test in the shell
   suite. This one is severity high: it touches the owner's machine.

E5 stays unmeasured until T20 exists; say so in the research doc.

## D-MERGE — one integration branch, fixed order, then main

Branch `p1-integrate` from `main`:

1. commit the second-wave spec files as promoted (verbatim from T12/T13);
2. merge `p1-wave1` (T01–T10 artifacts);
3. apply T14 → T16(+D-L3 restatement) → T15 → T17 → D-L1c → D-EXIT,
   re-pinning vectors after each step (`cargo test --release` green before
   the next);
4. fmt + clippy;
5. T12 (CI) and T13 (law gate) on top; T13 must pass with L8 present;
6. `P1.md`: Decisions table gets one row per D-* above, dated.

Oracle for merging `p1-integrate` → `main`: `cargo test --release` with
`PROPTEST_CASES=5000` green on 3 different seeds; T13 gate green; T06's 15
mutations re-run on the integrated tree, 15/15 killed; T03 harness
re-run (2 000 iterations) with the documented exclusion classes only.

Then T18 → T19 → T20, sequential, each merged to main on its own oracle.

## Unpromoted items — closed

- T02 F3 (error-class distribution): becomes a `note` row in `BENCH.md`
  (numbers, no action). Closed.
- T09 F9 (dead Python branches): closed by T18 — the shell path is
  replaced, not cleaned.
- T10's 5 proposed vectors: add the ones that are not duplicates of T05/
  T09 pins during D-MERGE step 3; the orchestrator decides which by
  `name`+`expect` equality.

## Pacing

Keep ≤ 3 concurrent subagents. The integration branch is **one** agent,
sequential by design.
