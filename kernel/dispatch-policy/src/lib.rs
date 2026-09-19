//! llms.surf kernel — P1: dispatch policy.
//!
//! Pure function from (request, registry, free catalog, allowlist, file
//! credentials) to an ordered fallback chain, or a typed, loud error.
//! No I/O here. Written in the "Bend way": immutable data, no shared
//! state, every invariant is either a type or a law in `tests/laws.rs`.
//!
//! Laws (see `kernel/laws/P1.md`, each tied to an incident):
//! - L1  fields are typed, never positional text (incident e82f008)
//! - L2  no dead id ever enters a chain (E5-M2)
//! - L3  cheap order = keyless, context desc, ref asc; deterministic (E5-M4/R1)
//! - L4  non-keyless entry requires a file credential for its provider (E5-M5)
//! - L5  free path never reaches a provider outside the allowlist (E5-M6/R4)
//! - L6  a chain is never empty; failure is a typed error, never a default (E5)
//! - L8  a chain never contains the same ref twice; the first occurrence in
//!   `catalog_order` decides the ref's fate, later occurrences are reported
//!   (E5: retrying the same ref — possibly the same dead ref — is the smell)

use serde::{Deserialize, Serialize};
use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet};

/// Unit-separator used on the wire to the shell (never tab: incident e82f008).
pub const US: char = '\u{1f}';

/// id_status values stamped by `audit-registry-ids.sh` that reject at the door.
pub const DEAD_ID_STATUSES: [&str; 3] = ["FANTASMA", "NAO-ENCONTRADO", "NAO-VERIFICADO"];

// ---------------------------------------------------------------- inputs

