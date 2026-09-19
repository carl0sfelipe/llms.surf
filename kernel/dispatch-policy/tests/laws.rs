//! Laws of P1 as universally quantified properties (sampled by proptest).
//! Each law names the incident it closes. See `kernel/laws/P1.md`.

use dispatch_policy::{
    catalog_order, resolve, Allowlist, CatalogModel, Chain, ChainEntry, FreeCatalog, Inputs, PolicyError, Registry,
    RegistryModel, SkipReason, DEAD_ID_STATUSES, US,
};
use proptest::prelude::*;
use std::collections::BTreeSet;

fn field() -> impl Strategy<Value = String> {
    // Any text except the two wire delimiters (those are rejected by Chain::new — law L1b).
    "[a-zA-Z0-9:/._ -]{1,24}"
}

fn provider() -> impl Strategy<Value = Option<String>> {
    prop_oneof![Just(None), Just(Some("opencode".into())), Just(Some("openrouter".into()))]
}

fn catalog_model() -> impl Strategy<Value = CatalogModel> {
    ("[a-z0-9:/.-]{1,16}", provider(), any::<bool>(), proptest::option::of(0u64..2_000_000)).prop_map(
        |(r, provider, keyless, context_length)| CatalogModel { r#ref: r, provider, keyless, context_length },
    )
}

fn status() -> impl Strategy<Value = Option<String>> {
    prop_oneof![
        Just(None),
        Just(Some("EXISTE".into())),
        Just(Some("PROVAVEL".into())),
        Just(Some("FANTASMA".into())),
        Just(Some("NAO-ENCONTRADO".into())),
        Just(Some("NAO-VERIFICADO".into())),
    ]
}

fn entry() -> impl Strategy<Value = ChainEntry> {
    // keyless generates the full tri-state (Some(true)/Some(false)/None =
    // wire `1`/`0`/`-`, T15) so the L1 round-trip covers every wire value.
    (field(), field(), proptest::option::of(field()), proptest::option::of(any::<bool>()))
        .prop_map(|(r, id_status, provider, keyless)| ChainEntry { r#ref: r, id_status, provider, keyless })
}

fn allow() -> Allowlist {
    Allowlist { providers: vec!["opencode".into(), "openrouter".into()] }
}

/// Registry whose statuses cover the catalog refs (so dead-id gating is exercised).
fn registry_for(cat: &[CatalogModel], statuses: &[Option<String>]) -> Registry {
    Registry {
        models: cat
            .iter()
            .zip(statuses.iter().cycle())
            .map(|(m, st)| RegistryModel { id: m.r#ref.clone(), id_status: st.clone(), ..Default::default() })
            .collect(),
    }
}

/// Catalog whose refs come from a tiny pool, so duplicate refs are frequent
/// (law L8 needs them; `catalog_model` alone almost never repeats a ref).
/// Small context range on purpose: ties interact with the stable sort that
/// defines which duplicate is "first".
fn dup_catalog() -> impl Strategy<Value = Vec<CatalogModel>> {
    (
        proptest::collection::vec("[a-z]{1,3}", 1..3),
        proptest::collection::vec(any::<bool>(), 0..8),
        proptest::collection::vec(proptest::option::of(0u64..4), 0..8),
    )
        .prop_map(|(pool, keyless, ctx)| {
            keyless
                .iter()
                .zip(ctx.iter().cycle())
                .enumerate()
                .map(|(i, (k, c))| CatalogModel {
                    r#ref: pool[i % pool.len()].clone(),
                    provider: Some("opencode".into()),
                    keyless: *k,
                    context_length: *c,
                })
                .collect()
        })
}

/// Generator for the restated L3 (D-L3.3): duplicate refs are FREQUENT in
/// the input (they must be handled), but two occurrences of one ref never
/// tie on the full sort key — `context_length` is the distinct per-entry
/// index — so "keep the first (= best-ranked)" is content-determined and
/// the output is a pure function of the catalog as a set. The degenerate
/// full-key-tie class (same ref/keyless/context, different provider) stays
/// pinned at vector level by `T02_l3_duplicate_ref_ties_keep_file_order`.
fn dup_ref_catalog() -> impl Strategy<Value = Vec<CatalogModel>> {
    (
        proptest::collection::vec("[a-z]{1,3}", 1..3),
        proptest::collection::vec(any::<bool>(), 0..10),
        proptest::collection::vec(
            proptest::option::of(prop_oneof![Just("opencode".to_string()), Just("openrouter".to_string())]),
            0..10,
        ),
    )
        .prop_map(|(pool, keyless, provider)| {
            let pick = |i: usize| provider.get(i % provider.len().max(1)).cloned().flatten();
            keyless
                .iter()
                .enumerate()
                .map(|(i, k)| CatalogModel {
                    r#ref: pool[i % pool.len()].clone(),
                    provider: pick(i),
                    keyless: *k,
                    context_length: Some(i as u64),
                })
                .collect()
        })
}

proptest! {
    /// L8 (E5): a chain never contains the same ref twice; the first
    /// occurrence in `catalog_order` decides the ref's fate, and every later
    /// occurrence is reported as a `DuplicateRef` skip — a dead or
    /// uncredited first occurrence is never rescued by a duplicate.
    #[test]
    fn l8_first_occurrence_wins(
        cat in dup_catalog(),
        creds in proptest::collection::btree_set(Just("opencode".to_string()), 0..2),
    ) {
        let reg = registry_for(&cat, &[Some("EXISTE".into())]);
        let catalog = FreeCatalog { kind: Some("free-catalog/1".into()), models: cat.clone() };
        let allowlist = allow();
        let inputs = Inputs { registry: &reg, catalog: Some(&catalog), allowlist: &allowlist, credentials: &creds };
        match resolve("tier:cheap", &inputs) {
            Ok(res) => {
                let refs: Vec<&str> = res.chain.entries().iter().map(|e| e.r#ref.as_str()).collect();
                let unique: std::collections::BTreeSet<&str> = refs.iter().copied().collect();
                prop_assert_eq!(unique.len(), refs.len(), "duplicate ref in chain: {:?}", refs);
                // Accounting: with every id alive, each ref contributes
                // exactly (occurrences - 1) DuplicateRef skips.
                let ordered = catalog_order(&cat);
                let mut first: std::collections::BTreeMap<&str, &CatalogModel> = std::collections::BTreeMap::new();
                let mut count: std::collections::BTreeMap<&str, usize> = std::collections::BTreeMap::new();
                for m in ordered.iter() {
                    first.entry(m.r#ref.as_str()).or_insert(m);
                    *count.entry(m.r#ref.as_str()).or_insert(0) += 1;
                }
                let mut dup_skips: std::collections::BTreeMap<&str, usize> = std::collections::BTreeMap::new();
                for s in &res.skipped {
                    if let SkipReason::DuplicateRef {} = s.reason {
                        *dup_skips.entry(s.r#ref.as_str()).or_insert(0) += 1;
                    }
                }
                for (r, n) in &count {
                    prop_assert_eq!(dup_skips.get(r).copied().unwrap_or(0), n - 1, "dup accounting for {:?}", r);
                }
                // First occurrence wins: a chain entry carries the first
                // occurrence's metadata, never a later duplicate's.
                for e in res.chain.entries() {
                    let f = first[e.r#ref.as_str()];
                    prop_assert_eq!(e.keyless, Some(f.keyless), "not the first occurrence for {:?}", e.r#ref);
                    prop_assert_eq!(&e.provider, &f.provider, "not the first occurrence for {:?}", e.r#ref);
                }
            }
            Err(PolicyError::NoLiveRef { .. }) | Err(PolicyError::EmptyAfterCredentialGate { .. }) => {}
            Err(other) => prop_assert!(false, "unexpected error {:?}", other),
        }
    }
    /// L1 (e82f008): the wire format round-trips exactly — no field can be
    /// read as another. Positional text is only ever produced/consumed by
    /// these two functions.
    #[test]
    fn l1_us_wire_roundtrip(entries in proptest::collection::vec(entry(), 1..8)) {
        let chain = Chain::new("tier:cheap", entries).unwrap();
        let text = chain.render_us();
        let back = Chain::parse_us("tier:cheap", &text).unwrap();
        prop_assert_eq!(back, chain);
    }

    /// L1b: a field containing a delimiter cannot become a chain.
    #[test]
    fn l1b_delimiters_are_rejected(mut e in entry(), which in 0u8..3) {
        match which { 0 => e.r#ref.push(US), 1 => e.id_status.push('\n'), _ => e.provider = Some(format!("x{US}y")) }
        let rejected = matches!(Chain::new("r", vec![e]), Err(PolicyError::MalformedField { .. }));
        prop_assert!(rejected);
    }

    /// L3, restated per D-L3 (DECISIONS-wave1-2, 2026-09-19): the ordered
    /// chain is a function of the set of catalog entries; refs are unique
    /// (L8); for any two entries in the output the key is strictly
    /// increasing. `catalog_order` sorts by the key, then dedupes by `ref`
    /// keeping the first (= the best-ranked occurrence). The generator
    /// keeps duplicate refs in the input (they must be handled); the
    /// assertions are on the deduped output.
    #[test]
    fn l3_cheap_order(cat in dup_ref_catalog()) {
        let ordered = catalog_order(&cat);
        // refs are unique in the output (L8 as L3's precondition).
        let mut seen: BTreeSet<&str> = BTreeSet::new();
        for m in &ordered {
            prop_assert!(seen.insert(m.r#ref.as_str()), "duplicate ref in deduped output: {:?}", m.r#ref);
        }
        // the key is STRICTLY increasing along the deduped output.
        let key = |m: &CatalogModel| (!m.keyless, std::cmp::Reverse(m.context_length.unwrap_or(0)), m.r#ref.clone());
        for w in ordered.windows(2) {
            prop_assert!(key(w[0]) < key(w[1]), "key not strictly increasing: {:?} then {:?}", w[0], w[1]);
        }
        // the kept occurrence is the best-ranked of its ref in the input.
        for m in &ordered {
            for x in cat.iter().filter(|x| x.r#ref == m.r#ref) {
                prop_assert!(key(m) <= key(x), "kept occurrence not best-ranked for ref {:?}", m.r#ref);
            }
        }
        // function of the set: reversing the input file does not move the
        // output (refs are distinct and the key is a strict total order on
        // them, so sort+dedup is content-determined).
        let mut shuffled = cat.clone();
        shuffled.reverse();
        let again: Vec<_> = catalog_order(&shuffled).into_iter().cloned().collect();
        let first: Vec<_> = ordered.into_iter().cloned().collect();
        prop_assert_eq!(first, again);
    }

    /// L2 + L4 + L5 + L6 on the cheap route, for any catalog/registry/credentials:
    /// - no dead id in the chain (E5-M2)
    /// - every non-keyless entry has a file credential for its provider (E5-M5)
    /// - every provider in the chain is in the allowlist (E5-M6/R4)
    /// - success implies a non-empty chain; failure is a typed error (E5)
    /// - the chain is a subsequence of catalog_order (no reordering by gates)
    #[test]
    fn l2_l4_l5_l6_cheap_gates(
        cat in proptest::collection::vec(catalog_model(), 0..12),
        statuses in proptest::collection::vec(status(), 1..4),
        creds in proptest::collection::btree_set(prop_oneof![Just("opencode".to_string()), Just("openrouter".to_string())], 0..3),
    ) {
        let reg = registry_for(&cat, &statuses);
        let catalog = FreeCatalog { kind: Some("free-catalog/1".into()), models: cat.clone() };
        let allowlist = allow();
        let inputs = Inputs { registry: &reg, catalog: Some(&catalog), allowlist: &allowlist, credentials: &creds };
        match resolve("tier:cheap", &inputs) {
            Ok(res) => {
                prop_assert!(!res.chain.entries().is_empty());
                let order: Vec<&str> = catalog_order(&cat).into_iter().map(|m| m.r#ref.as_str()).collect();
                let mut cursor = 0usize;
                for e in res.chain.entries() {
                    prop_assert!(!DEAD_ID_STATUSES.iter().any(|d| e.id_status.contains(d)), "dead id leaked: {:?}", e);
                    if let Some(p) = &e.provider {
                        prop_assert!(allowlist.providers.contains(p), "provider outside allowlist: {:?}", e);
                        if e.keyless == Some(false) {
                            prop_assert!(creds.contains(p), "keyed entry without credential: {:?}", e);
                        }
                    }
                    let want = e.r#ref.as_str();
                    let pos = order[cursor..].iter().position(|r| *r == want);
                    prop_assert!(pos.is_some(), "chain reordered or invented {:?}", e);
                    cursor += pos.unwrap() + 1;
                }
            }
            Err(PolicyError::NoLiveRef { .. }) | Err(PolicyError::EmptyAfterCredentialGate { .. }) => {}
            Err(other) => prop_assert!(false, "unexpected error {:?}", other),
        }
    }

    /// L5 strict: a catalog citing a provider outside the allowlist is a
    /// violation, never a silent skip and never a chain.
    #[test]
    fn l5_outside_allowlist_is_a_violation(cat in proptest::collection::vec(catalog_model(), 0..6), idx in 0usize..6) {
        let mut cat = cat;
        let intruder = CatalogModel { r#ref: "intruder/paid".into(), provider: Some("paidcorp".into()), keyless: false, context_length: Some(1) };
        let at = idx.min(cat.len());
        cat.insert(at, intruder);
        let reg = registry_for(&cat, &[Some("EXISTE".into())]);
        let catalog = FreeCatalog { kind: Some("free-catalog/1".into()), models: cat };
        let allowlist = allow();
        let creds: BTreeSet<String> = ["openrouter".to_string()].into_iter().collect();
        let inputs = Inputs { registry: &reg, catalog: Some(&catalog), allowlist: &allowlist, credentials: &creds };
        let violation = matches!(resolve("tier:cheap", &inputs), Err(PolicyError::ProviderOutsideAllowlist { .. }));
        prop_assert!(violation);
    }

    /// L6 (E5): the free route without a catalog is CatalogMissing for any
    /// registry — never a hardcoded default.
    #[test]
    fn l6_no_catalog_never_defaults(n in 0usize..5) {
        let reg = Registry { models: (0..n).map(|i| RegistryModel { id: format!("m{i}"), ..Default::default() }).collect() };
        let allowlist = allow();
        let creds = BTreeSet::new();
        let inputs = Inputs { registry: &reg, catalog: None, allowlist: &allowlist, credentials: &creds };
        prop_assert_eq!(resolve("tier:cheap", &inputs), Err(PolicyError::CatalogMissing));
    }
}

// ---------------------------------------------------------------- CLI contract
// Promoted by the P1 battery spec T04 (kernel/test-specs/reports/T04.md,
// 2026-09-19). The shared vector schema (`p1-vectors/1`) can only pin
// resolution semantics, so exit codes, usage text and wire framing are
// pinned here against the real binary instead.

fn cli_run(args: &[&str]) -> (i32, String, String) {
    use std::process::Command;
    let out = Command::new(env!("CARGO_BIN_EXE_dispatch-policy")).args(args).output().unwrap();
    (
        out.status.code().expect("killed by signal"),
        String::from_utf8(out.stdout).unwrap(),
        String::from_utf8(out.stderr).unwrap(),
    )
}

fn cli_fixture(name: &str, value: &serde_json::Value) -> std::path::PathBuf {
    let p = std::env::temp_dir().join(format!("p1-t04-{}-{name}", std::process::id()));
    std::fs::write(&p, value.to_string()).unwrap();
    p
}

/// Fixtures straight from the shared vectors file (single source of truth).
fn cli_fixtures() -> (std::path::PathBuf, std::path::PathBuf, std::path::PathBuf) {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../vectors/p1/cases.json");
    let v: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let f = &v["fixtures"];
    (
        cli_fixture("registry.json", &f["registry"]),
        cli_fixture("catalog.json", &f["catalog"]),
        cli_fixture("allowlist.json", &f["allowlist"]),
    )
}

fn usage_starts(s: &str) -> bool {
    s.starts_with("usage: dispatch-policy resolve <request>")
}

/// T04 checks 1, 2, 5, 11, 12 + bare `-h`: argument errors are usage on
/// stderr, exit 2, nothing on stdout, no panic.
#[test]
fn cli_argument_errors_are_usage_exit_2() {
    let (r, _c, a) = cli_fixtures();
    let cases: &[&[&str]] = &[
        &[],
        &["resolve"],
        &["resolve", "tier:cheap"],                                   // no --registry
        &["resolve", "tier:cheap", "--registry"],                     // dangling flag
        &["resolve", "tier:cheap", "--registry", r.to_str().unwrap()], // no --allowlist
        &["resolve", "tier:cheap", "--registry", r.to_str().unwrap(), "--allowlist", a.to_str().unwrap(), "--foo", "x"],
        &["resolve", "tier:cheap", "--registry", r.to_str().unwrap(), "--allowlist", a.to_str().unwrap(), "extra"],
        &["resolve", "-h"],
    ];
    for args in cases {
        let (code, stdout, stderr) = cli_run(args);
        assert_eq!(code, 2, "exit for {args:?}");
        assert!(stdout.is_empty(), "stdout non-empty for {args:?}");
        assert!(usage_starts(&stderr), "stderr for {args:?}: {stderr:?}");
    }
}

/// T04 checks 3, 4: unreadable / unparseable required input is a typed
/// `ERROR: cannot …` with exit 3, stdout empty.
#[test]
fn cli_unreadable_input_exit_3() {
    let (_r, _c, a) = cli_fixtures();
    let bad = cli_fixture("bad.json", &serde_json::Value::String("{oops".into()));
    let (code, stdout, stderr) =
        cli_run(&["resolve", "tier:cheap", "--registry", "/nonexistent", "--allowlist", a.to_str().unwrap()]);
    assert_eq!(code, 3);
    assert!(stdout.is_empty());
    assert!(stderr.starts_with("ERROR: cannot read registry"), "{stderr:?}");
    let (code, stdout, stderr) =
        cli_run(&["resolve", "tier:cheap", "--registry", bad.to_str().unwrap(), "--allowlist", a.to_str().unwrap()]);
    assert_eq!(code, 3);
    assert!(stdout.is_empty());
    assert!(stderr.starts_with("ERROR: cannot parse registry"), "{stderr:?}");
}

/// T04 checks 6, 7, 14: a free route whose catalog is unreadable or of an
/// unexpected kind is WARNed as absent, then the policy error is loud
/// (`✖ rota free sem catálogo`), exit 2, stdout empty — never a default.
#[test]
fn cli_catalog_trouble_is_warn_then_loud() {
    let (r, c, a) = cli_fixtures();
    let badkind = cli_fixture(
        "badkind.json",
        &serde_json::json!({"kind": "something-else/1", "models": []}),
    );
    for catalog in ["/nonexistent".to_string(), badkind.to_str().unwrap().to_string()] {
        let (code, stdout, stderr) = cli_run(&[
            "resolve", "tier:cheap", "--registry", r.to_str().unwrap(), "--catalog", &catalog,
            "--allowlist", a.to_str().unwrap(), "--credentials", "openrouter",
        ]);
        assert_eq!(code, 2, "catalog {catalog}");
        assert!(stdout.is_empty(), "catalog {catalog}");
        assert!(stderr.contains("tratado como ausente"), "catalog {catalog}: {stderr:?}");
        assert!(stderr.contains("✖ rota free sem catálogo"), "catalog {catalog}: {stderr:?}");
    }
    let _ = c;
}

/// T04 check 8 + 9 + 10: happy path wire format — exactly one line per
/// entry with exactly 3 US separators, last field ∈ {0,1}, `\n`-terminated;
/// `--format json` has `chain.request`, `chain.entries[]`, `skipped[]`;
/// messy credentials parse to the same set as clean ones.
#[test]
fn cli_happy_path_wire_and_formats() {
    let (r, c, a) = cli_fixtures();
    let base = [
        "resolve", "tier:cheap", "--registry", r.to_str().unwrap(), "--catalog", c.to_str().unwrap(),
        "--allowlist", a.to_str().unwrap(),
    ];
    let (code, stdout, _stderr) = cli_run(&[base.as_slice(), &["--credentials", "openrouter"]].concat());
    assert_eq!(code, 0);
    assert!(stdout.ends_with('\n'));
    let mut last_field_ok = true;
    let lines: Vec<&str> = stdout.trim_end_matches('\n').split('\n').collect();
    assert_eq!(lines.len(), 4, "4 entries expected, got {stdout:?}");
    for line in &lines {
        let fields: Vec<&str> = line.split(US).collect();
        assert_eq!(fields.len(), 4, "3 US per line, got {line:?}");
        assert!(!line.ends_with(' '), "trailing space in {line:?}");
        last_field_ok &= matches!(fields[3], "0" | "1");
    }
    assert!(last_field_ok, "keyless field not 0/1 in {stdout:?}");

    let messy = cli_run(&[base.as_slice(), &["--credentials", " openrouter , ,opencode "]].concat());
    let clean = cli_run(&[base.as_slice(), &["--credentials", "openrouter,opencode"]].concat());
    assert_eq!(messy, clean, "messy credentials must equal clean ones");

    let (code, stdout, _stderr) =
        cli_run(&[base.as_slice(), &["--credentials", "openrouter", "--format", "json"]].concat());
    assert_eq!(code, 0);
    let v: serde_json::Value = serde_json::from_str(&stdout).expect("valid json");
    assert!(v["chain"]["request"].is_string());
    assert!(v["chain"]["entries"].is_array());
    assert!(v["skipped"].is_array());
    let entry = &v["chain"]["entries"][0];
    let keys: Vec<&str> = entry.as_object().unwrap().keys().map(String::as_str).collect();
    assert_eq!(keys, vec!["id_status", "keyless", "provider", "ref"], "entry keys exactly the typed four");
}

/// T04 decision D1 (this branch): an unknown `--format` value falls back to
/// the US wire format with exit 0 — documented leniency, pinned here so a
/// change must update the decision in `kernel/laws/P1.md` first.
#[test]
fn cli_unknown_format_value_falls_back_to_us() {
    let (r, c, a) = cli_fixtures();
    let base = [
        "resolve", "tier:cheap", "--registry", r.to_str().unwrap(), "--catalog", c.to_str().unwrap(),
        "--allowlist", a.to_str().unwrap(), "--credentials", "openrouter",
    ];
    let default_us = cli_run(&base);
    let unknown = cli_run(&[base.as_slice(), &["--format", "xml"]].concat());
    assert_eq!(unknown.0, 0);
    assert_eq!(unknown.1, default_us.1, "unknown --format renders the US wire format");
}

/// L4 (E5-M5): the environment is never a credential input. Found by T06/M9:
/// a fallback to `std::env::var(p)` inside the credential gate survives every
/// other shipped test, because nothing else ever sets the env.
#[test]
fn l4_env_is_never_an_input() {
    std::env::set_var("opencode", "present-but-ignored");
    std::env::set_var("openrouter", "present-but-ignored");
    let keyed = CatalogModel { r#ref: "keyed".into(), provider: Some("openrouter".into()), keyless: false, context_length: Some(1) };
    let zero = CatalogModel { r#ref: "zero".into(), provider: Some("opencode".into()), keyless: true, context_length: Some(2) };
    let reg = Registry {
        models: vec![
            RegistryModel { id: "keyed".into(), id_status: Some("EXISTE".into()), ..Default::default() },
            RegistryModel { id: "zero".into(), id_status: Some("EXISTE".into()), ..Default::default() },
        ],
    };
    let allowlist = allow();
    let creds = BTreeSet::new();
    // Env vars for both providers are set, yet carry no credential: the keyed
    // ref must still be gated out, and only the zero-key leg survives.
    let cat = FreeCatalog { kind: Some("free-catalog/1".into()), models: vec![keyed.clone(), zero] };
    let inputs = Inputs { registry: &reg, catalog: Some(&cat), allowlist: &allowlist, credentials: &creds };
    match resolve("tier:cheap", &inputs) {
        Ok(res) => assert!(
            res.chain.entries() == [ChainEntry {
                r#ref: "zero".into(), id_status: "EXISTE".into(), provider: Some("opencode".into()), keyless: Some(true),
            }],
            "env leaked into the credential gate: {res:?}"
        ),
        other => panic!("env leaked into the credential gate: {other:?}"),
    }
    // A keyed-only catalog stays loud even with the env set.
    let cat = FreeCatalog { kind: Some("free-catalog/1".into()), models: vec![keyed] };
    let inputs = Inputs { registry: &reg, catalog: Some(&cat), allowlist: &allowlist, credentials: &creds };
    assert!(matches!(resolve("tier:cheap", &inputs), Err(PolicyError::EmptyAfterCredentialGate { .. })));
    std::env::remove_var("opencode");
    std::env::remove_var("openrouter");
}

/// L6 (E5): `Chain::new` rejects an empty entry list and an empty `ref` with
/// typed errors. Found by T06/M12: both guards were dead code — no shipped
/// test ever constructed such a chain, so deleting either guard stayed green.
#[test]
fn l6_chain_new_rejects_empty() {
    let empty_ref = ChainEntry { r#ref: String::new(), id_status: String::new(), provider: None, keyless: Some(true) };
    assert!(matches!(Chain::new("r", vec![]), Err(PolicyError::NoLiveRef { .. })));
    assert!(matches!(Chain::new("r", vec![empty_ref]), Err(PolicyError::MalformedField { .. })));
    // Parsing an empty wire text is the same property via the wire door.
    assert!(matches!(Chain::parse_us("r", ""), Err(PolicyError::NoLiveRef { .. })));
}
