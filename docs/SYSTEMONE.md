# System-One client

The supervisor adapter. One client, two backends (llama.cpp on CPU today,
Eikos on a GPU later). The caller passes the endpoint; this program does not
choose a host, a port, or a URL. What it fixes is the **format**, already the
same on both servers (`docs/decision-supervisor.md` §5.1).

The `spec` and the `state` are the caller's. The client does not invent state,
does not read the ledger, and does not choose which questions to ask beyond
the `--ids` filter.

**The client asks and brings the answer — rung I is who decides.**

## Command

```
python3 bin/oracfit-systemone.py ask \
  --endpoint <url> \
  --questions <file.json> \
  --state <file.json> \
  [--ids <a,b,c>] \
  [--out <file.json>] \
  [--timeout <seconds>]
```

One subcommand: `ask`.

| option | meaning |
|---|---|
| `--endpoint` | URL of `POST /v1/systemone`. **Required. No default.** |
| `--questions` | JSON file in the export shape from `bin/oracfit-questions.py export`: an object with a `questions` object |
| `--state` | JSON file with the round's state. Loaded and sent as-is; never interpreted |
| `--ids` | comma-separated ids to ask. Default: every id in the questions file. An id that is not in the file is a usage error (exit 3) **before** any network call |
| `--out` | optional audit file (see Output file) |
| `--timeout` | time ceiling of the HTTP call, in seconds. Default: **30**. That default is a choice of this rung, not a measured number |

## Request body

`POST` to `--endpoint` with `Content-Type: application/json`. The body is
exactly the System-One shape of §5.1:

```json
{
  "state": "<contents of the --state file>",
  "questions": {
    "<id>": {
      "type": "choice",
      "instructions": "...",
      "criteria": {"a": "...", "b": "..."}
    }
  }
}
```

`questions` is the subset selected from the export file (`--ids`, or the
whole object). Each value is sent as it was in the file. `noul` has `type`
and `instructions`; `choice` and `score` also have `criteria`.

The client does not invent this shape.

## Response

A 2xx body must be JSON of the §5.1 shape:

```json
{
  "answers": {
    "<id>": { "... as the server sent it ..." }
  },
  "usage": { "input_tokens": 412, "output_tokens": 0 }
}
```

- a `noul` answer carries `noul` (the abstention mass)
- a `choice` answer carries `probabilities`, `choice` and `confidence`
- a `score` answer carries `probabilities`, `score` and `legend`

`usage` is optional. The client does not add, drop, or rewrite fields on an
answer. What arrived is what is stored.

## Output file

When `--out` is given, and only on success, the client writes a JSON object
with **exactly** these keys:

| key | value |
|---|---|
| `endpoint` | the URL that was called |
| `requested_at` | UTC instant of the call, `YYYY-MM-DDTHH:MM:SSZ` (example: `2026-01-01T00:00:00Z`) |
| `questions` | array of the ids that were asked, in the order they were sent |
| `answers` | the `answers` object **as it arrived**, no omitempty, no normalisation |
| `usage` | the `usage` object as it arrived, or `null` if the response did not carry it |

There is no `decision`, no `verdict`, no `action`. The file is an audit of
the call, not a policy.

## Stdout

One line per asked question:

```
<id>  <answer>  <detail>
```

`<answer>` is the value of the answer: the `choice` of a `choice`, the
`score` of a `score`, the `noul` mass of a `noul`. `<detail>` is
`confidence` when the answer carries that field, and the string `—` when it
does not.

Stdout reports what came back. It does not compare, and it does not pick an
action.

## Errors

| situation | exit | stderr |
|---|---|---|
| success | 0 | (empty) |
| endpoint did not answer (connection refused, DNS, socket) | 1 | the original cause |
| HTTP status is not 2xx | 1 | the status code and the first bytes of the body |
| body is not valid JSON | 1 | the parse error |
| body has no `answers`, or answers for ids that were not asked, or is **missing** answers for ids that were asked | 1 | missing ids are listed |
| the call exceeded `--timeout` | 1 | the error says the time ceiling was exceeded |
| usage error (bad flags, empty `--ids`, an unknown id) | 3 | the usage reason; unknown ids are named **before** any network call |

## Time ceiling

`--timeout` is the ceiling of the HTTP call. Default 30 seconds. The client
aborts when the deadline passes and does not wait longer. Rule 12: no
command without a ceiling.

## What this client does not do

- choose CONTINUE / INJECT_HINT / RESET / ESCALATE
- compare an abstention mass against a threshold
- inject a hint, snapshot a tree, or escalate
- invent state, or read the ledger on its own
- pin a host, a port, or a URL
- call a model; the backend behind `--endpoint` is the owner's (D1)

**The client asks and brings the answer — rung I is who decides.**
