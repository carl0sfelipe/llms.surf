# E1 — Bend 2: install, reproduce the law demo, measure the checker

Purpose: turn the bend-lang.com claims into numbers from this machine
before any Bend code touches llms.surf. Owner: ZCode. Budget: one
afternoon. Nothing here is a product change.

## Preconditions

- Omarchy desktop (Linux, RTX 3090 available for the GPU leg).
- Network for the installer only; everything else offline.
- `~/bend/` is the playground (owner-designated).

## Steps and the number each one produces

| # | Step | Record in `~/bend/E1-RESULTS.md` |
|---|---|---|
| 1 | `curl -fsSL https://bend-lang.com/install.sh \| sh` — **read the script first**, note version/commit installed | version, install time, anything the script touches outside `~/.bend`/`~/.local` |
| 2 | `bend guide` → save to `~/bend/GUIDE.md` (the site says the guide is the whole language; the raw GitHub file 404s) | line count; headings |
| 3 | Reproduce the site demo: game with `LAWS.bend` (`you_cant_win`) + `PROOF.bend`; run `bend PROOF.bend` | exit code; wall-clock of the check (`/usr/bin/time -v`) |
| 4 | Break the law on purpose (the "wrap around" change from the site) and re-check | does the checker reject? error message quality (does it point at the law and the line?) |
| 5 | Let an agent (ZCode itself, cheap tier via llms.surf `paddle`) repair the proof; count attempts until `bend PROOF.bend` exits 0 | attempts, minutes, which model, cost from the ledger |
| 6 | `pow2`/game-of-life sample: 1 core vs all cores vs GPU (`bend` flags per the guide) | table: seconds per mode on this machine; compare with the M4 Max numbers on the site — as *reproduction*, not endorsement |
| 7 | Stability probe: run steps 3–4 ten times; any nondeterminism or crash? | count |

## Acceptance

- `E1-RESULTS.md` exists with all seven rows filled with numbers or an
  explicit "failed: <reason>".
- No Bend artifact was added to the llms.surf tree.
- If step 3 or 4 fails (checker does not reject a broken law), **stop E2**
  and report: the premise of the whole convergence is false at this
  version.

## What this decides

- Step 4 → whether "AGENTS.md backed by proof" is real today.
- Step 5 → first data point for H-Bend-1 (can a cheap model close a
  proof with a fast judge?).
- Step 6 → whether the performance claims transfer to our hardware.