/// T14 decision (2026-09-19): `provider: ""` means "no provider".
/// Python (`lib-oracfit-mode-loader.py`) treats `""` as falsy and every
/// producer in the tree emits `""` (or omits the field) for unknown;
/// plain `Option<String>` would deserialize `""` as `Some("")`, which then
/// trips the L5 allowlist gate as a provider outside the allowlist — the
/// divergence proven by T05 §16. Normalized at the parse boundary, for
/// every `provider` field in this crate.
fn empty_provider_is_none<'de, D>(d: D) -> Result<Option<String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let raw: Option<String> = serde::Deserialize::deserialize(d)?;
    Ok(raw.filter(|s| !s.is_empty()))
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Registry {
    #[serde(default)]
    pub models: Vec<RegistryModel>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct RegistryModel {
    #[serde(default)]
    pub id: String,
    #[serde(default, deserialize_with = "empty_provider_is_none")]
    pub provider: Option<String>,
    #[serde(default)]
    pub tier: Option<String>,
    #[serde(default)]
    pub id_status: Option<String>,
    #[serde(default)]
    pub fallback: Vec<String>,
    #[serde(default)]
    pub cli_hints: BTreeMap<String, serde_json::Value>,
    #[serde(default)]
    pub best_for: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct FreeCatalog {
    #[serde(default)]
    pub kind: Option<String>,
    #[serde(default)]
    pub models: Vec<CatalogModel>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CatalogModel {
    #[serde(rename = "ref", default)]
    pub r#ref: String,
    #[serde(default, deserialize_with = "empty_provider_is_none")]
    pub provider: Option<String>,
    #[serde(default)]
    pub keyless: bool,
    #[serde(default)]
    pub context_length: Option<u64>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Allowlist {
    #[serde(default)]
    pub providers: Vec<String>,
}

/// Everything the policy is allowed to look at. Credentials are the set of
/// providers that have a credential in a FILE (lib-free-credentials); the
/// environment is never consulted (E5-M5).
#[derive(Debug, Clone)]
pub struct Inputs<'a> {
    pub registry: &'a Registry,
    pub catalog: Option<&'a FreeCatalog>,
    pub allowlist: &'a Allowlist,
    pub credentials: &'a BTreeSet<String>,
}

// --------------------------------------------------------------- outputs

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChainEntry {
    pub r#ref: String,
    /// Stamped id_status from the registry, or empty when unknown there.
    pub id_status: String,
    /// Who serves this ref. `None` = unknown (never the string "1": e82f008,
    /// never `Some("")`: T14).
    #[serde(default, deserialize_with = "empty_provider_is_none")]
    pub provider: Option<String>,
    /// Credential-gate tri-state (decision D2, T09/T15): `Some(true)` =
    /// zero-key leg; `Some(false)` = keyed leg, gate applies; `None` = gate
    /// not applicable (direct ids — the policy made no credential
    /// determination here). Wire: `1` / `0` / `-`.
    pub keyless: Option<bool>,
}

/// Ordered fallback chain. Non-empty by construction (L6): the only way to
/// build one is [`Chain::new`], which rejects empty input.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Chain {
    pub request: String,
    entries: Vec<ChainEntry>,
}

impl Chain {
    pub fn new(request: impl Into<String>, entries: Vec<ChainEntry>) -> Result<Self, PolicyError> {
        let request = request.into();
        if entries.is_empty() {
            return Err(PolicyError::NoLiveRef { request });
        }
        for e in &entries {
            for (field, value) in [
                ("ref", e.r#ref.as_str()),
                ("id_status", e.id_status.as_str()),
                ("provider", e.provider.as_deref().unwrap_or("")),
            ] {
                // D-L1c (T07, 2026-09-19): CR is a delimiter too —
                // `text.lines()` splits on `\n` and strips a trailing `\r`,
                // so a lone CR inside a field survives the round-trip as a
                // shifted field.
                if value.contains(US) || value.contains('\n') || value.contains('\r') {
                    return Err(PolicyError::MalformedField {
                        field: field.to_string(),
                        value: value.to_string(),
                    });
                }
            }
            if e.r#ref.is_empty() {
                return Err(PolicyError::MalformedField {
                    field: "ref".into(),
                    value: String::new(),
                });
            }
        }
        Ok(Self { request, entries })
    }

    pub fn entries(&self) -> &[ChainEntry] {
        &self.entries
    }

    /// Wire format consumed by `run-with-fallback.sh`:
    /// `ref US id_status US provider US keyless(1|0|-)` per line. `-` (gate
    /// not applicable, direct ids) keeps the shell's existing
    /// `[ "$KEYLESS" != "1" ]` credential gate armed — a third value can
    /// never unlock a leg, only `1` does (failsafe; the shell is unchanged).
    pub fn render_us(&self) -> String {
        let mut out = String::new();
        for e in &self.entries {
            out.push_str(&e.r#ref);
            out.push(US);
            out.push_str(&e.id_status);
            out.push(US);
            out.push_str(e.provider.as_deref().unwrap_or(""));
            out.push(US);
            out.push(match e.keyless {
                Some(true) => '1',
                Some(false) => '0',
                None => '-',
            });
            out.push('\n');
        }
        out
    }

    /// Inverse of [`Chain::render_us`] (law L1: round-trip).
    pub fn parse_us(request: impl Into<String>, text: &str) -> Result<Self, PolicyError> {
        let mut entries = Vec::new();
        for line in text.lines() {
            if line.is_empty() {
                continue;
            }
            let fields: Vec<&str> = line.split(US).collect();
            if fields.len() != 4 {
                return Err(PolicyError::MalformedField {
                    field: "line".into(),
                    value: line.to_string(),
                });
            }
            let keyless = match fields[3] {
                "1" => Some(true),
                "0" => Some(false),
                "-" => None,
                other => {
                    return Err(PolicyError::MalformedField {
                        field: "keyless".into(),
                        value: other.to_string(),
                    })
                }
            };
            entries.push(ChainEntry {
                r#ref: fields[0].to_string(),
                id_status: fields[1].to_string(),
                provider: if fields[2].is_empty() {
                    None
                } else {
                    Some(fields[2].to_string())
                },
                keyless,
            });
        }
        Self::new(request, entries)
    }
}

/// Why an entry of the free catalog was left out (reported, never silent).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum SkipReason {
    DeadId {
        id_status: String,
    },
    NoFileCredential {
        provider: String,
    },
    /// L8: a later catalog occurrence of a ref already seen. Dedup precedes
    /// the gates, so a dead or uncredited first occurrence is never rescued
    /// by a duplicate further down the file (E5 retry smell).
    DuplicateRef {},
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Skipped {
    pub r#ref: String,
    pub reason: SkipReason,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Resolution {
    pub chain: Chain,
    pub skipped: Vec<Skipped>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "error", content = "detail")]
pub enum PolicyError {
    /// Free route without a readable stamped catalog. Never falls back to defaults (E5).
    CatalogMissing,
    /// Nothing survived the door gates.
    NoLiveRef {
        request: String,
    },
    /// Live refs existed but none had a file credential (E5-M5).
    EmptyAfterCredentialGate {
        request: String,
        skipped: Vec<Skipped>,
    },
    /// Free catalog cites a provider the owner never allowed (E5-M6/R4).
    ProviderOutsideAllowlist {
        r#ref: String,
        provider: String,
    },
    NoModelForTier {
        tier: String,
    },
    UnknownModel {
        request: String,
    },
    MalformedField {
        field: String,
        value: String,
    },
}

impl std::fmt::Display for PolicyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PolicyError::CatalogMissing => write!(
                f,
                "rota free sem catálogo carimbado legível (data/free-catalog.json). Rode bin/sync-free-catalog.sh. Recusando defaults que já serviram id morto (incidente E5)"
            ),
            PolicyError::NoLiveRef { request } => {
                write!(f, "{request} não resolveu para nenhum ref vivo após o gate do registry (E5-M2)")
            }
            PolicyError::EmptyAfterCredentialGate { request, .. } => write!(
                f,
                "cadeia do {request} vazia após gate de credencial — nada despachado (E5-M5)"
            ),
            PolicyError::ProviderOutsideAllowlist { r#ref, provider } => write!(
                f,
                "catálogo free cita '{ref}' com provider '{provider}' fora da allowlist (E5-M6/R4) — sync comprometido",
                ref = r#ref
            ),
            PolicyError::NoModelForTier { tier } => write!(f, "no model for tier:{tier}"),
            PolicyError::UnknownModel { request } => write!(f, "modelo '{request}' não existe no registry"),
            PolicyError::MalformedField { field, value } => {
                write!(f, "campo '{field}' malformado: {value:?}")
            }
        }
    }
}

