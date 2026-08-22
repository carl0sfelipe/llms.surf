/* Oracfit GUI — shell compartilhado (sidebar, fetch, listas com teto de 5).
 * Princípios i-have-adhd aplicados aqui:
 *  - navegação persistente (memória de trabalho fora da cabeça do leitor)
 *  - listas com no máximo 5 itens visíveis + "ver mais N" explícito
 *  - vocabulário sem vergonha: "aberto"/"sem nota ainda", nunca "pendente"/"atrasado"
 */
"use strict";

const GUI_PAGES = [
  { group: "Agir", items: [
    { href: "home.html", label: "Agora", id: "home" },
    { href: "hitl.html", label: "Calibração", id: "hitl" },
  ]},
  { group: "Observar", items: [
    { href: "rings.html", label: "Anéis", id: "rings" },
    { href: "dispatches.html", label: "Dispatches", id: "dispatches" },
    { href: "index.html", label: "Run ao vivo", id: "live" },
  ]},
  { group: "Manutenção", items: [
    { href: "corte.html", label: "Corte público", id: "corte" },
    { href: "incidents.html", label: "Incidents", id: "incidents" },
    { href: "registry.html", label: "Modelos & uso", id: "registry" },
  ]},
];

function buildSidebar() {
  const host = document.getElementById("sidebar");
  if (!host) return;
  const page = document.body.dataset.page || "";
  let html = '<h1 class="brand">ORACFIT<small>GUI local · leitura</small></h1>';
  for (const g of GUI_PAGES) {
    html += `<div class="nav-group-label">${g.group}</div>`;
    for (const it of g.items) {
      const active = it.id === page ? " active" : "";
      html += `<a class="nav-link${active}" href="${it.href}" data-nav="${it.id}">${it.label}` +
              `<span class="nav-count" data-navcount="${it.id}"></span></a>`;
    }
  }
  host.innerHTML = html;
  // contagem "para dar nota" ao lado de Calibração — progresso visível sem abrir a página
  fetch("/api/rings").then((r) => r.json()).then((d) => {
    if (d && d.ok && d.to_score > 0) {
      const el = host.querySelector('[data-navcount="hitl"]');
      if (el) el.textContent = String(d.to_score);
    }
  }).catch(() => {});
}

async function getJSON(url) {
  const res = await fetch(url);
  let body = null;
  try { body = await res.json(); } catch (_) { /* corpo não-JSON vira erro abaixo */ }
  if (!res.ok || !body) {
    const msg = body && body.error ? body.error : `HTTP ${res.status} em ${url}`;
    throw new Error(msg);
  }
  return body;
}

async function postJSON(url, payload) {
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  let body = null;
  try { body = await res.json(); } catch (_) { /* idem */ }
  if (!body) throw new Error(`HTTP ${res.status} em ${url}`);
  return { status: res.status, body };
}

const esc = (s) => String(s == null ? "" : s)
  .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;");

function fmtTs(ts) {
  if (!ts) return "—";
  try {
    const d = typeof ts === "number" ? new Date(ts * 1000) : new Date(ts);
    return d.toLocaleString("pt-BR", { day: "2-digit", month: "2-digit",
      hour: "2-digit", minute: "2-digit" });
  } catch (_) { return String(ts); }
}

function fmtDur(s) {
  if (s == null || isNaN(s)) return "—";
  s = Math.round(Number(s));
  if (s < 90) return `${s}s`;
  if (s < 5400) return `${Math.round(s / 60)}min`;
  return `${(s / 3600).toFixed(1)}h`;
}

/* Lista com teto de 5 itens + "ver mais N" (regra 9 da skill). */
function renderCapped(container, items, renderItem, cap = 5) {
  container.innerHTML = "";
  if (!items.length) return;
  const list = document.createElement("div");
  list.className = "row-list";
  container.appendChild(list);
  const draw = (n) => {
    list.innerHTML = items.slice(0, n).map(renderItem).join("");
    const old = container.querySelector(".see-more");
    if (old) old.remove();
    if (items.length > n) {
      const btn = document.createElement("button");
      btn.className = "see-more";
      btn.type = "button";
      btn.textContent = `ver mais ${items.length - n}`;
      btn.addEventListener("click", () => draw(items.length));
      container.appendChild(btn);
    }
  };
  draw(cap);
}

function showError(el, err) {
  el.innerHTML = `<div class="alert-banner">Falha ao carregar: ${esc(err.message || err)}</div>`;
}

/* Glossário mínimo compartilhado — o jargão do framework em palavras comuns.
 * Renderizado em toda página que tiver <div id="glossary">. */
const GLOSSARY = [
  ["anel", "um bloco de trabalho com começo e fim que um robô entrega de uma vez"],
  ["oráculo", "o teste automático que decide se o trabalho está pronto (verde = pronto)"],
  ["critic / revisor", "um segundo robô que revisa o trabalho do primeiro e dá uma opinião"],
  ["veredito", "a opinião escrita do revisor: aprovado ou devolvido, e qual a maior falha"],
  ["delta", "a diferença entre a nota que o revisor previu e a nota que VOCÊ deu"],
  ["dispatch", "uma tarefa entregue a um robô para fazer sozinho"],
  ["ledger", "o caderno de registro onde cada acontecimento fica anotado, em ordem"],
];

function buildGlossary() {
  const host = document.getElementById("glossary");
  if (!host) return;
  host.innerHTML = `
    <details class="ver-mais panel" style="padding:var(--space-3) var(--space-4)">
      <summary>Dicionário rápido — o que significam as palavras desta tela</summary>
      <dl class="glossary">
        ${GLOSSARY.map(([t, d]) => `<dt>${esc(t)}</dt><dd>${esc(d)}</dd>`).join("")}
      </dl>
    </details>`;
}

document.addEventListener("DOMContentLoaded", () => { buildSidebar(); buildGlossary(); });
