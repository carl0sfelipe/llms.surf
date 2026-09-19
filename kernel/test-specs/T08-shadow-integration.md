# T08 — Shadow integration with the live shell (read-only)

Question: on the real tree, with the real credential reader, does the
kernel produce exactly the `CHAIN_META` the shell builds today — for
every tier and for the direct-id path? No shell file is modified.

## Setup

- Worktree of llms.surf; `cargo build --release` in `kernel/`.
- Source the credential lib the way the shell does and derive the
  provider set: `source bin/lib-free-credentials.sh` and, for each
  provider in `data/free-provider-allowlist.json`, call
  `free_cred_has_provider <p>`; collect the ones that return 0 into a
  CSV. Do this in **both** states: as the machine is, and with
  `HOME=/tmp/empty-home` (no auth files) to force the zero-key state.

## Steps

1. Extract the shell's reference: copy the inline Python from
   `bin/run-with-fallback.sh` (the block that prints `FS.join(...)`) into
   `/tmp/t08/ref.py` **unchanged** except for reading env like the shell
   does. Run it for `MODEL=tier:cheap` with the real `REG` and `CATALOG`.
   Then apply the shell's credential loop (lines ~80–90) in a tiny bash
   harness to get the post-gate list.
2. Run `dispatch-policy resolve tier:cheap ... --credentials <csv>`.
   Oracle: byte-identical post-gate US lines (`diff <(…) <(…)`), in both
   credential states.
3. Repeat for `tier:mid`, `tier:expensive`, `tier:vision`. Oracle:
   identical single line each (ref, status, provider, keyless).
4. Direct-id path: for **every** `id` in `model-registry.json` and every
   string value in its `cli_hints`, compare the shell's non-tier branch
   output (the second inline Python, ~lines 96–116: `id\tstatus` list +
   provider map) with `dispatch-policy resolve <id>` fields 1–3. Oracle:
   identical ref/status sequence and provider per ref. (Field 4 `keyless`
   is not consumed on this path; ignore it.)
5. Dead-id WARN parity: temporarily point `--registry` at a **copy** of
   the registry where one catalog ref is stamped `FANTASMA`; confirm both
   sides skip it and both emit a WARN mentioning E5-M2.
6. Timing of the whole `tier:cheap` resolution: shell path (Python
   subprocess ×2) vs binary. Report ms.

## Oracle

PASS = zero diffs in 2–5. Any diff is a `bug` with the exact inputs
attached (registry/catalog copies under `/tmp/t08/`).
