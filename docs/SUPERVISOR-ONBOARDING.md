# Turning the supervisor on

The supervisor is **built and dormant**. This page is the short version of
what it takes to wake it up, and what it will do when it wakes up.

The full design is in `docs/decision-supervisor.md`. The contract of each
piece is next to the piece: `core/supervisor/policy.md` (the policy and
the order), `docs/SYSTEMONE.md` (the client), `core/supervisor/README.md`
(the question set).

## What happens today, in order

1. A run fails an attempt. At the **attempt boundary** the runtime asks
   the supervisor (`bin/oracfit-supervisor-ask.sh`): export the typed
   question set, `POST` the endpoint, hand the answers to the policy
   engine.
2. The engine (`bin/oracfit-policy.py`) turns the typed answers into
   **one order**: `CONTINUE`, `INJECT_HINT`, `RESET` or `ESCALATE`.
3. The runtime applies the order (`bin/lib-oracfit-supervisor.sh`): the
   hint travels to the next attempt's spec, the reset restores the tree
   from the checkpoint (keeping the evidence in a WIP ref), the escalate
   leaves the question in the inbox and pauses the run with status
   `owner_question` and exit 7.

The supervisor is consulted **only after a failed attempt**. A run that
passes on its first attempt ends without any order.

Both runtimes are wired: the single-stage (`bin/dispatch-mode.sh`) and
the multi-stage (`bin/dispatch-stages.sh`).

## The three things only the owner can do

### 1. Choose the endpoint (this is D1)

The endpoint has **no default**. Nothing in the repo points at a host, a
port or a URL. The owner sets it:

```
export ORACFIT_SUPERVISOR_ENDPOINT="http://127.0.0.1:8080/v1/systemone"
```

The endpoint speaks the System-One shape (`docs/decision-supervisor.md`
§5.1) and answers `POST /v1/systemone`.

**The CPU option needs no GPU.** The decision-model family has a CPU
half that speaks the same API, so a `llama-server` with a small GGUF
(e.g. `Kev-4B-GGUF`, about 3 GB with context) on `127.0.0.1` is enough
for the short-state questions. It costs about 3-4 GB of RAM on this box,
and the box is the owner's only machine — starting it is the owner's
call, and it should not be started while the box is already loaded.

### 2. Calibrate the policy (the evidence)

The shipped policy is **not calibrated**, so the engine always answers
`CONTINUE` with the reason `not calibrated`. That is by design: there is
no threshold without evidence.

Calibration needs one ring scored by the owner
(`oracfit ring score RING-N --real N`). The ring stores the measured
`CALIBRATION` line on its own score event; the command copies that line
into a **derived** policy and takes the threshold from the owner:

```
python3 bin/oracfit-calibrate.py \
  --ring RING-N --target /path/to/target \
  --policy core/supervisor/policy.json \
  --act-above 0.85 \
  --out core/supervisor/policy.calibrated.json
```

The command refuses without a scored ring, never writes the source
policy, and **does not measure the threshold**: `--act-above` is the
owner's number.

### 3. Map the questions to actions (the judgment)

Even calibrated, the shipped policy has **empty rules**: no question maps
to an action, so the engine still answers `CONTINUE`. The rules are the
owner's judgment, one entry per question id of
`core/supervisor/questions.json`:

```json
"rules": {
  "r42-long-job-outside-dispatch-is-orphan": {
    "action": "ESCALATE",
    "pergunta": "which watchdog should cover this long-running job?",
    "se": ["se keep it outside dispatch -> ...", "se bring it under dispatch -> ..."]
  }
}
```

`INJECT_HINT` and `RESET` need a `hint`; `ESCALATE` needs a `pergunta`
and at least two `se ... -> ...` consequences. The engine refuses an
invalid policy and never writes the workdir.

The runtime picks the policy with `ORACFIT_SUPERVISOR_POLICY` (default:
`core/supervisor/policy.json`).

## The environment, all of it

| variable | meaning | default |
|---|---|---|
| `ORACFIT_SUPERVISOR_ENDPOINT` | the URL of `POST /v1/systemone` | none — without it, nobody asks |
| `ORACFIT_SUPERVISOR_POLICY` | the policy file the engine reads | `core/supervisor/policy.json` |
| `ORACFIT_SUPERVISOR_TIMEOUT` | the ceiling of the HTTP call, in seconds | 20 |
| `ORACFIT_SUPERVISOR_DECISION` | a hand-placed decision record; it wins over the ask | none |
| `ORACFIT_SUPERVISOR_RESTORE_REF` | the origin of a reset's restore | HEAD (the single-stage behaviour) |

## How to tell it is working

The run's event stream carries the whole story:

| event | meaning |
|---|---|
| `supervisor_ask` | the ask happened (the `result` says whether it worked) |
| `supervisor_order` | the order was applied, refused or a no-op, with the reason |
| `owner_question` | the run was paused for the owner |

The answers that came back are in the run's inbox, next to the decision
record, and the decision record is the engine's own record — the order,
not a verdict.

A failed ask never fails a run: the event says it failed, and the round
follows the mechanical path as if there were no order. The same is true
of a refused order.
