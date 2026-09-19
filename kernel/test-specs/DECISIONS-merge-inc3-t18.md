# Decisions — merge, incident 3, T18–T20 (Fable, 2026-09-19 17:30 -03)

## D-MERGE-APPROVE — yes, merge `p1-integrate` → `main`

Oracles 4/4 green as reported (O1 3 seeds × 5000; O2 gate with L8; O3
15/15 mutations on the integrated tree; O4 2000 iterations, mismatches
100 % inside the documented duplicate-ref class). Approved:

1. `git merge --no-ff p1-integrate` into `main`. Conflict on
   `kernel/test-specs/T11-T20-second-wave.md`: keep **main's** copy
   (`1e69908`) — identical content, and main is the reference.
2. Then `p1-inc-1`, `p1-inc-2`, `p1-inc-3` → `main`, in that order
   (disjoint files).
3. After the merge, re-run `cd kernel && cargo test --release` and
   `kernel/scripts/check-laws.sh` on `main` once. Record both exit codes
   in `kernel/test-specs/reports/MERGE.md`. That file is the receipt.

## D-INC3 — path (a) with a measured fallback; never (b) alone

Facts: the adapter already reads `ZCODE_CLI_CONFIG`; the zcode binary
(Electron AppImage) has no `--model` and resolves `~/.zcode/cli/config.json`
through `HOME`. The only real question is whether the binary honours a
relocated home.

1. **Measure first (10 min):** run the *real* binary with
   `HOME=/tmp/zc-home` where `/tmp/zc-home/.zcode/cli/config.json` is a copy
   with a different `model.main`, and check which model it reports/uses
   (`zcode` prints the model on start, or use a stub provider URL in the
   copy and watch what it hits). Also try `XDG_CONFIG_HOME` and
   `--user-data-dir`. Write the result into the incident file.
2. **If a relocated home works:** per-dispatch overlay — the runner creates
   `<workdir>/.dispatch/zcode-home/.zcode/` with symlinks to everything
   under `~/.zcode` **except** `cli/config.json`, which is a modified copy;
   runs zcode with that `HOME`. The owner's file is never opened for
   writing. Auth/plugins/db keep working through the symlinks.
3. **If it does not:** write-then-restore under `flock` on the config
   path: back up, write, run, restore in a `trap` (EXIT/INT/TERM), plus a
   one-line notice on stderr before the run ("this dispatch temporarily
   sets your zcode model to X; restored on exit"). Concurrent dispatches
   serialize on the lock (the per-.git lock already does most of this).
4. **Regression test (both paths):** `sha256sum ~/.zcode/cli/config.json`
   before and after a stub dispatch must be identical; and after a
   dispatch killed with SIGTERM mid-run (path 3) it must also be
   identical. Lands in the same commit as the fix.

Rejected: (b) remove the write with opt-in — silently loses model
selection; (c) defer — the file is the owner's live config on a machine
he uses all day; severity stays high until 4 passes.

## D-T18/19/20 — proceed in order, one at a time

- T18 shadow mode from `p1-integrate` (now `main`), with the D-SHELL
  addenda: re-emit the kernel's stderr in `shadow|on`; a shell leg for
  `id_status: null`. "13/13" means the current suite (37 vectors) — the
  oracle is "all vectors + all legs", not a number.
- T19 `policy_version` in the ledger (additive).
- T20 `core/modes/kernel_test.yaml` — closes `p1-inc-1` and unlocks E5.
  **Design the mode so its tier/oracle shape is reusable by the BMAD
  team modes** (see `docs/research/bmad-tiers-2026-09-19.md`): the same
  YAML grammar, a `command:` oracle, `owner_question` where a human gate
  belongs.

Pacing unchanged: ≤ 3 subagents; long specs one at a time; dead agent →
inspect `/tmp/p1-<ID>`, discard uncommitted edits, relaunch.
