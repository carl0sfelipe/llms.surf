/* Oracfit panel v3 — observe-only. Poll incremental via Range. Sem chamadas a modelo. */
(function () {
  "use strict";

  const POLL_MS = 2500;
  const LOG_POLL_MS = 4000;
  const LOG_TAIL_BYTES = 65536;
  const LOG_LINES = 60;
  const MAX_EVENTS_PER_RUN = 3000;
  const FEED_LIMIT = 50;
  const PREVIEW_MAX = 300;
  const THINKING_MAX = 200;
  const CMD_PREVIEW_MAX = 80;

  const state = {
    runs: new Map(),
    selectedRunId: null,
    feedFilters: new Set(["tool_call", "thinking", "prompt_sent"]),
    feedTotal: false,
    filesFreshMtime: new Map(),
    autoScroll: true,
    logsPath: "/logs/events.jsonl",
    logsDirLabel: ".dispatch/logs/",
    byteOffset: 0,
    lastErr: null,
    cold: true,
    modeStageHints: new Map(),
    logAutoScroll: true,
    stageLog: {
      file: null,
      size: null,
      text: "",
      currentTask: null,
      err: null,
    },
  };

  const $ = (id) => document.getElementById(id);

  function num(v) {
    if (v == null || v === "") return null;
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }

  function truthy(v) {
    if (v === true || v === "true") return true;
    if (v === false || v === "false") return false;
    return null;
  }

  function trunc(s, max) {
    const t = String(s || "");
    return t.length <= max ? t : t.slice(0, max) + "…";
  }

  function tsShort(iso) {
    if (!iso) return "—";
    try {
      const d = new Date(iso);
      if (Number.isNaN(d.getTime())) return String(iso).slice(11, 19);
      return d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    } catch {
      return String(iso).slice(11, 19);
    }
  }

  function tsStart(iso) {
    if (!iso) return "—";
    try {
      const d = new Date(iso);
      return d.toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
    } catch {
      return String(iso).slice(0, 16);
    }
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function escapeAttr(s) {
    return escapeHtml(s).replace(/'/g, "&#39;");
  }

  function stripAnsi(s) {
    return String(s || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
  }

  function stripBoxDrawing(s) {
    return String(s || "")
      .replace(/[│╭╮╯╰─━┌┐└┘├┤┬┴┼═║╔╗╚╝╠╣╦╩╬▁▂▃▄▅▆▇█▀▁▔▏▕▖▗▘▙▚▛▜▝▞▟]/g, " ")
      .replace(/ {2,}/g, " ");
  }

  function cleanLogLine(s) {
    return stripBoxDrawing(stripAnsi(s)).trimEnd();
  }

  function extractCurrentTask(tailText) {
    const re = /Executing task:\s+(\S+)/g;
    let match;
    let last = null;
    while ((match = re.exec(tailText)) !== null) {
      last = match[1];
    }
    return last;
  }

  function formatBytes(n) {
    if (n == null || !Number.isFinite(n)) return "—";
    if (n < 1024) return n + " B";
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB";
    return (n / (1024 * 1024)).toFixed(1) + " MB";
  }

  function pickBestLogFile(files) {
    if (!files || !files.length) return null;
    const logs = files.filter((f) => f.name && f.name.endsWith(".log"));
    if (!logs.length) return null;
    const preferred = logs.filter((f) => /^(mech|driver|oracle)-/.test(f.name));
    const pool = preferred.length ? preferred : logs;
    return pool.reduce((best, f) => (!best || (f.mtime || 0) > (best.mtime || 0) ? f : best), null);
  }

  // Conteúdo completo fica em memória (modo Total precisa dele); só um teto
  // duro por campo para não explodir com um output patológico. A truncagem
  // curta acontece na RENDERIZAÇÃO do modo simples, não na ingestão.
  const INGEST_HARD_CAP = 20000;

  function sanitizeEvent(raw) {
    const ev = { ...raw };
    if (ev.type === "tool_call") {
      if (ev.cmd_output && !ev.preview) ev.preview = ev.cmd_output;
      delete ev.cmd_output;
      if (ev.preview) ev.preview = trunc(ev.preview, INGEST_HARD_CAP);
      if (ev.input && typeof ev.input === "object") {
        const slim = { ...ev.input };
        for (const k of Object.keys(slim)) {
          if (typeof slim[k] === "string" && slim[k].length > INGEST_HARD_CAP) {
            slim[k] = trunc(slim[k], INGEST_HARD_CAP);
          }
        }
        ev.input = slim;
      }
    }
    if (ev.type === "thinking" && ev.detail) {
      ev.detail = trunc(ev.detail, INGEST_HARD_CAP);
    }
    if (ev.type === "prompt_sent" && ev.content) {
      ev._contentLen = ev.content.length;
      ev.content = trunc(ev.content, INGEST_HARD_CAP);
    }
    return ev;
  }

  function emptyRun(id) {
    return {
      run_id: id,
      mode: "—",
      task: "—",
      model_id: "—",
      stagesTotal: null,
      stageOrder: [],
      stageIndex: {},
      activeStage: null,
      activeIndex: null,
      status: "live",
      reason: null,
      firstTs: null,
      lastTs: null,
      events: [],
      attempts: 0,
      duration_s: 0,
      flash_work_s: 0,
      estimated_cost: null,
      stageStats: new Map(),
      loopBacks: [],
      messageConsumed: null,
    };
  }

  function ensureStage(run, name) {
    if (!run.stageStats.has(name)) {
      run.stageStats.set(name, {
        name,
        attempts: new Set(),
        oracles: [],
        loopBacks: [],
      });
    }
    return run.stageStats.get(name);
  }

  function ingestEvent(run, ev) {
    run.events.push(ev);
    if (run.events.length > MAX_EVENTS_PER_RUN) {
      run.events.splice(0, run.events.length - MAX_EVENTS_PER_RUN);
    }

    if (ev.ts) {
      const t = Date.parse(ev.ts);
      if (!Number.isNaN(t)) {
        if (run.firstTs == null || t < run.firstTs) run.firstTs = t;
        if (run.lastTs == null || t > run.lastTs) run.lastTs = t;
      }
    }

    const type = ev.type;

    if (type === "run_started") {
      if (ev.mode) run.mode = ev.mode;
      if (ev.task) run.task = ev.task;
      if (ev.model_id) run.model_id = ev.model_id;
      run.stagesTotal = num(ev.stages);
      run.status = "live";
      run.reason = null;
    }

    if (type === "stage_changed") {
      const stage = ev.stage || "—";
      const idx = num(ev.index);
      if (idx != null) run.stageIndex[stage] = idx;
      if (!run.stageOrder.includes(stage)) {
        run.stageOrder.push(stage);
        run.stageOrder.sort((a, b) => (run.stageIndex[a] ?? 99) - (run.stageIndex[b] ?? 99));
      }
      run.activeStage = stage;
      run.activeIndex = idx;
    }

    if (type === "attempt_started") {
      run.attempts = Math.max(run.attempts, num(ev.attempt) || 0);
      const st = ev.stage || run.activeStage;
      if (st) ensureStage(run, st).attempts.add(num(ev.attempt) || 1);
    }

    if (type === "attempt_finished") {
      const d = num(ev.duration_s);
      if (d != null) run.duration_s += d;
    }

    if (type === "oracle_result") {
      const stage = ev.stage || run.activeStage || "—";
      const exit = num(ev.exit);
      const cmd = ev.command ? trunc(ev.command, CMD_PREVIEW_MAX) : "";
      ensureStage(run, stage).oracles.push({
        exit,
        attempt: num(ev.attempt),
        command: cmd,
        ts: ev.ts,
      });
    }

    if (type === "gauntlet_loop_back") {
      const lb = {
        from: ev.from,
        to: ev.to,
        count: num(ev.count),
        ceiling: num(ev.ceiling),
        ts: ev.ts,
      };
      run.loopBacks.push(lb);
      if (ev.from) ensureStage(run, ev.from).loopBacks.push(lb);
    }

    if (type === "metric") {
      const fw = num(ev.flash_work_s);
      if (fw != null) run.flash_work_s = Math.max(run.flash_work_s, fw);
      if (ev.estimated_cost != null) run.estimated_cost = ev.estimated_cost;
      if (ev.model_id) run.model_id = ev.model_id;
    }

    if (type === "run_finished") {
      const st = String(ev.status || "").toLowerCase();
      run.status = st === "pass" ? "pass" : "fail";
      if (ev.reason) run.reason = ev.reason;
      const d = num(ev.duration_s);
      if (d != null && run.duration_s === 0) run.duration_s = d;
    }

    if (type === "message_consumed") {
      run.messageConsumed = { count: num(ev.count), attempt: num(ev.attempt), ts: ev.ts };
    }
  }

  function processEvents(rawEvents, reset) {
    if (reset) state.runs.clear();

    for (const raw of rawEvents) {
      if (!raw || !raw.run_id || !raw.type) continue;
      const id = raw.run_id;
      if (!state.runs.has(id)) state.runs.set(id, emptyRun(id));
      ingestEvent(state.runs.get(id), sanitizeEvent(raw));
    }

    state.cold = state.runs.size === 0;

    for (const r of state.runs.values()) {
      if (r.stageOrder.length >= 2) {
        state.modeStageHints.set(r.mode, [...r.stageOrder]);
      }
    }

    if (!state.selectedRunId || !state.runs.has(state.selectedRunId)) {
      state.selectedRunId = pickDefaultRun();
    }
  }

  function pickDefaultRun() {
    const ids = sortedRunIds();
    return ids.length ? ids[0] : null;
  }

  function sortedRunIds() {
    return [...state.runs.keys()].sort((a, b) => {
      const ra = state.runs.get(a);
      const rb = state.runs.get(b);
      const ta = ra.lastTs ?? ra.firstTs ?? 0;
      const tb = rb.lastTs ?? rb.firstTs ?? 0;
      if (tb !== ta) return tb - ta;
      return b.localeCompare(a);
    });
  }

  function parseJsonl(text) {
    const out = [];
    for (const line of text.split("\n")) {
      const s = line.trim();
      if (!s) continue;
      try {
        out.push(JSON.parse(s));
      } catch {
        /* linha malformada — pular */
      }
    }
    return out;
  }

  // Run que morreu sem emitir run_finished ficaria "LIVE" para sempre;
  // sem evento novo há 10 min = abandonado.
  const STALE_MS = 10 * 60 * 1000;

  function displayStatus(r) {
    if (r.status === "live" && r.lastTs != null && Date.now() - r.lastTs > STALE_MS) {
      const fileMtime = state.filesFreshMtime.get(r.run_id) || 0;
      if (Date.now() - fileMtime <= STALE_MS) return "live";
      return "stale";
    }
    return r.status;
  }

  function runLabel(r) {
    const task = (r.task || r.run_id.slice(0, 8)).replace(/^journey-/, "");
    const when = tsStart(r.events.find((e) => e.type === "run_started")?.ts);
    let badge;
    const st = displayStatus(r);
    if (st === "live") badge = "● LIVE";
    else if (st === "stale") badge = "◌ abandonado";
    else if (st === "pass") badge = "✓ pass";
    else badge = "✗ fail";
    return `${badge} · ${r.mode} · ${task} · ${when}`;
  }

  function alertsFor(run) {
    if (!run) return [];
    const out = [];
    for (const ev of run.events) {
      if (ev.type === "run_finished" && run.status === "fail") {
        out.push({ level: "err", text: `Run falhou${run.reason ? ": " + run.reason : ""}` });
      }
      if (ev.type === "preflight_result" && truthy(ev.pass) === false) {
        out.push({ level: "warn", text: `Preflight ${ev.step || "?"}: ${ev.reason || "falhou"}` });
      }
      if (ev.type === "behavior_scan") {
        const high = num(ev.high) || 0;
        if (high > 0) {
          out.push({ level: "err", text: `behavior_scan: ${high} flag(s) alta(s) — ${ev.flags || ""}` });
        }
      }
      if (ev.type === "gauntlet_loop_back") {
        const count = num(ev.count);
        const ceiling = num(ev.ceiling);
        if (count != null && ceiling != null && count >= ceiling - 1) {
          out.push({
            level: "warn",
            text: `Loop-back ${ev.from}→${ev.to} perto do teto (${count}/${ceiling})`,
          });
        }
      }
      if (ev.type === "classify_result" && truthy(ev.allowed) === false) {
        out.push({ level: "warn", text: `Classify bloqueou: ${ev.class || "?"}` });
      }
    }
    const seen = new Set();
    return out.filter((a) => {
      const k = a.text;
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
  }

  function pipelineStages(run) {
    if (!run) return [];
    const hint = state.modeStageHints.get(run.mode) || [];
    const known = [...run.stageOrder];
    const total = run.stagesTotal || Math.max(hint.length, known.length) || 0;
    const stages = [];
    for (let i = 0; i < Math.max(total, known.length); i++) {
      const name = known[i] || hint[i] || `·`;
      const stats = run.stageStats.get(name) || { attempts: new Set(), oracles: [], loopBacks: [] };
      const pending = !known[i] && hint[i];
      stages.push({ name, index: run.stageIndex[name] ?? i, stats, pending });
    }
    return stages;
  }

  function renderAll() {
    renderSwitcher();
    renderHeader();
    renderAlerts();
    renderPipeline();
    renderStageLog();
    renderFeed();
    renderMetrics();
  }

  function selectedRun() {
    return state.selectedRunId ? state.runs.get(state.selectedRunId) : null;
  }

  function renderSwitcher() {
    const sel = $("run-switcher");
    const ids = sortedRunIds();
    if (!ids.length) {
      sel.innerHTML = `<option value="">nenhum run recente</option>`;
      return;
    }
    sel.innerHTML = ids
      .map((id) => {
        const r = state.runs.get(id);
        const selected = id === state.selectedRunId ? " selected" : "";
        return `<option value="${escapeAttr(id)}" title="${escapeAttr(id)}"${selected}>${escapeHtml(runLabel(r))}</option>`;
      })
      .join("");
  }

  function renderHeader() {
    const run = selectedRun();
    $("sb-mode").textContent = run ? run.mode : "—";
    $("sb-task").textContent = run ? run.task : "—";
    $("sb-model").textContent = run ? run.model_id : "—";

    const st = $("sb-status");
    st.className = "status-badge";
    if (!run) {
      st.textContent = state.lastErr ? "erro" : "cold";
      st.classList.add(state.lastErr ? "fail" : "cold");
    } else if (displayStatus(run) === "live") {
      st.textContent = "LIVE";
      st.classList.add("live");
    } else if (displayStatus(run) === "stale") {
      st.textContent = "abandonado";
      st.classList.add("cold");
    } else if (run.status === "pass") {
      st.textContent = "pass";
      st.classList.add("pass");
    } else {
      st.textContent = run.reason ? `fail · ${run.reason}` : "fail";
      st.classList.add("fail");
    }

    const link = $("logs-link");
    if (run) {
      link.href = `/logs/inbox/${encodeURIComponent(run.run_id)}.run.gauntlet/`;
      link.hidden = false;
    } else {
      link.hidden = true;
    }

    const consumed = $("hitl-consumed");
    if (run?.messageConsumed) {
      consumed.hidden = false;
      consumed.textContent = `message_consumed · attempt ${run.messageConsumed.attempt ?? "?"} · count ${run.messageConsumed.count ?? "?"}`;
    } else {
      consumed.hidden = true;
    }
  }

  function renderAlerts() {
    const el = $("alerts");
    const run = selectedRun();
    const items = alertsFor(run);
    if (!items.length) {
      el.hidden = true;
      el.innerHTML = "";
      return;
    }
    el.hidden = false;
    el.innerHTML = items.map((a) => `<div class="alert alert-${a.level}">${escapeHtml(a.text)}</div>`).join("");
  }

  function renderPipeline() {
    const run = selectedRun();
    const empty = $("pipeline-empty");
    const track = $("pipeline-track");
    if (!run || !run.stageOrder.length) {
      empty.hidden = false;
      track.hidden = true;
      empty.textContent = run ? "Pipeline ainda sem stages…" : "Aguardando eventos…";
      return;
    }
    empty.hidden = true;
    track.hidden = false;

    const stages = pipelineStages(run);
    const parts = [];
    for (let i = 0; i < stages.length; i++) {
      const s = stages[i];
      const isActive = run.activeStage === s.name && displayStatus(run) === "live";
      const activeCls = isActive ? " active" : "";
      const doneCls = run.stageIndex[s.name] != null && run.activeIndex != null && run.stageIndex[s.name] < run.activeIndex ? " done" : "";
      const pendingCls = s.pending ? " pending" : "";

      const attemptCount = s.stats.attempts.size;
      const oracleChips = s.stats.oracles
        .map((o) => {
          const ok = o.exit === 0;
          const cls = ok ? "oracle-ok" : "oracle-fail";
          const hint = ok ? "" : EXIT_HINTS[o.exit] || "";
          const tipTxt = [o.command, !ok && hint ? `exit ${o.exit}: ${hint}` : ""]
            .filter(Boolean)
            .join(" — ");
          const tip = tipTxt ? ` title="${escapeAttr(tipTxt)}"` : "";
          const label = ok
            ? "✓ ok"
            : `✗ exit ${o.exit ?? "?"}${hint ? " · " + hint : ""}`;
          return `<span class="oracle-chip ${cls}"${tip}>${label}</span>`;
        })
        .join("");

      const loopHtml = s.stats.loopBacks
        .map((lb) => {
          const hot = lb.count != null && lb.ceiling != null && lb.count >= lb.ceiling - 1;
          return `<span class="loop-chip${hot ? " hot" : ""}">↩ ${lb.from}→${lb.to} ${lb.count}/${lb.ceiling}</span>`;
        })
        .join("");

      let taskChip = "";
      if (isActive) {
        const task = state.stageLog.currentTask;
        if (task) {
          taskChip = `<div class="stage-task-chip">task atual: ${escapeHtml(task)}</div>`;
        } else if (displayStatus(run) === "live") {
          taskChip = `<div class="stage-task-chip waiting">aguardando…</div>`;
        }
      }

      parts.push(
        `<div class="stage-node${activeCls}${doneCls}${pendingCls}">` +
          `<div class="stage-name">${escapeHtml(s.name)}</div>` +
          `<div class="stage-meta">${attemptCount ? attemptCount + " tent." : ""}</div>` +
          taskChip +
          `<div class="stage-oracles">${oracleChips}</div>` +
          `<div class="stage-loops">${loopHtml}</div>` +
          `</div>`
      );

      if (i < stages.length - 1) {
        const lbBetween = run.loopBacks.find((lb) => lb.from === s.name);
        const arrowCls = lbBetween && lbBetween.count >= (lbBetween.ceiling || 99) - 1 ? " arrow-hot" : "";
        parts.push(`<div class="stage-arrow${arrowCls}" aria-hidden="true">→</div>`);
      }
    }
    track.innerHTML = parts.join("");
  }

  function renderStageLog() {
    const title = $("stage-log-title");
    const body = $("stage-log-body");
    const run = selectedRun();
    const sl = state.stageLog;

    if (!run) {
      title.textContent = "—";
      body.textContent = "Selecione um run para ver o log do gauntlet…";
      return;
    }

    if (sl.err) {
      title.textContent = sl.file ? `${sl.file} (erro)` : "erro";
      body.textContent = sl.err;
      return;
    }

    if (!sl.file) {
      const live = displayStatus(run) === "live";
      title.textContent = live ? "buscando log…" : "sem log gauntlet";
      body.textContent = live ? "Aguardando arquivos de log…" : "Nenhum log encontrado para este run.";
      return;
    }

    title.textContent = `${sl.file} · ${formatBytes(sl.size)}`;

    const lines = sl.text.split("\n").map(cleanLogLine).filter((l) => l.length > 0);
    const visible = lines.slice(-LOG_LINES).join("\n");
    const nearBottom = body.scrollHeight - body.scrollTop - body.clientHeight < 48;
    body.textContent = visible || "(log vazio)";

    if (state.logAutoScroll || nearBottom) {
      body.scrollTop = body.scrollHeight;
      state.logAutoScroll = true;
      $("log-resume").hidden = true;
    }
  }

  async function fetchStageLog() {
    const run = selectedRun();
    if (!run) {
      state.stageLog = { file: null, size: null, text: "", currentTask: null, err: null };
      renderStageLog();
      return;
    }

    try {
      const rf = await fetch(
        `/api/runfiles?run_id=${encodeURIComponent(run.run_id)}&t=${Date.now()}`,
        { cache: "no-store" }
      );
      if (!rf.ok) {
        state.stageLog.err = rf.status === 404 ? "diretório gauntlet não encontrado" : `HTTP ${rf.status} em /api/runfiles`;
        renderStageLog();
        renderPipeline();
        return;
      }
      const rfData = await rf.json();
      // Stage mecânico longo (vision gate ~20 min) não emite evento nenhum,
      // mas escreve log continuamente — mtime dos arquivos é sinal de vida
      // que evita o falso "abandonado" no run selecionado.
      const freshest = Math.max(
        0,
        ...(rfData.files || []).map((f) => (f.mtime || 0) * 1000)
      );
      state.filesFreshMtime.set(run.run_id, freshest);
      const best = pickBestLogFile(rfData.files || []);
      if (!best) {
        state.stageLog = {
          file: null,
          size: null,
          text: "",
          currentTask: null,
          err: run.status === "live" ? null : null,
        };
        renderStageLog();
        renderPipeline();
        return;
      }

      const tl = await fetch(
        `/api/tail?run_id=${encodeURIComponent(run.run_id)}&file=${encodeURIComponent(best.name)}&bytes=${LOG_TAIL_BYTES}&t=${Date.now()}`,
        { cache: "no-store" }
      );
      if (!tl.ok) {
        state.stageLog.err = `HTTP ${tl.status} lendo ${best.name}`;
        renderStageLog();
        return;
      }
      const tlData = await tl.json();
      state.stageLog = {
        file: best.name,
        size: tlData.size ?? best.size,
        text: tlData.tail || "",
        currentTask: tlData.current_task || extractCurrentTask(tlData.tail || ""),
        err: null,
      };
      renderStageLog();
      renderPipeline();
    } catch (e) {
      state.stageLog.err = String(e.message || e);
      renderStageLog();
    }
  }

  function feedItems(run) {
    if (!run) return [];
    // Modo Total: TODOS os eventos do run, de qualquer tipo, sem limite —
    // runs mecânicos (content_factory) não emitem tool_call/thinking, então
    // filtrar pelos 3 tipos de feed deixava o Total vazio.
    const list = state.feedTotal
      ? run.events
      : run.events.filter((ev) => state.feedFilters.has(ev.type));
    const items = state.feedTotal ? list : list.slice(-FEED_LIMIT);
    const counter = $("feed-count");
    if (counter) {
      counter.textContent = list.length
        ? `${items.length} de ${list.length} eventos`
        : "";
    }
    return items;
  }

  // Número de exit pelado no chip não diz nada pra quem olha o painel
  // ("127 o que???"). Códigos de shell conhecidos ganham tradução.
  const EXIT_HINTS = {
    1: "falha",
    2: "uso incorreto",
    124: "timeout",
    126: "sem permissão",
    127: "comando não encontrado",
    130: "interrompido",
    137: "morto (kill/OOM)",
  };

  const GENERIC_SKIP_KEYS = new Set([
    "ts", "type", "run_id", "mode", "task", "schema", "v", "host", "pid",
  ]);

  function genericEventBody(ev) {
    const parts = [];
    for (const [k, v] of Object.entries(ev)) {
      if (GENERIC_SKIP_KEYS.has(k) || k.startsWith("_") || v == null) continue;
      const s = typeof v === "object" ? JSON.stringify(v) : String(v);
      if (s === "") continue;
      parts.push(`${k}=${trunc(s, 160)}`);
    }
    return parts.join(" · ");
  }

  function renderFeed() {
    const el = $("feed");
    const run = selectedRun();

    if (state.lastErr) {
      el.innerHTML =
        `<div class="error-state">Não foi possível ler ${escapeHtml(state.logsDirLabel)}` +
        `<br/><span class="muted">${escapeHtml(state.lastErr)}</span></div>`;
      return;
    }

    if (state.cold) {
      el.innerHTML =
        `<div class="empty-state" id="feed-empty">` +
        `Nenhum evento ainda.<br />` +
        `O silêncio aqui significa que nada foi despachado.` +
        `</div>`;
      return;
    }

    const items = feedItems(run);
    if (!items.length) {
      el.innerHTML = `<div class="empty-state">Nenhum evento de feed para este run (ajuste filtros ou aguarde).</div>`;
      return;
    }

    const total = state.feedTotal;

    const expandable = (cls, badgeCls, badgeTxt, ev, summaryTxt, fullTxt) =>
      `<details class="feed-item ${cls}" open>` +
      `<summary><span class="feed-ts">${escapeHtml(tsShort(ev.ts))}</span>` +
      `<span class="feed-badge ${badgeCls}">${escapeHtml(badgeTxt)}</span>` +
      `<span class="feed-body">${escapeHtml(summaryTxt)}</span></summary>` +
      `<pre class="prompt-body">${escapeHtml(fullTxt)}</pre>` +
      `</details>`;

    const html = items.map((ev) => {
      if (ev.type === "tool_call") {
        const exit = ev.cmd_exit != null ? ` exit ${ev.cmd_exit}` : "";
        const preview = ev.preview || ev.detail || "";
        if (total) {
          const full =
            (ev.input ? "── input ──\n" + JSON.stringify(ev.input, null, 2) + "\n" : "") +
            (preview ? "── output ──\n" + preview : "");
          return expandable(
            "feed-tool", "tool", ev.tool || "?", ev,
            trunc(preview, 120) + exit,
            full || "(sem detalhe)"
          );
        }
        return (
          `<article class="feed-item feed-tool">` +
          `<span class="feed-ts">${escapeHtml(tsShort(ev.ts))}</span>` +
          `<span class="feed-badge tool">${escapeHtml(ev.tool || "?")}</span>` +
          `<span class="feed-body">${escapeHtml(trunc(preview, PREVIEW_MAX))}${escapeHtml(exit)}</span>` +
          `</article>`
        );
      }
      if (ev.type === "thinking") {
        const detail = ev.detail || "";
        if (total && detail.length > THINKING_MAX) {
          return expandable("feed-think", "think", "thinking", ev, trunc(detail, 120), detail);
        }
        return (
          `<article class="feed-item feed-think">` +
          `<span class="feed-ts">${escapeHtml(tsShort(ev.ts))}</span>` +
          `<span class="feed-badge think">thinking</span>` +
          `<span class="feed-body">${escapeHtml(total ? detail : trunc(detail, THINKING_MAX))}</span>` +
          `</article>`
        );
      }
      if (ev.type === "prompt_sent") {
        const len = ev._contentLen || (ev.content || "").length;
        return (
          `<details class="feed-item feed-prompt"${total ? " open" : ""}>` +
          `<summary><span class="feed-ts">${escapeHtml(tsShort(ev.ts))}</span>` +
          `<span class="feed-badge prompt">prompt</span>` +
          `<span class="feed-body">attempt ${ev.attempt ?? "?"} · ${len} chars${ev.truncated ? " (truncado)" : ""}</span></summary>` +
          `<pre class="prompt-body">${escapeHtml(ev.content || "")}</pre>` +
          `</details>`
        );
      }
      // Eventos de ciclo de vida (stage_changed, oracle_result,
      // gauntlet_loop_back, metric…) — só aparecem no modo Total.
      if (total) {
        return expandable(
          "feed-generic", "generic", ev.type || "?", ev,
          genericEventBody(ev).slice(0, 160),
          JSON.stringify(ev, null, 2)
        );
      }
      return (
        `<article class="feed-item feed-generic">` +
        `<span class="feed-ts">${escapeHtml(tsShort(ev.ts))}</span>` +
        `<span class="feed-badge generic">${escapeHtml(ev.type || "?")}</span>` +
        `<span class="feed-body">${escapeHtml(genericEventBody(ev))}</span>` +
        `</article>`
      );
    });

    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 48;
    el.innerHTML = html.join("");
    if (state.autoScroll || nearBottom) {
      el.scrollTop = el.scrollHeight;
      state.autoScroll = true;
      $("resume").hidden = true;
    }
  }

  function renderMetrics() {
    const run = selectedRun();
    $("mb-duration").textContent = run && run.duration_s ? run.duration_s.toFixed(1) + "s" : "—";
    $("mb-attempts").textContent = run ? String(run.attempts || "—") : "—";
    $("mb-flash").textContent = run && run.flash_work_s ? String(run.flash_work_s) : "—";
    $("mb-cost").textContent = run && run.estimated_cost != null ? String(run.estimated_cost) : "—";
  }

  async function fetchEvents() {
    try {
      const headers = {};
      if (state.byteOffset > 0) headers.Range = `bytes=${state.byteOffset}-`;

      const res = await fetch(state.logsPath + "?t=" + Date.now(), { cache: "no-store", headers });

      if (res.status === 404) {
        if (state.byteOffset === 0) {
          state.cold = true;
          state.runs.clear();
          state.lastErr = null;
        }
        renderAll();
        return;
      }

      if (res.status === 416) {
        state.byteOffset = 0;
        await fetchEvents();
        return;
      }

      if (!res.ok && res.status !== 206) {
        state.lastErr = `HTTP ${res.status} lendo ${state.logsPath}`;
        renderAll();
        return;
      }

      const text = await res.text();
      const reset = res.status === 200;
      if (reset && state.byteOffset === 0 && text.length === 0) {
        state.cold = true;
        renderAll();
        return;
      }

      const events = parseJsonl(text);
      if (events.length || reset) {
        processEvents(events, reset);
        state.cold = state.runs.size === 0;
        state.lastErr = null;
      }

      const cr = res.headers.get("Content-Range");
      if (cr) {
        const m = cr.match(/\/(\d+|\*)$/);
        if (m && m[1] !== "*") state.byteOffset = parseInt(m[1], 10);
        else state.byteOffset += text.length;
      } else {
        state.byteOffset = reset ? text.length : state.byteOffset + text.length;
      }

      renderAll();
    } catch (e) {
      state.lastErr = String(e.message || e);
      renderAll();
    }
  }

  async function loadConfig() {
    try {
      const res = await fetch("runtime-config.json?t=" + Date.now(), { cache: "no-store" });
      if (res.ok) {
        const cfg = await res.json();
        if (cfg.logs_url) state.logsPath = cfg.logs_url;
        if (cfg.logs_dir) state.logsDirLabel = cfg.logs_dir;
      }
    } catch {
      /* opcional */
    }
  }

  // ── quota por provider (/api/usage) ──
  const ACTION_BADGE = { use: "pass", wait: "live", exhausted: "fail" };
  const ACTION_RANK = { exhausted: 0, wait: 1, use: 2 };

  function fmtTok(n) {
    if (n == null || n === "") return "—";
    const v = Number(n);
    if (!Number.isFinite(v)) return "—";
    if (v < 1000) return String(Math.round(v));
    if (v < 1e6) return Math.round(v / 1000) + "k";
    return (v / 1e6).toFixed(1).replace(/\.0$/, "") + "M";
  }

  function fmtDur(s) {
    if (s == null || !Number.isFinite(Number(s))) return "—";
    const t = Math.round(Number(s));
    const m = Math.floor(t / 60);
    const sec = t % 60;
    if (m === 0) return sec + "s";
    return m + "m " + sec + "s";
  }

  function nowHms() {
    try {
      return new Date().toLocaleTimeString("pt-BR", {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      });
    } catch {
      const d = new Date();
      return (
        String(d.getHours()).padStart(2, "0") +
        ":" +
        String(d.getMinutes()).padStart(2, "0") +
        ":" +
        String(d.getSeconds()).padStart(2, "0")
      );
    }
  }

  function tokCell(label, v) {
    return `<span class="usage-tok"><b class="usage-tok-label">${label}</b> ${fmtTok(v)}</span>`;
  }

  async function fetchUsage() {
    try {
      const res = await fetch("/api/usage", { cache: "no-store" });
      const data = await res.json();
      renderUsage(data);
    } catch (e) {
      renderUsage({ ok: false, error: String(e.message || e) });
    }
  }

  function renderUsage(data) {
    const panel = $("usage-panel");
    const body = $("usage-body");
    if (!panel || !body) return;

    if (!data || data.ok !== true) {
      panel.hidden = false;
      const err = data && data.error ? String(data.error) : "resposta inválida";
      body.innerHTML = `<div class="usage-unavailable">hub indisponível: ${escapeHtml(err)}</div>`;
      $("usage-updated").textContent = "atualizado " + nowHms();
      return;
    }

    const providers = Array.isArray(data.providers) ? data.providers : [];
    const filtered = providers.filter((p) => {
      const tok = p.tokens || {};
      const allZero = [tok["5h"], tok.day, tok.week].every((v) => !(Number(v) > 0));
      return !(allZero && p.action === "use");
    });

    filtered.sort((a, b) => {
      const ra = ACTION_RANK[a.action] ?? 3;
      const rb = ACTION_RANK[b.action] ?? 3;
      if (ra !== rb) return ra - rb;
      const ta = Number(a.tokens && a.tokens["5h"]) || 0;
      const tb = Number(b.tokens && b.tokens["5h"]) || 0;
      return tb - ta;
    });

    if (!filtered.length) {
      panel.hidden = true;
      body.innerHTML = "";
      return;
    }

    panel.hidden = false;
    const rows = filtered.map((p) => {
      const tok = p.tokens || {};
      const action = ACTION_BADGE[p.action] ? p.action : "use";
      const cls = ACTION_BADGE[action] || "cold";
      let barHtml = "";
      const pct = Number(p.limit_pct);
      if (p.limit_pct != null && Number.isFinite(pct)) {
        const w = Math.max(0, Math.min(100, pct));
        const hot = w > 85 ? " hot" : "";
        barHtml = `<div class="usage-bar"><div class="usage-bar-fill${hot}" style="width:${w}%"></div></div>`;
      }
      let obs = "";
      const o = p.last_observation_24h;
      if (o && typeof o === "object") {
        obs =
          `<div class="usage-obs">` +
          `${escapeHtml(o.kind || "")} · ${escapeHtml(o.model || "")} · ${escapeHtml(o.ts || "")}` +
          `</div>`;
      }
      return (
        `<div class="usage-row">` +
        `<span class="usage-name">${escapeHtml(p.provider || "?")}</span>` +
        `<span class="status-badge ${cls}">${escapeHtml(action)}</span>` +
        `<span class="usage-toks">` +
        tokCell("5h", tok["5h"]) +
        tokCell("day", tok.day) +
        tokCell("week", tok.week) +
        `</span>` +
        barHtml +
        obs +
        `</div>`
      );
    });

    body.innerHTML = rows.join("");
    $("usage-updated").textContent = "atualizado " + nowHms();
  }

  // ── batch (progresso de lote) ──
  const BATCH_RESULT_BADGE = { success: "pass", blocked: "fail", "already-passing": "cold" };

  function parseJsonlStrict(text) {
    const out = [];
    for (const line of String(text || "").split("\n")) {
      const s = line.trim();
      if (!s) continue;
      try {
        out.push(JSON.parse(s));
      } catch {
        /* linha truncada/inválida — pular */
      }
    }
    return out;
  }

  async function fetchBatch() {
    try {
      const [batchRes, escalateRes] = await Promise.all([
        fetch("/logs/batch-ledger.jsonl", { cache: "no-store" }),
        fetch("/logs/escalate-ledger.jsonl", { cache: "no-store" }),
      ]);
      if (!batchRes.ok && !escalateRes.ok) return;
      const batchText = batchRes.ok ? await batchRes.text() : "";
      const escalateText = escalateRes.ok ? await escalateRes.text() : "";
      renderBatch(batchText, escalateText);
    } catch {
      /* seção continua hidden */
    }
  }

  function renderBatch(batchText, escalateText) {
    const panel = $("batch-panel");
    const body = $("batch-body");
    if (!panel || !body) return;

    const batches = parseJsonlStrict(batchText);
    const escalate = parseJsonlStrict(escalateText);

    if (!batches.length && !escalate.length) {
      panel.hidden = true;
      body.innerHTML = "";
      return;
    }

    panel.hidden = false;
    const parts = [];

    if (batches.length) {
      const last = batches[batches.length - 1];
      const total = num(last.total) || 0;
      const ok = num(last.ok) || 0;
      const failed = num(last.failed) || 0;
      const okPct = total ? Math.round((ok / total) * 100) : 0;
      const failPct = total ? Math.round((failed / total) * 100) : 0;
      const items = Array.isArray(last.items) ? last.items : [];

      const chips = [];
      const shown = Math.min(items.length, 12);
      for (let i = 0; i < shown; i++) {
        const it = items[i] || {};
        const good = it.result === "success";
        const cls = good ? "ok" : "fail";
        chips.push(
          `<span class="batch-chip ${cls}">${escapeHtml(it.task || "?")} ${escapeHtml(fmtDur(it.duration_s))}</span>`
        );
      }
      if (items.length > shown) {
        chips.push(`<span class="batch-chip more">+${items.length - shown}</span>`);
      }

      parts.push(
        `<div class="batch-block">` +
        `<div class="batch-head"><span class="batch-run">${escapeHtml(last.run_id || "?")}</span>` +
        `<span class="batch-count">${ok}/${failed}/${total}</span></div>` +
        `<div class="batch-bar"><div class="batch-bar-ok" style="width:${okPct}%"></div>` +
        `<div class="batch-bar-fail" style="width:${failPct}%"></div></div>` +
        `<div class="batch-meta">duração ${escapeHtml(fmtDur(last.total_s))}</div>` +
        `<div class="batch-chips">${chips.join("")}</div>` +
        `</div>`
      );
    }

    if (escalate.length) {
      const recent = escalate.slice(-5);
      const rows = recent.map((it) => {
        const cls = BATCH_RESULT_BADGE[it.result] || "cold";
        return (
          `<div class="batch-item">` +
          `<span class="batch-task">${escapeHtml(it.task_name || "?")}</span>` +
          `<span class="status-badge ${cls}">${escapeHtml(it.result || "?")}</span>` +
          `<span class="batch-tier">${escapeHtml(it.tier || "")}</span>` +
          `<span class="batch-dur">${escapeHtml(fmtDur(it.duration_s))}</span>` +
          `</div>`
        );
      });
      parts.push(
        `<div class="batch-block">` +
        `<div class="batch-sub">últimos itens (escalate)</div>` +
        rows.join("") +
        `</div>`
      );
    }

    body.innerHTML = parts.join("");
  }

  // wiring
  $("run-switcher").addEventListener("change", (e) => {
    state.selectedRunId = e.target.value || null;
    state.stageLog = { file: null, size: null, text: "", currentTask: null, err: null };
    renderAll();
    fetchStageLog();
  });

  document.querySelectorAll("[data-feed]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const t = btn.getAttribute("data-feed");
      if (state.feedFilters.has(t)) {
        state.feedFilters.delete(t);
        btn.classList.remove("on");
      } else {
        state.feedFilters.add(t);
        btn.classList.add("on");
      }
      renderAll();
    });
  });

  $("btn-feed-total").addEventListener("click", () => {
    state.feedTotal = !state.feedTotal;
    $("btn-feed-total").classList.toggle("on", state.feedTotal);
    $("btn-feed-total").setAttribute("aria-pressed", state.feedTotal ? "true" : "false");
    renderAll();
  });

  if (new URLSearchParams(location.search).get("total") === "1") {
    $("btn-feed-total").click();
  }

  $("btn-pause-scroll").addEventListener("click", () => {
    state.autoScroll = !state.autoScroll;
    $("btn-pause-scroll").classList.toggle("on", state.autoScroll);
    $("btn-pause-scroll").setAttribute("aria-pressed", state.autoScroll ? "true" : "false");
    if (state.autoScroll) {
      $("feed").scrollTop = $("feed").scrollHeight;
      $("resume").hidden = true;
    }
  });

  $("feed").addEventListener("scroll", () => {
    const el = $("feed");
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 48;
    if (!nearBottom) {
      state.autoScroll = false;
      $("resume").hidden = false;
      $("btn-pause-scroll").classList.remove("on");
    }
  });

  $("resume").addEventListener("click", () => {
    state.autoScroll = true;
    $("btn-pause-scroll").classList.add("on");
    $("resume").hidden = true;
    $("feed").scrollTop = $("feed").scrollHeight;
  });

  $("btn-log-pause-scroll").addEventListener("click", () => {
    state.logAutoScroll = !state.logAutoScroll;
    $("btn-log-pause-scroll").classList.toggle("on", state.logAutoScroll);
    $("btn-log-pause-scroll").setAttribute("aria-pressed", state.logAutoScroll ? "true" : "false");
    if (state.logAutoScroll) {
      $("stage-log-body").scrollTop = $("stage-log-body").scrollHeight;
      $("log-resume").hidden = true;
    }
  });

  $("stage-log-body").addEventListener("scroll", () => {
    const el = $("stage-log-body");
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 48;
    if (!nearBottom) {
      state.logAutoScroll = false;
      $("log-resume").hidden = false;
      $("btn-log-pause-scroll").classList.remove("on");
    }
  });

  $("log-resume").addEventListener("click", () => {
    state.logAutoScroll = true;
    $("btn-log-pause-scroll").classList.add("on");
    $("log-resume").hidden = true;
    $("stage-log-body").scrollTop = $("stage-log-body").scrollHeight;
  });

  $("hitl-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const statusEl = $("hitl-status");
    const text = $("hitl-text").value.trim();
    const interrupt = $("hitl-interrupt").checked;

    if (!state.selectedRunId) {
      statusEl.textContent = "selecione um run";
      return;
    }
    if (!text) {
      statusEl.textContent = "mensagem vazia";
      return;
    }

    statusEl.textContent = "enviando…";
    try {
      const resp = await fetch("/api/message", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ run_id: state.selectedRunId, text, interrupt }),
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      statusEl.textContent = interrupt ? "interrupção pedida + mensagem enfileirada" : "enfileirada";
      $("hitl-text").value = "";
      $("hitl-interrupt").checked = false;
    } catch (err) {
      statusEl.textContent = `falhou: ${err.message}`;
    }
    setTimeout(() => {
      statusEl.textContent = "";
    }, 5000);
  });

  loadConfig().then(() => {
    fetchEvents();
    fetchStageLog();
    fetchUsage();
    fetchBatch();
    setInterval(fetchEvents, POLL_MS);
    setInterval(fetchStageLog, LOG_POLL_MS);
    setInterval(fetchUsage, 30000);
    setInterval(fetchBatch, 30000);
  });
})();
