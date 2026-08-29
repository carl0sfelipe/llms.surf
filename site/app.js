"use strict";

const DATA = {
  meta: {
    name: "LLMs.surf",
    former: "Oracfit",
    version: "3.5.0",
    github: "https://github.com/carl0sfelipe/llms.surf"
  },

  market: {
    frontierOut: 25,
    cheapOut: 0.40,
    split: [0.01, 0.99],
    tier: "assumed",
    note: "assumed public-API ballpark, not llms.surf prices — we say so"
  },

  tasks: {
    migration: { label: "code migration",     tokensOutM: 0.18, oracle: 'grep -q "from lib_y import" src/ && pytest' },
    tests:     { label: "test coverage",      tokensOutM: 0.12, oracle: "pytest --cov-fail-under=90" },
    research:  { label: "research → article", tokensOutM: 0.25, oracle: 'wc -w draft.md && grep -vqE "lorem|filler" draft.md' },
    refactor:  { label: "refactor",           tokensOutM: 0.10, oracle: "pytest -x && ruff check src/" },
    nightly:   { label: "nightly agent run",  tokensOutM: 0.40, oracle: "sha256sum -c artifacts.lock" }
  },

  budgets: {
    cursor: { label: "$20/mo Cursor Pro", monthly: 20,  local: false },
    api100: { label: "$100/mo API",       monthly: 100, local: false },
    api500: { label: "$500/mo API",       monthly: 500, local: false },
    gpu:    { label: "my own GPUs",       monthly: 0,   local: true }
  },

  stats: {
    incidents: 106,
    models: 69,
    modes: 20,
    adapters: 8,
    adaptersStub: 1,
    suites: 29,
    version: "3.5.0"
  },

  mechanisms: [
    { claim: '"done" — exit 0, no work',  mech: "gates read artifact CONTENT on disk",                         cmd: "gate: read files, hash, grep — empty artifact = exit 1" },
    { claim: "loops silently at 3am",     mech: "watchdog kills real silence, timeout kills the process tree", cmd: "watchdog: no-write > 120s → SIGKILL the tree" },
    { claim: '"read-only" critic writes', mech: "critic-guard kills dispatch, exit 5, incident auto-filed",    cmd: "critic-guard: write detected → exit 5 + incidents/ filed" },
    { claim: "pads filler lines",         mech: "per-section content greps + NEGATIVE greps",                  cmd: "oracle: grep required && grep -v filler" },
    { claim: "edits goalposts mid-run",   mech: "oracle frozen by sha256 at ring open",                        cmd: "ring: sha256(oracle.sh) locked at open" }
  ],

  quotes: [
    "A rule without a mechanism is debt, not protection.",
    "Victory is a green oracle — not 'I tried 8 times'.",
    "The critic is read-only because code kills it on the first write — not because the prompt asked nicely."
  ],

  loop: [
    { t: 0,    kind: "cmd",      text: "$ llms-surf run spec/migrate-lib_x-to-lib_y.md" },
    { t: 600,  kind: "dim",      text: "spec opened · oracle loaded · sha256 frozen at ring open" },
    { t: 1400, kind: "fail",     text: 'oracle pre-check → grep -q "from lib_y import" src/ → exit 1 FAIL · wipeout' },
    { t: 2400, kind: "dim",      text: "failure → structured feedback: missing imports listed" },
    { t: 3100, kind: "dispatch", text: "dispatch → cheap model sweats · 1% frontier plan attached" },
    { t: 4200, kind: "watch",    text: "watchdog tick 1 … artifact growing" },
    { t: 5000, kind: "watch",    text: "watchdog tick 2 … artifact growing" },
    { t: 5800, kind: "dim",      text: "artifact complete · sha256 locked on disk" },
    { t: 6500, kind: "run",      text: 'oracle re-run → grep -q "from lib_y import" src/ && pytest -q' },
    { t: 7400, kind: "pass",     text: "exit 0 ✓ victory is a green oracle." }
  ],

  quickstart: [
    "git clone https://github.com/carl0sfelipe/llms.surf.git",
    "cd llms.surf",
    'export ORACFIT_ROOT="$PWD" DISPATCH_RUNNER="$PWD/adapters/stub/runner.sh"',
    "bin/llms-surf start",
    "bin/llms-surf gui"
  ],

  chips: ["opencode", "Claude Code", "Cursor", "Hermes", "qwen-code", "llama.cpp", "zcode", "prime-agent"],
  adapterChip: "+ stub (and your adapter — one YAML)"
};

const $  = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const WEEKS_PER_MONTH = 52 / 12;
const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
}
const money = n => "$" + Math.round(n).toLocaleString("en-US");

