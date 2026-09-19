//! CLI shell for the P1 kernel. All I/O lives here; `lib.rs` stays pure.
//!
//! dispatch-policy resolve <request> --registry R.json [--catalog C.json]
//!     --allowlist A.json [--credentials p1,p2] [--format us|json]
//!
//! Exit codes mirror the shell they replace: 0 ok, 2 loud policy error,
//! 3 unreadable input.

use dispatch_policy::{Allowlist, FreeCatalog, Inputs, PolicyError, Registry, SkipReason};
use std::collections::BTreeSet;
use std::process::exit;

fn usage() -> ! {
    eprintln!(
        "usage: dispatch-policy resolve <request> --registry R.json [--catalog C.json] --allowlist A.json [--credentials p1,p2] [--format us|json]"
    );
    exit(2)
}

fn read_json<T: serde::de::DeserializeOwned>(path: &str, what: &str) -> Result<T, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("cannot read {what} {path}: {e}"))?;
    serde_json::from_str(&text).map_err(|e| format!("cannot parse {what} {path}: {e}"))
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() < 2 || args[0] != "resolve" {
        usage();
    }
    let request = args[1].clone();
    let (mut registry, mut catalog, mut allowlist, mut credentials, mut format) =
        (None, None, None, String::new(), "us".to_string());
    let mut i = 2;
    while i < args.len() {
        let value = args.get(i + 1).cloned().unwrap_or_else(|| usage());
        match args[i].as_str() {
            "--registry" => registry = Some(value),
            "--catalog" => catalog = Some(value),
            "--allowlist" => allowlist = Some(value),
            "--credentials" => credentials = value,
            "--format" => format = value,
            _ => usage(),
        }
        i += 2;
    }
    let registry_path = registry.unwrap_or_else(|| usage());
    let allowlist_path = allowlist.unwrap_or_else(|| usage());

    let registry: Registry = match read_json(&registry_path, "registry") {
        Ok(r) => r,
        Err(e) => {
            eprintln!("ERROR: {e}");
            exit(3)
        }
    };
    let allowlist: Allowlist = match read_json(&allowlist_path, "allowlist") {
        Ok(a) => a,
        Err(e) => {
            eprintln!("ERROR: {e}");
            exit(3)
        }
    };
    // Catalog: absent or unreadable both mean "missing" — the policy decides
    // loudly (CatalogMissing) instead of this shell degrading to defaults.
    let catalog: Option<FreeCatalog> = catalog.and_then(|p| match read_json::<FreeCatalog>(&p, "free catalog") {
        Ok(c) if c.kind.as_deref().map(|k| k.starts_with("free-catalog/")).unwrap_or(true) => Some(c),
        Ok(_) => {
            eprintln!("WARN: catálogo {p} com kind inesperado — tratado como ausente");
            None
        }
        Err(e) => {
            eprintln!("WARN: {e} — tratado como ausente");
            None
        }
    });
    let credentials: BTreeSet<String> =
        credentials.split(',').map(str::trim).filter(|s| !s.is_empty()).map(String::from).collect();

    let inputs = Inputs { registry: &registry, catalog: catalog.as_ref(), allowlist: &allowlist, credentials: &credentials };

    match dispatch_policy::resolve(&request, &inputs) {
        Ok(res) => {
            for s in &res.skipped {
                match &s.reason {
                    SkipReason::DeadId { id_status } => eprintln!(
                        "WARN: catálogo free cita '{}' com id_status '{}' no registry — pulado na porta (E5-M2)",
                        s.r#ref, id_status
                    ),
                    SkipReason::NoFileCredential { provider } => eprintln!(
                        "  ↳ pulando {} — provider '{}' sem credencial em arquivo (E5-M5: env herdada não conta)",
                        s.r#ref, provider
                    ),
                }
            }
            match format.as_str() {
                "json" => println!("{}", serde_json::to_string_pretty(&res).expect("serializable")),
                _ => print!("{}", res.chain.render_us()),
            }
        }
        Err(err) => {
            if let PolicyError::EmptyAfterCredentialGate { skipped, .. } = &err {
                for s in skipped {
                    if let SkipReason::NoFileCredential { provider } = &s.reason {
                        eprintln!("  ↳ pulando {} — provider '{}' sem credencial em arquivo (E5-M5)", s.r#ref, provider);
                    }
                }
            }
            eprintln!("✖ {err}");
            exit(2)
        }
    }
}
