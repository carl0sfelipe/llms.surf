# site/ — public marketing surface (llms.surf)

Static cut of the public site. Visual language (logo, bathymetry, terminal
chrome) is the owner's template. **Numbers are not.**

## Change checklist — if you touch X, also touch Y

- `app.js` `DATA.stats` → `tests/test-site-honesty.sh` must stay green (it
  counts incidents, registry models, modes, adapters, test suites, VERSION).
- A new hosted price or tok/s → set `cloudLive` only after a **measured**
  cell exists; never paste a vendor figure as measured.
- New HTML page → add it to the honesty test's file list and to nav/footer.
- Copy that says "open source" → `LICENSE` is proprietary. Don't.

## Load-bearing decisions

- Invented numbers are a critical bug (same rule as bestmodel.run).
- Swell/Saquarema stay "no data yet" until measured.
- Oracle-loop animation is a **demo of shape**, not a recorded session.
- Hero estimator uses **assumed** public-API ballpark rates, labeled as such.