function splitRate() {
  const m = DATA.market;
  return m.split[0] * m.frontierOut + m.split[1] * m.cheapOut;
}

function initHero() {
  const taskSel   = $("#sel-task");
  const budgetSel = $("#sel-budget");
  const rng       = $("#rng-week");
  const outWeek   = $("#out-week");
  const estBox    = $("#estimate");
  if (!taskSel) return;

  Object.keys(DATA.tasks).forEach(k => taskSel.append(new Option(DATA.tasks[k].label, k)));
  Object.keys(DATA.budgets).forEach(k => budgetSel.append(new Option(DATA.budgets[k].label, k)));
  taskSel.value = "migration";
  budgetSel.value = "api100";
  rng.value = 60;

  function paintSlider() {
    const p = ((rng.value - rng.min) / (rng.max - rng.min)) * 100;
    rng.style.background = "linear-gradient(to right, #3FB950 " + p + "%, #1F2733 " + p + "%)";
    outWeek.textContent = rng.value;
  }

  function currentHero() {
    const week   = +rng.value;
    const task   = DATA.tasks[taskSel.value];
    const budget = DATA.budgets[budgetSel.value];
    const perMonth = Math.round(week * WEEKS_PER_MONTH);
    const tokens = task.tokensOutM * perMonth;
    const front  = tokens * DATA.market.frontierOut;
    const disp   = tokens * splitRate();
    return { week, task, budget, perMonth, tokens, front, disp, ratio: front / Math.max(disp, 0.01) };
  }

  function budgetLine(st) {
    const b = st.budget;
    if (b.local) {
      const f = st.tokens * DATA.market.split[0] * DATA.market.frontierOut;
      return { cls: "dim", text: "gpus eat the 99% for ~$0 tokens; frontier 1% ≈ " + money(f) + "/mo api (assumed rates)" };
    }
    if (st.disp <= b.monthly) {
      return { cls: "ok", text: "fits the " + money(b.monthly) + "/mo ceiling under assumed rates — " + money(b.monthly - st.disp) + " headroom" };
    }
    const fitWeek = Math.max(1, Math.floor(b.monthly / (st.task.tokensOutM * splitRate() * WEEKS_PER_MONTH)));
    return { cls: "warn", text: "over the " + money(b.monthly) + "/mo ceiling by " + money(st.disp - b.monthly) + " — fits at ≤ " + fitWeek + " tasks/week" };
  }

  function renderEstimate() {
    const st = currentHero();
    estBox.replaceChildren();
    const add = () => { const d = el("div", "ln"); estBox.append(d); return d; };
    let l;

    l = add();
    l.append(el("span", "dim", '$ llms-surf estimate --task "' + st.task.label + '" --budget "' + st.budget.label + '" --tasks-week ' + st.week));

    l = add();
    l.append(el("span", "k", "frontier-only (assumed):".padEnd(28)), el("span", "warn", money(st.front) + "/mo"));

    l = add();
    l.append(
      el("span", "k", "1%/99% dispatch (assumed):".padEnd(28)),
      el("span", "ok strong", money(st.disp) + "/mo"),
      el("span", "dim", "   (" + Math.round(st.ratio) + "× cheaper)")
    );

    l = add();
    l.append(
      el("span", "k", "oracle:".padEnd(9)),
      el("span", "dim", " " + st.task.oracle + " "),
      el("span", "ok", "→ exit 0 ✓")
    );

    const bl = budgetLine(st);
    l = add();
    l.append(el("span", "k", "budget:".padEnd(9)), el("span", bl.cls, " " + bl.text));

    l = add();
    l.append(el("span", "k", "verdict:".padEnd(9)), el("span", "ok strong", " ships when the disk says so, not the model."));

    l = add();
    l.append(el("span", "dim", "math: " + DATA.market.note));
  }

  [taskSel, budgetSel].forEach(s => s.addEventListener("change", renderEstimate));
  rng.addEventListener("input", () => { paintSlider(); renderEstimate(); });
  paintSlider();
  renderEstimate();
}

