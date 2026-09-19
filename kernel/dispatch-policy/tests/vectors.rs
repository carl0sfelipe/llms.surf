//! Shared conformance vectors (`kernel/vectors/p1/cases.json`). The same file
//! drives the Bend lab; a case added here is a case added there.

use dispatch_policy::{Allowlist, ChainEntry, FreeCatalog, Inputs, Registry, Skipped};
use serde::Deserialize;
use std::collections::BTreeSet;

#[derive(Deserialize)]
struct File {
    fixtures: Fixtures,
    cases: Vec<Case>,
}

#[derive(Deserialize)]
struct Fixtures {
    registry: serde_json::Value,
    catalog: serde_json::Value,
    allowlist: serde_json::Value,
}

#[derive(Deserialize)]
struct Case {
    name: String,
    request: String,
    #[serde(default)]
    credentials: Vec<String>,
    /// Override; `null` (explicit) = no catalog; absent = fixture.
    #[serde(default, deserialize_with = "deserialize_override")]
    catalog: Override,
    #[serde(default, deserialize_with = "deserialize_override")]
    registry: Override,
    expect: Expect,
}

enum Override {
    Fixture,
    Null,
    Value(serde_json::Value),
}

impl Default for Override {
    fn default() -> Self {
        Override::Fixture
    }
}

fn deserialize_override<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Override, D::Error> {
    let v = serde_json::Value::deserialize(d)?;
    Ok(if v.is_null() { Override::Null } else { Override::Value(v) })
}

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Expect {
    Ok { entries: Vec<ChainEntry>, skipped: Vec<Skipped> },
    Error(String),
}

fn pick(o: &Override, fixture: &serde_json::Value) -> Option<serde_json::Value> {
    match o {
        Override::Fixture => Some(fixture.clone()),
        Override::Null => None,
        Override::Value(v) => Some(v.clone()),
    }
}

#[test]
fn all_p1_vectors_conform() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../vectors/p1/cases.json");
    let file: File = serde_json::from_str(&std::fs::read_to_string(path).expect("vectors file")).expect("vectors json");
    let allowlist: Allowlist = serde_json::from_value(file.fixtures.allowlist.clone()).unwrap();
    let mut failures = Vec::new();

    for case in &file.cases {
        let registry: Registry =
            serde_json::from_value(pick(&case.registry, &file.fixtures.registry).expect("registry never null")).unwrap();
        let catalog: Option<FreeCatalog> =
            pick(&case.catalog, &file.fixtures.catalog).map(|v| serde_json::from_value(v).unwrap());
        let credentials: BTreeSet<String> = case.credentials.iter().cloned().collect();
        let inputs = Inputs { registry: &registry, catalog: catalog.as_ref(), allowlist: &allowlist, credentials: &credentials };

        let got = dispatch_policy::resolve(&case.request, &inputs);
        let ok = match (&case.expect, &got) {
            (Expect::Ok { entries, skipped }, Ok(res)) => res.chain.entries() == entries.as_slice() && &res.skipped == skipped,
            (Expect::Error(variant), Err(e)) => {
                let tag = serde_json::to_value(e).unwrap()["error"].as_str().unwrap().to_string();
                &tag == variant
            }
            _ => false,
        };
        if !ok {
            failures.push(format!("{}: got {:#?}", case.name, got));
        }
    }
    assert!(failures.is_empty(), "vector failures:\n{}", failures.join("\n\n"));
}
