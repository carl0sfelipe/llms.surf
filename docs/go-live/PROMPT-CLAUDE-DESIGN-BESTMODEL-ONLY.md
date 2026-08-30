# Claude Design (Opus) — bestmodel.run ONLY

You are building ONE complete production website: **bestmodel.run** — a
benchmark engine for local LLMs. Every result DERIVES from validated runs
signed with per-user Ed25519 keys. Nothing is an opinion; everything is
measured, reproducible, attributable. Community pool data (via
localmaxxing.com public API) is displayed with its provenance class
("reported") — never hidden, never passed off as CLI-measured.

=== NON-NEGOTIABLES ===

1. MOBILE-FIRST. Every page works beautifully at 360px. Desktop layouts
   are enhancements. min-width gating of any kind is FORBIDDEN.
2. HONESTY: numbers on pages come ONLY from the attached JSON files
   (leaderboard standings, contributor export). Never hardcode metrics in
   copy. Bad provenance is displayed, not buried. No price, no dates, no
   invented counts anywhere.
3. OUTPUT: pure HTML/CSS/JS, no build step, relative paths, works under
   Vercel cleanUrls. One file per page + shared assets/theme.css.

=== DESIGN SYSTEM (ATTACHED theme.css — evolve, never replace) ===

The attached theme.css IS the brand: dark tokens (#0B0C0E), surfaces in
layers, hairline translucent borders, amber #E0A458 accent, Inter /
Inter Tight / JetBrains Mono. Keep the identity. ELEVATE to professional:
refined spacing and typography scales, tighter data tables, cleaner
badges, flawless mobile. No external framework. Do not change brand
colors or fonts.

=== PAGES ===

1. **index.html** — landing: what bestmodel.run is (one paragraph),
   leaderboard preview (top rows), the three provenance badges explained
   in one line each (measured_signed / community / reported), link to
   hardware page. One CTA: "contribute a signed run".
2. **leaderboard.html** — full table from the attached standings shape:
   rank, model, engine, provenance badge, tok/s, per-row button
   **"report unrealistic run"** (opens a small form: reason + evidence
   URL; posts nowhere yet — front-end only, console.log the payload).
3. **hardware.html** — GPU/hardware view of the same data.
4. **track-record.html** — the professional gamification: levels
   Contributor → Replicator → Auditor, mapped to verified acts (signed
   runs, reproductions, accepted fake reports). Tone: scientific
   audit, ZERO surf/slang lexicon.

=== DELIVERY ===

4 rounds: (1) theme.css refinement + index, (2) leaderboard + report
button, (3) hardware + track-record, (4) self-audit against the three
non-negotiables + list of files delivered. Each file complete, no
placeholders.

=== ATTACHMENTS (pasted in this message) ===

A1. theme.css — current production visual language (evolve it).
A2. contributor export contract:
    {"generated_at":"...","source":"S27 fetch_contributor_points
    (validated signed runs x 2)","contributors":[{"handle":"...",
    "points":4,"validated_runs":2}]}
A3. standings shape (what the leaderboard renders at runtime):
    rows with model, engine, source_class, throughput metrics, GPU.