function buildStats() {
  const S = DATA.stats;
  const grid = $("#stats-grid");
  if (!grid) return;
  const cells = [
    { n: S.incidents, label: "wipeouts in this cut" },
    { n: S.models,    label: "models in the registry" },
    { n: S.modes,     label: "modes" },
    { n: S.adapters,  label: "adapters (+" + S.adaptersStub + " stub)" },
    { n: S.suites,    label: "test suites guarding the guards" },
    { n: S.version,   label: "public cut version", raw: true }
  ];
  cells.forEach(c => {
    const stat = el("div", "stat");
    const num = el("div", "stat-num", c.raw ? c.n : "0");
    if (!c.raw) num.dataset.target = c.n;
    else num.dataset.done = "1";
    stat.append(num, el("div", "stat-label", c.label));
    grid.append(stat);
  });

  function countUp(node) {
    if (node.dataset.done) return;
    node.dataset.done = "1";
    const target = +node.dataset.target;
    if (reduceMotion) { node.textContent = target.toLocaleString("en-US"); return; }
    const t0 = performance.now(), dur = 1100;
    (function step(now) {
      const p = Math.min(1, (now - t0) / dur);
      const eased = 1 - Math.pow(1 - p, 3);
      node.textContent = Math.round(target * eased).toLocaleString("en-US");
      if (p < 1) requestAnimationFrame(step);
    })(t0);
  }

  const cio = new IntersectionObserver(es => {
    es.forEach(e => {
      if (e.isIntersecting) { $$(".stat-num[data-target]", e.target).forEach(countUp); cio.unobserve(e.target); }
    });
  }, { threshold: 0.3 });
  cio.observe(grid);
}

function buildMechs() {
  const grid = $("#mech-grid");
  if (!grid) return;
  DATA.mechanisms.forEach((m, i) => {
    const a = el("article", "mech");
    const head = el("div", "mech-head");
    head.append(el("span", "mech-id", "w-" + String(i + 1).padStart(3, "0")), el("span", "tag-wipe", "wipeout"));
    a.append(head);
    a.append(el("p", "mech-claim", m.claim));
    a.append(el("p", "mech-arrow", "↓"));
    const head2 = el("div", "mech-head");
    head2.append(el("span", "tag-does", "mechanism"), el("span", "mech-id", "enforced by code"));
    a.append(head2);
    a.append(el("p", "mech-mech", m.mech));
    a.append(el("code", "mech-cmd", m.cmd));
    a.append(el("p", "mech-foot", "logged, learned, never repeated."));
    grid.append(a);
  });
}

function buildChips() {
  $$(".js-chips").forEach(row => {
    row.replaceChildren();
    DATA.chips.forEach(c => row.append(el("span", "chip", c)));
    row.append(el("span", "chip chip-adapter", DATA.adapterChip));
  });
}

function buildQuotes() {
  const grid = $("#wall-grid");
  if (!grid) return;
  DATA.quotes.forEach((q, i) => {
    const bq = el("blockquote", "quote");
    bq.append(el("span", "q-head", "> wall/0" + (i + 1)), el("p", "q-text", q));
    grid.append(bq);
  });
}

function buildQuickstart() {
  $$(".js-qs").forEach(qs => {
    qs.replaceChildren();
    DATA.quickstart.forEach(c => {
      const line = el("div", "qs-line");
      line.append(el("span", "qs-prompt", "$ "), el("span", "qs-cmd", c));
      qs.append(line);
    });
  });
  $$(".js-copy-qs").forEach(btn => {
    if (btn.dataset.bound) return;
    btn.dataset.bound = "1";
    btn.addEventListener("click", () => {
      const text = DATA.quickstart.join("\n");
      const done = () => {
        btn.textContent = "copied ✓";
        btn.classList.add("ok");
        setTimeout(() => { btn.textContent = "copy"; btn.classList.remove("ok"); }, 1400);
      };
      function fallback() {
        const ta = document.createElement("textarea");
        ta.value = text;
        ta.style.position = "fixed"; ta.style.opacity = "0";
        document.body.append(ta); ta.select();
        try { document.execCommand("copy"); done(); } catch (e) { /* noop */ }
        ta.remove();
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done).catch(fallback);
      } else fallback();
    });
  });
}

function fillCounts() {
  const f = $("#foot-count");  if (f) f.textContent = DATA.stats.incidents;
  const w = $("#wipe-count");  if (w) w.textContent = DATA.stats.incidents;
  $$("[data-stat]").forEach(n => {
    const k = n.getAttribute("data-stat");
    if (k && DATA.stats[k] != null) n.textContent = DATA.stats[k];
  });
}

