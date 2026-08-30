/* journey.js — runs in <head>, no defer. Sets html[data-journey] before paint.
 *
 * Portable: same file on llms.surf and bestmodel.run.
 *   <script src="journey.js" data-key="llms.surf.journey"></script>
 *   <script src="assets/journey.js" data-key="bestmodel.run.journey"></script>
 *
 * Precedence (first hit wins):
 *   1. ?as= / ?view=                      URL — shareable, deterministic
 *   2. localStorage (data-key)           explicit previous click
 *   3. known agent / LLM user-agent
 *   4. search-crawler user-agent         Googlebot etc. → human
 *   5. referrer from a known agent host
 *   else: ask — do not guess
 *
 * Auto-detect is NOT written to localStorage. Only a click (or URL) sticks.
 * Googlebot / Chrome / "Cursor" are not treated as agents — too many humans.
 *
 * Binds button[data-as=human|agent] on DOMContentLoaded. Goal/hardware
 * switchers use data-journey, not data-as — they are a different axis.
 */
(function (w, d) {
  "use strict";
  var script = d.currentScript;
  var KEY = (script && script.getAttribute("data-key")) || "llms.surf.journey";
  var HUMAN_TARGET = "#quickstart";
  if (script && script.hasAttribute("data-human-target")) {
    HUMAN_TARGET = script.getAttribute("data-human-target") || "";
  }
  var html = d.documentElement;

  var AGENT_UA = new RegExp([
    "GPTBot", "ChatGPT-User", "OAI-SearchBot",
    "ClaudeBot", "Claude-User", "anthropic-ai",
    "PerplexityBot", "Perplexity-User",
    "Google-Extended", "Applebot-Extended",
    "Amazonbot", "Bytespider", "CCBot",
    "meta-externalagent", "cohere-ai",
    "YouBot", "DuckAssistBot", "Diffbot",
    "AI2Bot", "iaskspider", "ImagesiftBot",
    "Timpibot", "Webzio-Extended", "PetalBot",
    "HuggingFace(?:Bot)?", "MetaAI", "PhindBot",
    "xAI-Grok", "GrokBot",
    "OpenHands", "SWE-agent", "Aiderbot"
  ].join("|"), "i");

  var AGENT_REF = /(^|\.)((chatgpt|claude|perplexity|poe|phind|you)\.com|chat\.openai\.com|gemini\.google\.com|copilot\.microsoft\.com|huggingface\.co|grok\.x\.ai)$/i;

  var HOW = {
    ask: "no ?as=, no saved choice, UA is a normal browser, referrer is not a chat product.",
    url: "from the URL (?as=).",
    saved: "from a previous explicit choice on this browser.",
    ua: "from a known agent / LLM user-agent.",
    search: "from a search-crawler user-agent — not an agent runtime.",
    referrer: "from the referring chat product.",
    click: "you picked."
  };

  function norm(v) {
    v = String(v || "").toLowerCase();
    if (v === "agent" || v === "human") return v;
    return null;
  }

  function fromUrl() {
    try {
      var u = new URL(w.location.href);
      var q = norm(u.searchParams.get("as") || u.searchParams.get("view"));
      if (q) return q;
    } catch (e) { /* noop */ }
    return null;
  }

  function fromStore() {
    try { return norm(w.localStorage.getItem(KEY)); }
    catch (e) { return null; }
  }

  var SEARCH_UA = /Googlebot|Bingbot|bingbot|Slurp|DuckDuckBot|Baiduspider|Yandex(?:Bot|Images)|facebookexternalhit|LinkedInBot|Twitterbot|Applebot(?!-Extended)|Chrome-Lighthouse|Lighthouse/i;

  function fromUa() {
    var ua = w.navigator && w.navigator.userAgent;
    if (!ua) return null;
    if (AGENT_UA.test(ua)) return { value: "agent", how: "ua" };
    if (SEARCH_UA.test(ua)) return { value: "human", how: "search" };
    return null;
  }

  function fromRef() {
    try {
      var r = d.referrer;
      if (!r) return null;
      var host = new URL(r).hostname.replace(/^www\./, "");
      return AGENT_REF.test(host) ? { value: "agent", how: "referrer" } : null;
    } catch (e) { return null; }
  }

  function resolve() {
    var v;
    v = fromUrl();   if (v) return { value: v, how: "url" };
    v = fromStore(); if (v) return { value: v, how: "saved" };
    v = fromUa();    if (v) return v;
    v = fromRef();   if (v) return v;
    return { value: "ask", how: "ask" };
  }

  function apply(state) {
    html.setAttribute("data-journey", state.value);
    html.setAttribute("data-journey-how", state.how);
  }

  function persist(value) {
    try { w.localStorage.setItem(KEY, value); }
    catch (e) { /* private mode */ }
  }

  function writeUrl(value) {
    try {
      var u = new URL(w.location.href);
      if (value === "ask") u.searchParams.delete("as");
      else u.searchParams.set("as", value);
      u.searchParams.delete("view");
      w.history.replaceState(null, "", u.pathname + u.search + u.hash);
    } catch (e) { /* noop */ }
  }

  var state = resolve();
  apply(state);

  function paintUi() {
    var st = api.get();
    var how = HOW[st.how] || st.how;
    var nodes = d.querySelectorAll("button[data-as]");
    for (var i = 0; i < nodes.length; i++) {
      var on = nodes[i].getAttribute("data-as") === st.value;
      nodes[i].setAttribute("aria-pressed", on ? "true" : "false");
    }
    var howNodes = d.querySelectorAll(".js-journey-how");
    for (var j = 0; j < howNodes.length; j++) {
      howNodes[j].textContent = st.value === "ask"
        ? how
        : "reading as " + st.value + " · " + how;
    }
    function aria(sel, show) {
      var list = d.querySelectorAll(sel);
      for (var k = 0; k < list.length; k++) {
        list[k].setAttribute("aria-hidden", show ? "false" : "true");
      }
    }
    aria(".for-ask", st.value === "ask");
    aria(".for-human", st.value === "human");
    aria(".for-agent", st.value === "agent");
  }

  function afterHuman() {
    if (!HUMAN_TARGET) return;
    var target = d.querySelector(HUMAN_TARGET);
    if (target) {
      try { target.scrollIntoView({ block: "start" }); }
      catch (e) { /* noop */ }
    }
  }

  var api = {
    key: KEY,
    get: function () {
      return {
        value: html.getAttribute("data-journey"),
        how: html.getAttribute("data-journey-how")
      };
    },
    set: function (value, opts) {
      value = norm(value);
      if (!value) return;
      opts = opts || {};
      state = { value: value, how: opts.how || "click" };
      apply(state);
      if (opts.persist !== false) persist(value);
      if (opts.url !== false) writeUrl(value);
      paintUi();
      if (value === "human") afterHuman();
      if (typeof opts.after === "function") opts.after(state);
      try { d.dispatchEvent(new CustomEvent("llms-journey", { detail: state })); }
      catch (e) { /* noop */ }
    },
    paint: paintUi
  };

  w.READER_JOURNEY = api;
  w.LLMS_JOURNEY = api;

  function bindUi() {
    var btns = d.querySelectorAll("button[data-as]");
    for (var i = 0; i < btns.length; i++) {
      if (btns[i].dataset.bound) continue;
      btns[i].dataset.bound = "1";
      btns[i].addEventListener("click", function () {
        api.set(this.getAttribute("data-as"), { persist: true, url: true, how: "click" });
      });
    }
    paintUi();
  }

  if (d.readyState === "loading") d.addEventListener("DOMContentLoaded", bindUi);
  else bindUi();
})(window, document);
