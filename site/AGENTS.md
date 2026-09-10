# site/ — public marketing surface (llms.surf)

Static cut of the public site. Visual language (logo, bathymetry, terminal
chrome) is the owner's template. **Numbers are not.**

## Change checklist — if you touch X, also touch Y

- `app.js` `DATA.stats` → `tests/test-site-honesty.sh` must stay green (it
  counts incidents, registry models, modes, adapters, test suites, VERSION).
  Same numbers must appear in `llms.txt`.
- New HTML page → add it to the honesty test's file list and to nav/footer.
- Blog post → `site/blog/posts/<slug>.md` (frontmatter: title, date, slug,
  description, tags) then `python3 site/blog/build.py`. Do not hand-edit
  the generated `site/blog/index.html` or `site/blog/<slug>/index.html`.
  `site/.nojekyll` keeps GitHub Pages from running Jekyll on the `.md`.
- Copy that says "open source" → `LICENSE` is proprietary. Don't.
- Do **not** put a hosted-inference SKU, empty tps/$/M table, or "Swell is
  not live" product page on the site. That product does not exist yet.

## Journeys — human vs agent

The site is agent-first. `journey.js` (in `<head>`, no defer) sets
`html[data-journey]` before paint.

Precedence: URL `?as=human|agent` → localStorage (explicit click only) →
known agent UA → search-crawler UA (human) → chat-product referrer → **ask**.
If the signal is not deterministic, do not guess.

- `llms.txt` is the agent surface for clients that do not run JS.
- `index.html?as=agent` is the HTML twin. `?as=human` is the visual tour.
- Auto-detect is not written to localStorage. Only a click (or URL) sticks.
- Human first session is **clone** (`#quickstart` in the hero). Estimator
  (`#assumed-rates`) is optional and later. Agent surface: install, then
  contract. `journey.js` is portable (`data-key`); bestmodel.run uses the
  same file with `bestmodel.run.journey`.

## Load-bearing decisions

- Invented numbers are a critical bug (same rule as bestmodel.run).
- Public pages sell the dispatcher that ships in this repo. Not a catalog
  of products we will maybe host later.
- Oracle-loop animation is a **demo of shape**, not a recorded session.
- Hero estimator uses **assumed** public-API ballpark rates, labeled as such.