function buildBathy() {
  const svg = $("#bathy");
  if (!svg) return;
  const NS = "http://www.w3.org/2000/svg";
  const TAU = Math.PI * 2;
  svg.setAttribute("viewBox", "0 0 2400 620");
  svg.setAttribute("preserveAspectRatio", "xMidYMid slice");

  const move = document.createElementNS(NS, "g");
  move.setAttribute("class", "bathy-move");
  const tile = document.createElementNS(NS, "g");
  tile.setAttribute("id", "bathy-tile");

  const specs = [
    { y: 80,  a1: 22, a2: 8,  l1: 600, l2: 300, p1: 0.0, p2: 1.2, label: "−15 m"  },
    { y: 170, a1: 30, a2: 10, l1: 400, l2: 200, p1: 0.8, p2: 0.3, label: "−30 m"  },
    { y: 260, a1: 26, a2: 12, l1: 600, l2: 240, p1: 1.7, p2: 2.1, label: "−45 m"  },
    { y: 350, a1: 34, a2: 10, l1: 400, l2: 300, p1: 2.6, p2: 1.1, label: "−60 m"  },
    { y: 440, a1: 28, a2: 14, l1: 300, l2: 200, p1: 3.4, p2: 0.6, label: "−80 m"  },
    { y: 530, a1: 36, a2: 12, l1: 600, l2: 200, p1: 4.2, p2: 2.8, label: "−100 m" }
  ];

  specs.forEach((s, i) => {
    let d = "";
    for (let x = 0; x <= 1200; x += 12) {
      const y = s.y + s.a1 * Math.sin(TAU * x / s.l1 + s.p1) + s.a2 * Math.sin(TAU * x / s.l2 + s.p2);
      d += (x === 0 ? "M" : "L") + x + " " + y.toFixed(1) + " ";
    }
    const p = document.createElementNS(NS, "path");
    p.setAttribute("d", d);
    tile.append(p);
    if (i % 2 === 0) {
      const tx = 140 + i * 160;
      const ty = s.y + s.a1 * Math.sin(TAU * tx / s.l1 + s.p1) + s.a2 * Math.sin(TAU * tx / s.l2 + s.p2) - 6;
      const t = document.createElementNS(NS, "text");
      t.setAttribute("x", tx);
      t.setAttribute("y", ty.toFixed(1));
      t.textContent = s.label;
      tile.append(t);
    }
  });

  move.append(tile);
  const use = document.createElementNS(NS, "use");
  use.setAttribute("href", "#bathy-tile");
  use.setAttribute("x", "1200");
  move.append(use);
  svg.append(move);
}

function buildDividers() {
  const d = "M0 12 Q30 3 60 12 T120 12 T180 12 T240 12 T300 12 T360 12 T420 12 T480 12 " +
            "T540 12 T600 12 T660 12 T720 12 T780 12 T840 12 T900 12 T960 12";
  $$(".swell-div").forEach(node => {
    node.innerHTML = '<svg viewBox="0 0 480 24" preserveAspectRatio="none" aria-hidden="true">' +
                     '<path class="swell-path" d="' + d + '"></path></svg>';
  });
}

function initLoop() {
  const body = $("#loop-body");
  if (!body) return;
  let timers = [];
  let running = false;
  let visible = false;

  function renderStep(s) {
    const d = el("div", "ll ll-" + s.kind, s.text);
    if (s.kind === "dispatch") d.classList.add("flash");
    body.append(d);
    if (s.kind === "pass" || s.kind === "fail") {
      const sw = el("i", "sweep " + (s.kind === "pass" ? "pass" : "fail"));
      d.append(sw);
      setTimeout(() => sw.remove(), 1600);
    }
    body.scrollTop = body.scrollHeight;
  }

  function stop() {
    timers.forEach(clearTimeout);
    timers = [];
    running = false;
    body.replaceChildren();
  }

  function start() {
    if (running || reduceMotion) return;
    running = true;
    body.replaceChildren();
    const steps = DATA.loop;
    steps.forEach(s => timers.push(setTimeout(() => renderStep(s), s.t)));
    const endAt = steps[steps.length - 1].t + 2600;
    timers.push(setTimeout(() => {
      running = false;
      if (visible) start();
    }, endAt));
  }

  if (reduceMotion) { DATA.loop.forEach(renderStep); return; }

  const loopSection = $("#loop");
  if (!loopSection) return;
  new IntersectionObserver(entries => {
    entries.forEach(e => {
      if (e.isIntersecting) { visible = true; start(); }
      else { visible = false; stop(); }
    });
  }, { threshold: 0.2 }).observe(loopSection);
}

function initReveal() {
  const nodes = $$(".reveal");
  if (reduceMotion || !("IntersectionObserver" in window)) {
    nodes.forEach(n => n.classList.add("in"));
    return;
  }
  const io = new IntersectionObserver(es => {
    es.forEach(e => {
      if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    });
  }, { threshold: 0.12 });
  nodes.forEach(n => io.observe(n));
}

buildDividers();
if ($("#sel-task"))   initHero();
if ($("#stats-grid")) buildStats();
if ($("#mech-grid"))  buildMechs();
if ($$(".js-chips").length) buildChips();
if ($("#wall-grid"))  buildQuotes();
buildQuickstart();
fillCounts();
buildBathy();
initLoop();
initReveal();
