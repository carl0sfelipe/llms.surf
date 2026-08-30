# Stranger → hooked, in under 1 hour

> Every step is a command plus what the human actually sees. Testable: if a
> step's "you see" line does not happen, the journey is broken and that is
> an incident, not a shrug. Times are budgets, not promises of speed.

## 0:00–0:02 — First wave (no API key, no signup)

```bash
git clone https://github.com/carl0sfelipe/llms.surf.git
cd llms.surf
export ORACFIT_ROOT="$PWD" DISPATCH_RUNNER="$PWD/adapters/stub/runner.sh"
bin/llms-surf start
```

**You see:** a live dispatch log ending in a green oracle line — the stub
runner did the work, a real command on disk (`grep -q stub_ok
.dispatch/stub-proof`) decided it shipped. That is the whole product in
one screen. *(Blocked today by the missing smoke spec — spec S1 fixes it.)*

## 0:02–0:05 — Look at the lineup

```bash
bin/llms-surf
```

**You see:** the menu. Option 1 replays the first wave; option 3 lists the
three waves — `paddle (normal)`, `tow (unlock_plan)`, `surfcheck
(ui_visual_qa)` — plus any breaks of your own. Option 2 shows today's
spend (zero so far: the stub costs nothing).

## 0:05–0:15 — Plug your real CLI

```bash
source adapters/opencode/env.sh   # or claude-code, cursor, hermes, qwen-code, llama.cpp, zcode, prime-agent
```

**You see:** `DISPATCH_RUNNER` now points at your CLI's runner. Your key
stays in your CLI's own config — llms.surf never asks for it.

## 0:15–0:25 — First paddle on real work

```bash
cp examples/first-wave.md my-task.md
$EDITOR my-task.md        # describe the chore; put a real command under ## Oraculo
bin/llms-surf run normal my-task.md my-task
```

**You see:** a cheap model doing the chore, then the oracle verdict. If the
model claims victory and the command exits 1, the run is red. Your word is
not the gate; neither is the model's.

## 0:25–0:35 — First tow (get unstuck)

```bash
bin/llms-surf run unlock_plan my-hard-task.md tow-1
```

**You see:** three stages — an expensive model reads the wave (unlock), a
mid model plans the line, a cheap model rides it. A red unlock never
starts the run.

## 0:35–0:50 — Name your break

```bash
bin/llms-surf mode init my_break
$EDITOR core/modes/my_break.yaml     # 2-3 line edit; card: docs/go-live/CUSTOM-MODE-CARD.md
bin/llms-surf mode validate my_break
bin/llms-surf mode lint my_break
bin/llms-surf run my_break my-task.md break-1
```

**You see:** `OK … roles=[…]`, `LINT OK`, then your own pipeline closing a
run with a green oracle. Private by default — the file lives only in your
workdir.

## 0:50–1:00 — Share the break

```bash
bin/llms-surf mode share my_break    # prints the canonical YAML + provenance
```

**You see:** a paste-ready YAML (no keys, no secrets by construction). Post
it — gist, tweet, the repo's "share your break" thread. A friend runs
`bin/llms-surf mode add my_break.yaml` and it installs only after
validate + lint pass on *their* machine.

---

**Hooked =** within one hour the stranger has: a green oracle they did not
have to trust anyone for, one real task done by a cheap model, one mode
with their own name on it, and a file they can show a friend.
