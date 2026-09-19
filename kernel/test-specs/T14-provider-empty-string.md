## T14 — Decide `provider: ""` (30 min)

Today Rust treats `Some("")` as a provider outside the allowlist
(violation) while Python treats `""` as no provider. Decide: normalize
empty string to `None` at parse time (recommended — matches every
producer in the tree; write it as a serde `deserialize_with`), record the
decision in `P1.md` **Decisions**, add vector `T14_empty_provider_is_none`,
and confirm T03's harness (if promoted) no longer flags it. Oracle:
vector green; T05 §16 case now passes.

