# BENCH — kernel P1 measured numbers

One row per measured run: date, machine, input size → latency (ms) and RSS
when captured. Numbers are observations, not laws; re-run before quoting.

| Date | Machine | What | Input size | Result |
|---|---|---|---|---|
| 2026-09-19 | Arch Linux 7.1.9-arch1-2, Xeon E5-2680 v4 @ 2.40GHz, 28 threads, 31Gi RAM | `tier:cheap` whole resolution: shell path (`run-with-fallback.sh` CHAIN_META block: python3 spawning a 2nd python3, `lib-oracfit-mode-loader.py`) vs `dispatch-policy` release binary | real `model-registry.json` (26 models) + `data/free-catalog.json` (11 refs), 20 runs each after warmup | shell median 102.2 ms (min 96.6, max 224.1) · binary median 1.1 ms (min 1.0, max 1.5) · ≈91x |
