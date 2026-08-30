# S7 — Single-flight per workdir + canonical run verdict (rule 53, mechanisms 1–2)

Mode: glm_smart or hand-implemented under the same oracle discipline ·
gauntlet on · safety ceiling 4 · **file ceiling: 8 files**
Order: after the go-live/s1-s6 branch merges. Protects the exact first hour
the ad promises: a stranger double-launching runs must get a refusal, not an
overlapping rewrite; a verdict must come from a command, not from a grep.

## Goal

Build mechanisms 1 and 2 of rule 53 (SKILL.md): (1) a second dispatch into a
workdir that already has a live dispatch REFUSES instead of overlapping;
(2) `oracfit status --task <name>` is the canonical verdict surface — raw
grep of events.jsonl stops being a decision path. Mechanism 3 (sha256
imprint on green) stays declared as pending debt; it is NOT in this story.

## Verified data (dados verificados)

- Incident incidents/2026-08-27-dogfooding-tres-despachos-no-mesmo-workdir-e-veredito-lido-grepa-crud.md:
  three dispatches overlapped 7+ minutes in one workdir; the operator read a
  pass belonging to a PREVIOUS run via raw grep of run_finished; cost 30 min
  plus a night of lost translations. Mechanisms 1–2 are proposed there.
- Rule 53 (SKILL.md, branch go-live/s1-s6) declares all three mechanisms
  PENDING — this story flips 1 and 2 to built and leaves 3 pending.
- Dispatch entrypoints: bin/dispatch-mode.sh (single-stage) and
  bin/dispatch-stages.sh (multi-stage); bin/oracfit cmd_run picks one by
  stage count after resolving surf aliases. Both must hold the lock — a lock
  only in cmd_run would not survive the exec.
- The dispatcher already writes, per run: .dispatch/logs/events.jsonl
  (run_id events; run_finished carries a status), .dispatch/ledger/ and
  .dispatch/logs/inbox/<run_id>.spec-file (spec/mode/task persisted —
  cmd_resume depends on it).
- adapters/stub/runner.sh honors ORACFIT_STUB_SLEEP (sleeps N seconds in
  1s steps) — the hook this story's concurrency test needs; no real model.
- Hosts include macOS with bash 3.2 and no flock(1)/timeout(1) (SKILL.md and
  the cmd_modes comment in bin/oracfit). The lock must be portable: atomic
  mkdir of .dispatch/.run-lock/ plus a pid file inside, never flock.

Do not invent (nao invente) event fields, file formats, flags or numbers
beyond those listed above (alem destes). If the task name is not recoverable
from the files the dispatcher already writes, recording it at run start
becomes part of this story — do not guess a field that is not there.
NUNCA use declare const or any phantom reference — read the real files.

## Work

1. Portable single-flight in BOTH entrypoints (dispatch-mode.sh and
   dispatch-stages.sh), before any preflight: atomically mkdir
   WORKDIR/.dispatch/.run-lock/ and write the owner pid inside. Held for
   the whole run, released on every exit path (trap). If the lock exists:
   owner pid alive (kill -0) → refuse with a one-line message naming the
   owner pid and the lock path, exit distinct and documented; owner pid
   dead → announce the stale lock, take it over, proceed. The refusal
   message must NOT advertise how to force-remove (rule 47 spirit).
2. `oracfit status --task <name>` (cmd_status in bin/oracfit): emits one
   JSON object — run_id, status, attempts, last_oracle_exit — for the MOST
   RECENT run recorded with that task name in this workdir, sourced from
   the files the dispatcher already writes. Unknown task → JSON with
   status not_found, exit 3. Also register in the two help texts.
3. Update rule 53 in SKILL.md and its line in fluxos/_comum/mapa-regras.md:
   mechanisms 1–2 built (name the scripts), mechanism 3 still pending.
4. New tests/test-single-flight-status.sh: in a mktemp workdir with the
   stub runner and ORACFIT_STUB_SLEEP holding run A alive, run B in the
   same workdir must refuse while A is alive, and A must finish green;
   after A, status --task returns A's run_id and status pass; a stale lock
   (dead pid written by the test) is taken over, not refused. Update the
   suites count in site/app.js and site/llms.txt;
   tests/test-site-honesty.sh stays green.

## Do not touch

The gauntlet/oracle logic, adapters/ (the stub already has the hook),
tests/test-go-live-local.sh (the gate is frozen; it may gain this test in a
later story), LICENSE, core/modes/, model-registry.json.

VERIFICACAO: grep -q ORACFIT_STUB_SLEEP adapters/stub/runner.sh

## Barra

- reference: the "Mecanismos propostos" section of the 2026-08-27 incident
  and the rule 53 text — the implementation must match what the rule
  promised, or the rule text is the thing to fix first.

## Oraculo

- comando: bash tests/test-single-flight-status.sh && grep -q cmd_status bin/oracfit && grep -qi "run-lock" bin/dispatch-mode.sh && grep -qi "run-lock" bin/dispatch-stages.sh && bash tests/test-site-honesty.sh

Exit 0 only after: overlapping dispatch refuses with the owner pid, stale
lock recovers, the verdict has a canonical command, and rule 53's debt line
tells the truth about what is now built.
