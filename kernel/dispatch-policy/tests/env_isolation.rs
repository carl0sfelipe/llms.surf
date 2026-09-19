//! T17 — Environment isolation mechanism (law L4, incident E5-M5).
//!
//! Mutation M9 (`kernel/test-specs/T06-mutation.md`: the credential gate
//! of `cheap_chain` reads `std::env::var` as a fallback) survives on
//! `main` because no test observes the environment. This file is the
//! mechanism that closes that gap: the process environment is poisoned
//! and `resolve` must behave exactly as under a clean env — with an
//! empty FILE credential set, every non-keyless entry is skipped
//! (`SkipReason::NoFileCredential`) and the chain carries keyless legs
//! only. L4 holds regardless of env; the env is never an input.
//!
//! One single `#[test]` function: env vars are process-global, so all
//! poisoning and assertions happen on one thread, in one test.

use dispatch_policy::{
    resolve, Allowlist, CatalogModel, FreeCatalog, Inputs, PolicyError, Registry, RegistryModel,
    SkipReason,
};
use std::collections::BTreeSet;

/// Poison every channel an env-leaking credential gate could plausibly
/// read: the conventional provider variable names (both suffixes), the
/// bare provider names (a literal `std::env::var(p)` mutation), and the
/// generic process env (`HOME`, `PATH`).
fn poison_env() {
    for (k, v) in [
        ("OPENROUTER_API_KEY", "t17-poison"),
        ("OPENCODE_TOKEN", "t17-poison"),
        ("openrouter", "t17-poison"),
        ("opencode", "t17-poison"),
        ("HOME", "/nonexistent/t17-poison"),
        ("PATH", "/nonexistent/t17-poison"),
    ] {
        std::env::set_var(k, v);
    }
}

/// Live (non-dead) registry entries covering every catalog ref.
fn registry_for(cat: &[CatalogModel]) -> Registry {
    Registry {
        models: cat
            .iter()
            .map(|m| RegistryModel {
                id: m.r#ref.clone(),
                id_status: Some("EXISTE".into()),
                ..Default::default()
            })
            .collect(),
    }
}

/// One keyless leg (must survive any env) plus two keyed legs whose
/// conventional env names are poisoned above (must be skipped: the FILE
/// credential set is empty).
fn catalog() -> FreeCatalog {
    FreeCatalog {
        kind: Some("free-catalog/1".into()),
        models: vec![
            CatalogModel {
                r#ref: "z-free/keyless".into(),
                provider: Some("opencode".into()),
                keyless: true,
                context_length: Some(1_000_000),
            },
            CatalogModel {
                r#ref: "a-paid/openrouter".into(),
                provider: Some("openrouter".into()),
                keyless: false,
                context_length: Some(200_000),
            },
            CatalogModel {
                r#ref: "b-paid/opencode".into(),
                provider: Some("opencode".into()),
                keyless: false,
                context_length: Some(100_000),
            },
        ],
    }
}

fn keyed_refs() -> BTreeSet<&'static str> {
    BTreeSet::from(["a-paid/openrouter", "b-paid/opencode"])
}

#[test]
fn l4_holds_regardless_of_env() {
    poison_env();
    let cat = catalog();
    let reg = registry_for(&cat.models);
    let allowlist = Allowlist {
        providers: vec!["opencode".into(), "openrouter".into()],
    };
    let creds: BTreeSet<String> = BTreeSet::new(); // empty FILE credential set

    // Cheap route, mixed catalog: the keyless leg survives, both keyed
    // legs are skipped as NoFileCredential — never admitted via env.
    let inputs = Inputs {
        registry: &reg,
        catalog: Some(&cat),
        allowlist: &allowlist,
        credentials: &creds,
    };
    let res = resolve("tier:cheap", &inputs)
        .expect("keyless leg must survive the credential gate with empty FILE credentials");
    for e in res.chain.entries() {
        assert!(
            e.keyless == Some(true),
            "L4 violated under poisoned env: keyed entry {e:?} entered the chain with empty credentials"
        );
    }
    let skipped_keyed: BTreeSet<&str> = res
        .skipped
        .iter()
        .filter(|s| matches!(s.reason, SkipReason::NoFileCredential { .. }))
        .map(|s| s.r#ref.as_str())
        .collect();
    assert_eq!(
        skipped_keyed,
        keyed_refs(),
        "every non-keyless entry must be skipped, via env alone"
    );

    // Keyed-only catalog: the resolution must fail loud and typed —
    // never fall back to the environment to build a chain (E5-M5).
    let keyed_only = FreeCatalog {
        kind: Some("free-catalog/1".into()),
        models: cat.models.iter().filter(|m| !m.keyless).cloned().collect(),
    };
    let inputs = Inputs {
        registry: &reg,
        catalog: Some(&keyed_only),
        allowlist: &allowlist,
        credentials: &creds,
    };
    match resolve("tier:cheap", &inputs) {
        Err(PolicyError::EmptyAfterCredentialGate { skipped, .. }) => {
            let got: BTreeSet<&str> = skipped.iter().map(|s| s.r#ref.as_str()).collect();
            assert_eq!(got, keyed_refs(), "skipped list must name every keyed ref");
        }
        other => panic!(
            "keyed-only catalog under poisoned env must be EmptyAfterCredentialGate, got {other:?}"
        ),
    }
}