impl std::error::Error for PolicyError {}

// ----------------------------------------------------------------- policy

fn is_dead(status: &str) -> bool {
    DEAD_ID_STATUSES.iter().any(|d| status.contains(d))
}

fn status_map(reg: &Registry) -> BTreeMap<&str, &str> {
    reg.models
        .iter()
        .map(|m| (m.id.as_str(), m.id_status.as_deref().unwrap_or("")))
        .collect()
}

/// L3 (restated per D-L3, 2026-09-19): the ordered chain is a function of
/// the set of catalog entries — sort by the key (keyless first, larger
/// context first, ref ascending), then dedupe by `ref` keeping the first
/// (= the best-ranked occurrence; for full sort-key ties, the file-order
/// first via the stable sort). Output refs are distinct (L8 is a
/// precondition of L3), so the key is a strict total order on the output
/// and the result is byte-deterministic.
pub fn catalog_order(models: &[CatalogModel]) -> Vec<&CatalogModel> {
    let mut v: Vec<&CatalogModel> = models.iter().filter(|m| !m.r#ref.is_empty()).collect();
    v.sort_by_key(|m| {
        (
            !m.keyless,
            Reverse(m.context_length.unwrap_or(0)),
            m.r#ref.clone(),
        )
    });
    let mut seen: BTreeSet<&str> = BTreeSet::new();
    v.retain(|m| seen.insert(m.r#ref.as_str()));
    v
}

fn cheap_chain(request: &str, inp: &Inputs) -> Result<Resolution, PolicyError> {
    let cat = inp.catalog.ok_or(PolicyError::CatalogMissing)?;
    let statuses = status_map(inp.registry);
    let allow: BTreeSet<&str> = inp.allowlist.providers.iter().map(String::as_str).collect();

    let mut entries = Vec::new();
    let mut skipped = Vec::new();
    let mut live_before_credential_gate = 0usize;
    // L8: the first occurrence of a ref in catalog_order decides its fate;
    // every later occurrence is reported and never reaches the gates.
    let mut seen: BTreeSet<&str> = BTreeSet::new();

    for m in catalog_order(&cat.models) {
        if !seen.insert(m.r#ref.as_str()) {
            skipped.push(Skipped {
                r#ref: m.r#ref.clone(),
                reason: SkipReason::DuplicateRef {},
            });
            continue;
        }
        let status = statuses.get(m.r#ref.as_str()).copied().unwrap_or("");
        if is_dead(status) {
            skipped.push(Skipped {
                r#ref: m.r#ref.clone(),
                reason: SkipReason::DeadId {
                    id_status: status.into(),
                },
            });
            continue;
        }
        if let Some(p) = &m.provider {
            if !allow.contains(p.as_str()) {
                return Err(PolicyError::ProviderOutsideAllowlist {
                    r#ref: m.r#ref.clone(),
                    provider: p.clone(),
                });
            }
        }
        live_before_credential_gate += 1;
        if !m.keyless {
            if let Some(p) = &m.provider {
                if !inp.credentials.contains(p) {
                    skipped.push(Skipped {
                        r#ref: m.r#ref.clone(),
                        reason: SkipReason::NoFileCredential {
                            provider: p.clone(),
                        },
                    });
                    continue;
                }
            }
        }
        entries.push(ChainEntry {
            r#ref: m.r#ref.clone(),
            id_status: status.to_string(),
            provider: m.provider.clone(),
            keyless: Some(m.keyless),
        });
    }

    if live_before_credential_gate == 0 {
        return Err(PolicyError::NoLiveRef {
            request: request.to_string(),
        });
    }
    if entries.is_empty() {
        return Err(PolicyError::EmptyAfterCredentialGate {
            request: request.to_string(),
            skipped,
        });
    }
    Ok(Resolution {
        chain: Chain::new(request, entries)?,
        skipped,
    })
}

/// Port of the registry-first rules for `mid` / `expensive` / `vision`
/// (lib-oracfit-mode-loader.py `resolve_tier`), followed by the stamped defaults.
fn single_tier_id(tier: &str, reg: &Registry) -> Option<String> {
    let models = &reg.models;
    let by_id = |id: &str| models.iter().find(|m| m.id == id).map(|m| m.id.clone());
    let by_best_for = |pred: &dyn Fn(&RegistryModel) -> bool| {
        models.iter().find(|m| pred(m)).map(|m| m.id.clone())
    };

    if !models.is_empty() {
        let found = match tier {
            "mid" => by_id("deepseek-v4-pro")
                .or_else(|| by_id("deepseek-v4-flash-openrouter"))
                .or_else(|| {
                    by_best_for(&|m| {
                        let bf = &m.best_for;
                        (bf.iter().any(|b| b == "raciocínio médio")
                            || bf.iter().any(|b| b == "código"))
                            && matches!(m.tier.as_deref(), Some("paid") | Some("free"))
                    })
                }),
            "expensive" => by_best_for(&|m| {
                let mid = m.id.to_lowercase();
                m.tier.as_deref() == Some("paid")
                    && (mid.contains("frontier") || mid.contains("pro"))
            })
            .or_else(|| by_id("claude-sonnet-5"))
            .or_else(|| by_best_for(&|m| m.best_for.iter().any(|b| b == "melhor qualidade"))),
            "vision" => by_id("gemini-3.6-flash").or_else(|| {
                by_best_for(&|m| {
                    m.best_for
                        .iter()
                        .any(|b| b.contains("visão") || b.contains("vision"))
                        || m.id.to_lowercase().contains("vision")
                        || m.id.to_lowercase().contains("visão")
                })
            }),
            _ => None,
        };
        if found.is_some() {
            return found;
        }
    }
    match tier {
        "mid" => Some("deepseek-v4-pro".into()),
        "expensive" => Some("claude-sonnet-5".into()),
        "vision" => Some("gemini-3.6-flash".into()),
        _ => None,
    }
}

fn single_tier(request: &str, tier: &str, inp: &Inputs) -> Result<Resolution, PolicyError> {
    let id = single_tier_id(tier, inp.registry)
        .ok_or_else(|| PolicyError::NoModelForTier { tier: tier.into() })?;
    let statuses = status_map(inp.registry);
    // Provider/keyless come from the free catalog when the ref is there;
    // otherwise unknown provider + keyless (the e82f008 case, now typed).
    let meta = inp
        .catalog
        .and_then(|c| c.models.iter().find(|m| m.r#ref == id));
    let (provider, keyless) = match meta {
        Some(m) => (m.provider.clone(), m.keyless),
        None => (None, true),
    };
    if !keyless {
        if let Some(p) = &provider {
            if !inp.credentials.contains(p) {
                let skipped = vec![Skipped {
                    r#ref: id.clone(),
                    reason: SkipReason::NoFileCredential {
                        provider: p.clone(),
                    },
                }];
                return Err(PolicyError::EmptyAfterCredentialGate {
                    request: request.into(),
                    skipped,
                });
            }
        }
    }
    let entry = ChainEntry {
        r#ref: id.clone(),
        id_status: statuses.get(id.as_str()).copied().unwrap_or("").to_string(),
        provider,
        keyless: Some(keyless),
    };
    Ok(Resolution {
        chain: Chain::new(request, vec![entry])?,
        skipped: vec![],
    })
}

/// Direct model id (or a `cli_hints` value): the model followed by its
/// declared `fallback` ids, each carrying its stamped status. No credential
/// gate applies on this path today (mirrors run-with-fallback.sh), so every
/// entry is stamped `keyless: None` — wire `-`, "gate not applicable"
/// (decision D2) — never the unconditional `keyless: true` it used to lie
/// with (T15).
fn direct(request: &str, inp: &Inputs) -> Result<Resolution, PolicyError> {
    let reg = inp.registry;
    let statuses = status_map(reg);
    let model = reg
        .models
        .iter()
        .find(|m| m.id == request || m.cli_hints.values().any(|v| v.as_str() == Some(request)))
        .ok_or_else(|| PolicyError::UnknownModel {
            request: request.into(),
        })?;
    let provider_of = |id: &str| {
        reg.models
            .iter()
            .find(|m| m.id == id)
            .and_then(|m| m.provider.clone())
    };
    let mut entries = vec![ChainEntry {
        r#ref: model.id.clone(),
        id_status: statuses
            .get(model.id.as_str())
            .copied()
            .unwrap_or("")
            .to_string(),
        provider: model.provider.clone(),
        keyless: None,
    }];
    for f in &model.fallback {
        entries.push(ChainEntry {
            r#ref: f.clone(),
            id_status: statuses.get(f.as_str()).copied().unwrap_or("").to_string(),
            provider: provider_of(f),
            keyless: None,
        });
    }
    // L8 holds for every chain. The direct path has no skip channel, so a
    // ref repeated in the fallback list collapses to its first occurrence.
    let mut seen: BTreeSet<String> = BTreeSet::new();
    entries.retain(|e| seen.insert(e.r#ref.clone()));
    Ok(Resolution {
        chain: Chain::new(request, entries)?,
        skipped: vec![],
    })
}

/// The P1 entry point. Pure.
pub fn resolve(request: &str, inp: &Inputs) -> Result<Resolution, PolicyError> {
    match request.strip_prefix("tier:") {
        Some("cheap") => cheap_chain(request, inp),
        Some(tier) => single_tier(request, tier, inp),
        None => direct(request, inp),
    }
}
