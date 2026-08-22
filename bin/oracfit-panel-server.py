#!/usr/bin/env python3
"""oracfit-panel-server.py — static panel/GUI + read-only logs mount (AD-8).

Usage:
  oracfit-panel-server.py --panel-dir DIR --logs-dir DIR [--port N] [--bind ADDR]
                          [--oracfit-root DIR] [--ring-target DIR]

Serves:
  /           -> panel static files (index.html = run ao vivo; *.html = GUI)
  /logs/      -> workdir .dispatch/logs/ (events.jsonl etc.) read-only
  /runtime-config.json -> path metadata (no write into panel/)
  /api/message (POST) -> HITL v1 (AD-8 amendment 2026-08-01): escreve
    mensagem do humano na fila do run (.dispatch/logs/inbox/<run_id>.jsonl)
    e, se pedido, toca o arquivo de interrupt que o runner watchdog ja
    checa (adapters/*/runner.sh). Nunca chama modelo diretamente daqui —
    so escreve arquivo; quem consome e o dispatch-mode.sh do proximo attempt.

REMOTE (2026-08-22 — celular/túnel, ver docs/gui-remote.md):
  --auth-token SEGREDO -> TODO pedido exige token (cookie oracfit_auth via
    POST /login, ou header Authorization: Bearer). Fail-closed: --bind fora
    do loopback SEM token recusa subir (exit 3). Token < 16 chars recusa.
  /login (GET form + POST JSON {"token": ...}) -> cookie HttpOnly
    SameSite=Strict (+Secure atrás de proxy https).
  /api/gui/modes (GET) -> modes (workdir overlay + root) e adapters com
    env.sh — alimenta o formulário de dispatch (regra 38: dispatch
    desligado aparece como desligado, nunca some).
  /api/dispatch (POST, SÓ com --enable-dispatch) -> inicia um dispatch DE
    VERDADE pelo mesmo caminho do terminal: oracfit daemon start (double-
    fork+setsid, imune à morte da GUI) + bin/oracfit-dispatch-gui.sh, que
    sourceia o adapter (zcode, opencode, …) e exec `oracfit run`. Sem
    --enable-dispatch o POST recusa 404 — o default da GUI continua
    read-only + HITL. Validação fail-closed ANTES do subprocess: mode tem
    que existir, spec resolve DENTRO do workdir e é .md, adapter tem
    env.sh, task casa [a-z0-9._-]. argv explícito, nunca shell=True.

GUI (2026-08-13) — endpoints READ-ONLY, exceto /api/ring-score:
  /api/rings           -> aneis do --ring-target (HITL de calibracao).
    ANTI-ANCORA: anel sem nota real NAO carrega a previsao do critic no
    payload — a previsao so volta na RESPOSTA do POST de score, senao ela
    vira ancora e a calibracao nao mede nada.
    Por anel fechado tambem: delivered (frase mecanica do close), screens
    (ring/screens/<RING>/ do alvo), note (ring/notes/<RING>.md filtrada) e
    how_to_test (linha "como testar" das notas/DO-DONO, se existir).
  /ring-file/<rel>     -> arquivo estatico RESTRITO ao ring/ do --ring-target
    (imagens de gate visual, notas). Path traversal bloqueado por
    os.path.realpath dentro da raiz permitida + whitelist de extensao.
  /api/ring-score (POST) -> unico write da GUI: executa
    `oracfit ring score RING-N --real N` de verdade (subprocess com argv
    explicito, nunca shell=True/eval; N inteiro 0-10; anel fechado e sem
    nota — validado ANTES do subprocess).
  /api/gui/home        -> agora: runs vivos, aneis abertos, disco, audit
  /api/gui/dispatches  -> 3 ledgers DECLARADOS (regra 38: fonte ausente
    aparece como ausente, nunca some em silencio)
  /api/gui/rings       -> ring-v1 do ledger central agrupado por run
  /api/gui/incidents   -> incidents/ + saida do incident.sh audit
  /api/gui/registry    -> model-registry.json + core/usage-limits.json
  /api/gui/corte       -> payload do corte-review.py (revisão do corte público)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse

RUN_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
LOG_FILE_RE = re.compile(r"^[A-Za-z0-9._-]+\.log$")
RING_ID_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
REAL_SCORE_RE = re.compile(r"^(10|[0-9])$")
MODE_ID_RE = re.compile(r"^[a-z0-9_]{1,64}$")
TASK_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
ADAPTER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")

# --auth-token: token curto é token quebrado — força estourar na subida
MIN_TOKEN_LEN = 16
AUTH_COOKIE = "oracfit_auth"
AUTH_COOKIE_MAX_AGE = 30 * 24 * 3600

LOGIN_PAGE = """<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Oracfit — entrar</title>
<style>
body{margin:0;font-family:system-ui,sans-serif;background:#0B1120;color:#E8F0FE;
     display:flex;min-height:100vh;align-items:center;justify-content:center}
form{background:#111827;padding:32px;border-radius:12px;width:min(92vw,360px);
     display:flex;flex-direction:column;gap:12px}
h1{font-size:18px;margin:0}p{font-size:13px;color:#8BA3C7;margin:0}
input{padding:12px;border-radius:8px;border:1px solid #4A6080;background:#0B1120;
      color:#E8F0FE;font-size:16px}
button{padding:12px;border-radius:8px;border:0;background:#FFB800;color:#0B1120;
       font-size:15px;font-weight:600;cursor:pointer}
#err{color:#FF4757;font-size:13px;min-height:1em}
</style>
</head>
<body>
<form id="f">
  <h1>ORACFIT</h1>
  <p>Esta GUI está protegida por token.</p>
  <input type="password" id="t" autocomplete="current-password" autofocus>
  <div id="err"></div>
  <button type="submit">entrar</button>
</form>
<script>
document.getElementById("f").addEventListener("submit", async (e) => {
  e.preventDefault();
  const res = await fetch("/login", {method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({token: document.getElementById("t").value})});
  if (res.ok) { location.href = "home.html"; return; }
  document.getElementById("err").textContent = "token errado";
});
</script>
</body>
</html>
""".encode("utf-8")


def enforce_bind_guard(bind: str, token: str | None) -> str | None:
    """Fail-closed do acesso remoto: bind fora do loopback exige token.

    Retorna a mensagem de erro (e o chamador sai 3) ou None se passou.
    Usado pelo main daqui E pelo main do oracfit-todo-server (a GUI real).
    """
    loopback = bind.startswith("127.") or bind in ("::1", "localhost")
    if loopback:
        return None
    if not token:
        return ("ERROR: --bind fora do loopback exige --auth-token — "
                "GUI sem autenticação não sobe em rede (fail-closed; docs/gui-remote.md)")
    if len(token) < MIN_TOKEN_LEN:
        return f"ERROR: --auth-token precisa de >= {MIN_TOKEN_LEN} caracteres"
    return None

# /ring-file/: só o que a página de calibração precisa (imagem de gate visual,
# render de terminal, nota do executor). Nada de .sh/.jsonl/.json por aqui.
RING_FILE_TYPES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
    ".txt": "text/plain; charset=utf-8",
    ".md": "text/markdown; charset=utf-8",
}
IMG_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"}

BIN_DIR = Path(__file__).resolve().parent
USAGE_HUB = BIN_DIR / "usage-hub.py"
RING_SCRIPT = BIN_DIR / "oracfit-ring.sh"
INCIDENT_SCRIPT = BIN_DIR / "incident.sh"
_USAGE_CACHE: tuple[float, dict] | None = None
_USAGE_CACHE_TTL = 15.0
_AUDIT_CACHE: tuple[float, dict] | None = None
_AUDIT_CACHE_TTL = 60.0


# ── leitura de fontes (tudo read-only) ───────────────────────────────────────

def read_jsonl(path: Path) -> list[dict]:
    """Linhas JSON validas de um .jsonl; linha quebrada e pulada, nunca mata."""
    out: list[dict] = []
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(e, dict):
            out.append(e)
    return out


def checkpoint_sections(path: Path, hide_patterns: list[str]) -> dict[str, str]:
    """Secoes '## <ring> — …' do CHECKPOINTS.md, por ring.

    hide_patterns: linhas contendo qualquer padrao sao removidas do excerpt —
    e por aqui que a previsao do critic (owner_score_pred) vazaria para a
    tela antes da nota do dono (anti-ancora).
    """
    sections: dict[str, str] = {}
    if not path.is_file():
        return sections
    current: str | None = None
    buf: list[str] = []
    header = re.compile(r"^##\s+(\S+)\s+—")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = header.match(line)
        if m:
            if current:
                sections[current] = "\n".join(buf).strip()
            current = m.group(1)
            buf = []
            continue
        if current is None:
            continue
        if any(pat in line for pat in hide_patterns):
            continue
        buf.append(line)
    if current:
        sections[current] = "\n".join(buf).strip()
    return sections


def extract_target_rings(target: Path) -> dict:
    """Aneis do run atual de um alvo com ring/ (state.json + ledger.jsonl)."""
    state_file = target / "ring" / "state.json"
    if not state_file.is_file():
        raise FileNotFoundError(f"{state_file} não existe — alvo sem ring init")
    state = json.loads(state_file.read_text(encoding="utf-8"))
    run = state.get("run") or ""
    score_field = state.get("score_field") or "owner_score_pred"
    # nas notas do executor so a previsao precisa sumir; no checkpoint tambem
    # a linha de biggest_gap — a opiniao do revisor so aparece DEPOIS da nota
    hide_note = [score_field, "owner_score_pred"]
    hide_ckpt = hide_note + ["**Critic:**", "biggest_gap"]
    events = [
        e for e in read_jsonl(target / "ring" / "ledger.jsonl")
        if e.get("schema") == "ring-v1" and e.get("run") == run
    ]
    rings = merge_ring_events(events, score_field)
    # excerpt do checkpoint sem a linha do critic (previsao vazaria — anti-ancora)
    excerpts = checkpoint_sections(target / "CHECKPOINTS.md", hide_ckpt)
    closed, open_rings = [], []
    for r in rings:
        if r.get("status") == "fechado":
            ex = excerpts.get(r["ring"], "")
            if ex:
                r["checkpoint_excerpt"] = ex[:900]
            r["plain"] = plain_summary(r)
            r["delivered"] = delivered_summary(r)
            r["screens"] = ring_screens(target, r["ring"])
            note = ring_note(target, r["ring"], hide_note)
            if note:
                r["note"] = note
            htt = extract_how_to_test(
                target / "ring" / "notes" / f"{r['ring']}.md",
                target / "DO-DONO.md",
            )
            if htt:
                r["how_to_test"] = htt
            if not r.get("scored"):
                # ANTI-ANCORA: previsao fica fora do payload ate a nota existir
                r.pop("pred", None)
                r.pop("delta", None)
            else:
                # nota ja dada — o veredito completo do critic pode aparecer
                critic = critic_verdict(target, r["ring"])
                if critic:
                    r["critic"] = critic
            closed.append(r)
        elif r.get("status") == "aberto":
            open_rings.append(r)
    # worktrees da casa chamam-se wt-<projeto>; o dono conhece o projeto
    name = target.name
    project = name[3:] if name.startswith("wt-") else name
    return {
        "target": str(target),
        "project": project,
        "run": run,
        "mode": state.get("mode"),
        "rings": closed,
        "open_rings": open_rings,
        "to_score": sum(1 for r in closed if not r.get("scored")),
    }


def delivered_summary(r: dict) -> str:
    """"O que foi entregue" — frase-template dos dados MECANICOS do close.
    Nunca usa previsao/veredito do critic (anti-ancora, aparece antes da nota)."""
    files = r.get("files_staged") or 0
    tests = r.get("test_files") or 0
    runs = (r.get("oracle") or {}).get("runs") or 0
    commit = r.get("build_commit")
    attempts = len(r.get("close_attempts") or [])
    bits = []
    if files:
        arq = "arquivo" if files == 1 else "arquivos"
        bits.append(f"Mexeu em {files} {arq}" + (f" ({tests} de teste)" if tests else ""))
    else:
        bits.append("Não mexeu em código — trabalho de organização ou documentação")
    if runs:
        vez = "vez" if runs == 1 else "vezes"
        bits.append(f"passou os testes automáticos {runs} {vez}")
    if commit:
        bits.append(f"commit {commit}")
    s = ", ".join(bits) + "."
    if attempts:
        vez = "vez" if attempts == 1 else "vezes"
        s += f" O sistema recusou a entrega {attempts} {vez} antes de aceitar."
    return s


def ring_screens(target: Path, ring: str) -> list[dict]:
    """Evidencias visuais de ring/screens/<RING>/ do alvo: imagem vira URL do
    /ring-file/; render de terminal (.txt pequeno) vai inline no payload."""
    d = target / "ring" / "screens" / ring
    out: list[dict] = []
    if not d.is_dir():
        return out
    for f in sorted(d.iterdir()):
        if not f.is_file():
            continue
        ext = f.suffix.lower()
        if ext in IMG_EXTS:
            out.append({"name": f.name, "kind": "img",
                        "url": f"/ring-file/screens/{quote(ring)}/{quote(f.name)}"})
        elif ext == ".txt" and f.stat().st_size <= 8192:
            try:
                content = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            out.append({"name": f.name, "kind": "text", "content": content})
    return out


def ring_note(target: Path, ring: str, hide_patterns: list[str]) -> str:
    """Nota completa do executor (ring/notes/<RING>.md), com as linhas que
    citariam a previsao do critic removidas (anti-ancora)."""
    f = target / "ring" / "notes" / f"{ring}.md"
    if not f.is_file():
        return ""
    try:
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    kept = [ln for ln in lines if not any(p in ln for p in hide_patterns)]
    return "\n".join(kept).strip()[:6000]


def extract_how_to_test(*paths: Path) -> str:
    """Primeira linha de "como testar" achada nas notas do anel ou DO-DONO.md.
    Se o rotulo tiver comando inline (apos ':'), usa; senao, a proxima linha
    nao-vazia. Sem match -> "" (a secao some, nunca placeholder)."""
    pat = re.compile(r"como testar|para testar", re.IGNORECASE)
    for p in paths:
        if not p.is_file():
            continue
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for i, line in enumerate(lines):
            if not pat.search(line):
                continue
            inline = line.split(":", 1)[1].strip() if ":" in line else ""
            if inline:
                return inline.strip("`").strip()[:400]
            for nxt in lines[i + 1:i + 6]:
                t = nxt.strip()
                if t and not t.startswith("```"):
                    return t.lstrip("$ ").strip("`").strip()[:400]
    return ""


def critic_verdict(target: Path, ring: str) -> dict | None:
    """Resumo util de ring/verdicts/<RING>.json — SO entra no payload depois
    da nota do dono. owner_score_pred nunca sai daqui (ja vai no campo pred)."""
    f = target / "ring" / "verdicts" / f"{ring}.json"
    if not f.is_file():
        return None
    try:
        v = json.loads(f.read_text(encoding="utf-8", errors="replace"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(v, dict):
        return None
    claims = [c for c in (v.get("claims") or []) if isinstance(c, dict)]
    findings = [
        {"severity": x.get("severity"), "description": x.get("description")}
        for x in (v.get("findings") or []) if isinstance(x, dict)
    ]
    return {
        "verdict": v.get("verdict"),
        "biggest_gap": v.get("biggest_gap"),
        "claims_total": len(claims),
        "claims_verified": sum(1 for c in claims if c.get("status") == "VERIFIED"),
        "findings": findings[:8],
    }


def merge_ring_events(events: list[dict], score_field: str) -> list[dict]:
    """Funde eventos ring-v1 (open/close_attempt/close/abort/owner_score) por anel."""
    rings: dict[str, dict] = {}
    order: list[str] = []
    for e in events:
        ring = e.get("ring")
        ev = e.get("event")
        if not ring or not ev:
            continue
        if ring not in rings:
            rings[ring] = {"ring": ring, "status": "aberto", "close_attempts": [], "scored": False}
            order.append(ring)
        r = rings[ring]
        if ev == "open":
            r["hypothesis"] = e.get("hypothesis", "")
            r["opened_at"] = e.get("ts")
        elif ev == "close_attempt":
            r["close_attempts"].append(e.get("reason", "?"))
        elif ev == "close":
            r["status"] = "fechado"
            r["closed_at"] = e.get("ts")
            r["oracle"] = e.get("oracle")
            r["files_staged"] = e.get("files_staged")
            r["test_files"] = e.get("test_files")
            r["verdict"] = e.get("verdict")
            r["biggest_gap"] = e.get("biggest_gap")
            r["build_commit"] = e.get("build_commit")
            r["pred"] = e.get(score_field)
        elif ev == "abort":
            r["status"] = "abortado"
            r["abort_reason"] = e.get("reason")
        elif ev == "owner_score":
            r["scored"] = True
            r["real"] = e.get("real")
            r["pred"] = e.get("pred")
            r["delta"] = e.get("delta")
    return [rings[k] for k in order]


def plain_summary(r: dict) -> str:
    """Bloco "Em português claro" — template determinístico (sem LLM) sobre os
    números MEDIDOS do anel. NUNCA usa a previsão/veredito do critic: este
    texto aparece ANTES da nota do dono e não pode ancorar (anti-âncora)."""
    hyp = (r.get("hypothesis") or "um bloco de trabalho").strip().rstrip(".")
    oracle = r.get("oracle") or {}
    runs = oracle.get("runs") or 0
    files = r.get("files_staged") or 0
    tests = r.get("test_files") or 0
    attempts = len(r.get("close_attempts") or [])
    s = [f"Um robô trabalhou neste projeto e entregou: {hyp}."]
    if files:
        if tests:
            s.append(f"Mexeu em {files} arquivo(s), sendo {tests} de teste.")
        else:
            s.append(f"Mexeu em {files} arquivo(s).")
    else:
        s.append("Não mexeu em código — foi trabalho de organização ou documentação.")
    if runs:
        vez = "vez" if runs == 1 else "vezes"
        s.append(f"Os testes automáticos passaram {runs} {vez} antes da entrega.")
    if attempts:
        vez = "vez" if attempts == 1 else "vezes"
        s.append(f"O sistema devolveu o trabalho {attempts} {vez} por falta de requisito antes de aceitar.")
    s.append("Um revisor automático já deu a opinião dele — você vai vê-la depois de dar a sua.")
    return " ".join(s)


def central_ring_groups(root: Path) -> list[dict]:
    """Eventos ring-v1 do ledger central agrupados por run (mais recente 1º)."""
    events = [e for e in read_jsonl(root / "ledger" / "ledger.jsonl")
              if e.get("schema") == "ring-v1"]
    by_run: dict[str, list[dict]] = {}
    run_order: list[str] = []
    for e in events:
        run = e.get("run") or "?"
        if run not in by_run:
            by_run[run] = []
            run_order.append(run)
        by_run[run].append(e)
    groups = []
    for run in reversed(run_order):
        evs = by_run[run]
        rings = merge_ring_events(evs, "owner_score_pred")
        groups.append({
            "run": run,
            "mode": evs[0].get("mode"),
            "first_ts": evs[0].get("ts"),
            "last_ts": evs[-1].get("ts"),
            "rings": rings,
            "closed": sum(1 for r in rings if r["status"] == "fechado"),
            "scored": sum(1 for r in rings if r.get("scored")),
            "refused_attempts": sum(len(r["close_attempts"]) for r in rings),
        })
    return groups


def dispatch_sources(root: Path, logs_dir: Path) -> dict:
    """3 ledgers de dispatch, DECLARADOS (regra 38: fonte ausente aparece)."""
    srcs = [
        ("dispatch", root / "ledger" / "ledger.jsonl"),
        ("escalate", logs_dir / "escalate-ledger.jsonl"),
        ("batch", logs_dir / "batch-ledger.jsonl"),
    ]
    declared, runs = [], []
    for name, path in srcs:
        exists = path.is_file()
        entries = read_jsonl(path) if exists else []
        if name == "dispatch":
            # o ledger central mistura registros de dispatch e eventos ring-v1
            entries = [e for e in entries if e.get("task_name") and "schema" not in e]
        count = 0
        for e in entries:
            row = normalize_dispatch(name, e)
            if row:
                runs.append(row)
                count += 1
        declared.append({"source": name, "path": str(path), "exists": exists, "entries": count})
    runs.sort(key=lambda r: r.get("ts") or "", reverse=True)
    return {"sources": declared, "runs": runs}


def normalize_dispatch(source: str, e: dict) -> dict | None:
    if source == "dispatch":
        model = e.get("model") or {}
        ok = e.get("oracle_status") == "passou" or (
            e.get("oracle_status") == "sem-oraculo" and e.get("runner_exit") == "0")
        return {
            "source": source, "task": e.get("task_name"),
            "model": model.get("id") or "?",
            "ts": e.get("started_at"), "duration_s": e.get("duration_seconds"),
            "ok": bool(ok), "detail": f"oracle={e.get('oracle_status')} runner={e.get('runner_exit')}",
            "log_file": e.get("log_file"),
        }
    if source == "escalate":
        return {
            "source": source, "task": e.get("task_name"),
            "model": e.get("model") or e.get("tier") or "?",
            "ts": e.get("ts"), "duration_s": e.get("duration_s"),
            "ok": e.get("result") == "success",
            "detail": f"tier={e.get('tier')} attempt={e.get('attempt')}",
        }
    if source == "batch":
        total, okn = e.get("total"), e.get("ok")
        return {
            "source": source, "task": e.get("run_id"),
            "model": f"{len(e.get('items') or [])} itens",
            "ts": e.get("ts"), "duration_s": e.get("total_s"),
            "ok": bool(total is not None and okn == total),
            "detail": f"{okn}/{total} ok",
            "items": [
                {"task": i.get("task"), "ok": i.get("result") == "success",
                 "duration_s": i.get("duration_s")}
                for i in (e.get("items") or [])
            ],
        }
    return None


def active_runs_from_events(logs_dir: Path, max_age_h: float = 12.0) -> list[dict]:
    """run_started sem run_finished no events.jsonl do workdir = vivo agora.

    Staleness: run sem run_finished mais velho que max_age_h não é "vivo",
    é run que morreu sem fechar o evento — mostrar como vivo seria sinal
    falso (família das regras 24/42: sensor mentindo sobre vida).
    """
    started: dict[str, dict] = {}
    for e in read_jsonl(logs_dir / "events.jsonl"):
        rid = e.get("run_id")
        if not rid:
            continue
        if e.get("type") == "run_started":
            started[rid] = {
                "run_id": rid, "task": e.get("task"), "mode": e.get("mode"),
                "model": e.get("model_id"), "started": e.get("ts"),
            }
        elif e.get("type") == "run_finished":
            started.pop(rid, None)
    out = []
    import datetime
    now = datetime.datetime.now(datetime.timezone.utc)
    for r in started.values():
        ts = r.get("started") or ""
        try:
            age_h = (now - datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))).total_seconds() / 3600
        except ValueError:
            age_h = None
        if age_h is not None and age_h > max_age_h:
            continue
        out.append(r)
    return out


def incident_audit(root: Path) -> dict:
    """`incident.sh audit` com cache (read-only; ~1s)."""
    global _AUDIT_CACHE
    now = time.time()
    if _AUDIT_CACHE is not None and now - _AUDIT_CACHE[0] < _AUDIT_CACHE_TTL:
        return _AUDIT_CACHE[1]
    payload: dict
    try:
        proc = subprocess.run(
            ["bash", str(INCIDENT_SCRIPT), "audit"],
            cwd=str(root), timeout=30, capture_output=True, text=True,
        )
        lines = [ln for ln in (proc.stdout + proc.stderr).splitlines() if ln.strip()]
        debts = [ln for ln in lines if "DÍVIDA" in ln or "DIVIDA" in ln]
        payload = {"ok": True, "exit": proc.returncode, "debts": debts, "lines": lines}
    except Exception as exc:  # sensor ausente nunca derruba a home (fail-open)
        payload = {"ok": False, "error": str(exc)}
    _AUDIT_CACHE = (now, payload)
    return payload


def summarize_central_tail(root: Path, n: int = 12) -> list[dict]:
    out = []
    for e in read_jsonl(root / "ledger" / "ledger.jsonl")[-n:]:
        if e.get("schema") == "ring-v1":
            label = f"{e.get('event')} {e.get('ring')} · run {e.get('run')}"
            kind = "ring"
            ok = e.get("event") in ("close", "owner_score", "checkpoint_commit", "open")
            ts = e.get("ts")
        elif e.get("task_name"):
            label = f"dispatch {e.get('task_name')} · {(e.get('model') or {}).get('id', '?')}"
            kind = "dispatch"
            ok = e.get("oracle_status") in ("passou", "sem-oraculo")
            ts = e.get("started_at")
        else:
            label = ", ".join(sorted(e.keys()))[:80]
            kind, ok, ts = "outro", True, e.get("ts")
        out.append({"ts": ts, "kind": kind, "label": label, "ok": bool(ok)})
    out.reverse()
    return out


class OracfitPanelHandler(SimpleHTTPRequestHandler):
    panel_dir: Path
    logs_dir: Path
    runtime_config: bytes
    oracfit_root: Path
    ring_target: Path | None = None
    auth_token: str | None = None
    dispatch_enabled: bool = False

    # ── auth: cookie ou Bearer, comparação tempo-constante ───────────────────

    def _authorized(self) -> bool:
        if self.auth_token is None:
            return True
        supplied = None
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer "):
            supplied = header[7:].strip()
        else:
            for part in self.headers.get("Cookie", "").split(";"):
                key, _, val = part.strip().partition("=")
                if key == AUTH_COOKIE:
                    supplied = val
                    break
        if not supplied:
            return False
        return secrets.compare_digest(supplied, self.auth_token)

    def _deny_json(self) -> None:
        self._json_response(401, {
            "ok": False,
            "error": "não autenticado — POST /login {\"token\": …} (cookie) ou header Authorization: Bearer <token>",
        })

    def _read_json_body(self) -> dict | None:
        """Lê e valida o corpo JSON do POST; responde o erro e devolve None."""
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > 65536:
            self.send_error(400, "bad content-length")
            return None
        raw = self.rfile.read(length)
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            self.send_error(400, "invalid json")
            return None
        if not isinstance(body, dict):
            self.send_error(400, "invalid json")
            return None
        return body

    def _login_page(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(LOGIN_PAGE)))
        self.end_headers()
        self.wfile.write(LOGIN_PAGE)

    def _handle_login(self, body: dict) -> None:
        token = str(body.get("token", ""))
        if not token or not self.auth_token \
                or not secrets.compare_digest(token, self.auth_token):
            self._deny_json()
            return
        cookie = (f"{AUTH_COOKIE}={self.auth_token}; Path=/; HttpOnly; "
                  f"SameSite=Strict; Max-Age={AUTH_COOKIE_MAX_AGE}")
        # atrás do cloudflared o navegador só guarda Secure em https — sem
        # isso o login nunca "pega" no túnel
        if (self.headers.get("X-Forwarded-Proto") or "").lower() == "https":
            cookie += "; Secure"
        out = json.dumps({"ok": True}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Set-Cookie", cookie)
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def _json_response(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _gauntlet_dir(self, run_id: str) -> Path | None:
        if not RUN_ID_RE.match(run_id):
            return None
        gauntlet = (self.logs_dir / "inbox" / f"{run_id}.run.gauntlet").resolve()
        try:
            gauntlet.relative_to(self.logs_dir.resolve())
        except ValueError:
            return None
        return gauntlet

    def _safe_log_file(self, run_id: str, name: str) -> Path | None:
        if not LOG_FILE_RE.match(name):
            return None
        gauntlet = self._gauntlet_dir(run_id)
        if gauntlet is None:
            return None
        target = (gauntlet / name).resolve()
        try:
            target.relative_to(gauntlet)
        except ValueError:
            return None
        return target

    def _handle_runfiles(self, qs: dict[str, list[str]]) -> None:
        run_id = (qs.get("run_id") or [""])[0]
        gauntlet = self._gauntlet_dir(run_id)
        if gauntlet is None:
            self.send_error(400, "invalid run_id")
            return
        if not gauntlet.is_dir():
            self.send_error(404, "run dir not found")
            return
        files = []
        for entry in sorted(gauntlet.iterdir()):
            if not entry.is_file():
                continue
            st = entry.stat()
            files.append({"name": entry.name, "size": st.st_size, "mtime": st.st_mtime})
        self._json_response(200, {"ok": True, "files": files})

    def _handle_tail(self, qs: dict[str, list[str]]) -> None:
        run_id = (qs.get("run_id") or [""])[0]
        name = (qs.get("file") or [""])[0]
        raw_bytes = (qs.get("bytes") or ["16384"])[0]
        try:
            nbytes = int(raw_bytes)
        except ValueError:
            self.send_error(400, "invalid bytes")
            return
        nbytes = max(1, min(nbytes, 65536))

        target = self._safe_log_file(run_id, name)
        if target is None:
            self.send_error(400, "invalid run_id or file")
            return
        if not target.is_file():
            self.send_error(404, "log not found")
            return

        size = target.stat().st_size
        start = max(0, size - nbytes)
        with target.open("rb") as f:
            f.seek(start)
            chunk = f.read()
        text = chunk.decode("utf-8", errors="replace")
        scan_len = min(size, 524288)
        with target.open("rb") as f:
            f.seek(max(0, size - scan_len))
            scan_data = f.read(scan_len)
        task_matches = list(re.finditer(rb"Executing task:\s+(\S+)", scan_data))
        current_task = (
            task_matches[-1].group(1).decode("utf-8", errors="replace") if task_matches else None
        )
        payload: dict = {"ok": True, "size": size, "tail": text}
        if current_task:
            payload["current_task"] = current_task
        self._json_response(200, payload)

    def _handle_usage(self) -> None:
        global _USAGE_CACHE
        now = time.time()
        if _USAGE_CACHE is not None and now - _USAGE_CACHE[0] < _USAGE_CACHE_TTL:
            self._json_response(200, _USAGE_CACHE[1])
            return
        try:
            status = subprocess.run(
                [sys.executable, str(USAGE_HUB), "status", "--json"],
                timeout=20, capture_output=True, text=True,
            )
            data = json.loads(status.stdout)
            providers = data.get("providers", [])
            for prov in providers:
                rec = subprocess.run(
                    [sys.executable, str(USAGE_HUB), "recommend",
                     "--provider", prov["provider"], "--json"],
                    timeout=20, capture_output=True, text=True,
                )
                rec_data = json.loads(rec.stdout)
                prov["action"] = rec_data.get("action")
                prov["message"] = rec_data.get("message")
            payload: dict = {
                "ok": True,
                "ts": now,
                "warn": data.get("warn"),
                "providers": providers,
            }
            _USAGE_CACHE = (now, payload)
        except Exception as exc:
            payload = {"ok": False, "error": str(exc)}
        self._json_response(200, payload)

    # ── GUI: endpoints read-only ─────────────────────────────────────────────

    def _resolve_target(self, project: str | None) -> Path | None:
        """Alvo de /api/gui/todo: --ring-target direto, ou irmão wt-<projeto>.

        Frota = worktrees wt-<projeto> irmãs do --ring-target. Path nunca é
        aceito (só nome simples) — traversal morre aqui. Sem --ring-target
        não há frota: None (o chamador declara a ausência, regra 38).
        """
        if self.ring_target is None:
            return None
        if not project:
            return self.ring_target
        if "/" in project or project.startswith(".") or ".." in project:
            return None
        base = self.ring_target.parent
        for cand in (base / f"wt-{project}", base / project):
            if cand.is_dir():
                return cand
        if self.ring_target.name in (project, f"wt-{project}"):
            return self.ring_target
        return None

    def _handle_rings(self) -> None:
        if self.ring_target is None:
            self._json_response(404, {"ok": False, "error": "GUI subiu sem --ring-target (rode: oracfit hitl <target-dir>)"})
            return
        try:
            data = extract_target_rings(self.ring_target)
        except FileNotFoundError as exc:
            self._json_response(404, {"ok": False, "error": str(exc)})
            return
        except Exception as exc:
            self._json_response(500, {"ok": False, "error": str(exc)})
            return
        data["ok"] = True
        self._json_response(200, data)

    def _handle_gui_home(self) -> None:
        root = self.oracfit_root
        try:
            du = shutil.disk_usage(str(root))
            free_gb = round(du.free / 1e9, 1)
        except OSError:
            free_gb = None
        # regra 51: <25GB atenção, <10GB pausa trabalho em massa
        disk_level = "ok"
        if free_gb is not None and free_gb < 10:
            disk_level = "critico"
        elif free_gb is not None and free_gb < 25:
            disk_level = "atencao"
        open_rings = []
        for g in central_ring_groups(root):
            for r in g["rings"]:
                if r["status"] == "aberto":
                    open_rings.append({"run": g["run"], "mode": g["mode"], **r})
        to_score = None
        if self.ring_target is not None:
            try:
                to_score = extract_target_rings(self.ring_target)["to_score"]
            except Exception:
                to_score = None
        self._json_response(200, {
            "ok": True,
            "active_runs": active_runs_from_events(self.logs_dir),
            "open_rings": open_rings,
            "to_score": to_score,
            "ring_target": str(self.ring_target) if self.ring_target else None,
            "central_tail": summarize_central_tail(root),
            "disk": {"free_gb": free_gb, "level": disk_level},
            "audit": incident_audit(root),
        })

    def _handle_gui_dispatches(self) -> None:
        self._json_response(200, {"ok": True, **dispatch_sources(self.oracfit_root, self.logs_dir)})

    def _handle_gui_rings(self) -> None:
        payload: dict = {"ok": True, "groups": central_ring_groups(self.oracfit_root),
                         "central_ledger": str(self.oracfit_root / "ledger" / "ledger.jsonl")}
        if self.ring_target is not None:
            try:
                payload["target"] = extract_target_rings(self.ring_target)
            except Exception:
                payload["target"] = None
        self._json_response(200, payload)

    def _handle_gui_incidents(self) -> None:
        inc_dir = self.oracfit_root / "incidents"
        items = []
        if inc_dir.is_dir():
            for f in inc_dir.glob("*.md"):
                if f.name == "README.md":
                    continue
                title = f.stem
                try:
                    for line in f.read_text(encoding="utf-8", errors="replace").splitlines()[:10]:
                        if line.startswith("# "):
                            title = line[2:].strip()
                            break
                except OSError:
                    pass
                items.append({"name": f.stem, "title": title, "path": str(f),
                              "mtime": f.stat().st_mtime})
        items.sort(key=lambda i: i["mtime"], reverse=True)
        self._json_response(200, {"ok": True, "incidents": items[:40],
                                  "total": len(items), "audit": incident_audit(self.oracfit_root)})

    def _handle_gui_registry(self) -> None:
        root = self.oracfit_root
        models = []
        reg_file = root / "model-registry.json"
        if reg_file.is_file():
            try:
                for m in json.loads(reg_file.read_text(encoding="utf-8")).get("models", []):
                    status = str(m.get("id_status") or "")
                    models.append({
                        "id": m.get("id"), "provider": m.get("provider"),
                        "tier": m.get("tier"), "accuracy": m.get("accuracy"),
                        "latency_ms": m.get("latency_ms"),
                        "best_for": m.get("best_for") or [],
                        "verified_at": m.get("verified_at"),
                        "retired": "APOSENTADO" in status.upper(),
                    })
            except (OSError, json.JSONDecodeError):
                pass
        limits = {}
        lim_file = root / "core" / "usage-limits.json"
        if lim_file.is_file():
            try:
                raw = json.loads(lim_file.read_text(encoding="utf-8"))
                for pid, p in (raw.get("providers") or {}).items():
                    limits[pid] = {"plan": p.get("plan"), "windows": p.get("windows")}
            except (OSError, json.JSONDecodeError):
                pass
        self._json_response(200, {"ok": True, "models": models, "limits": limits,
                                  "registry_exists": reg_file.is_file()})

    # ── GUI: writes (score do HITL · dispatch com --enable-dispatch) ─────────

    def _gui_workdir(self) -> Path | None:
        """Workdir = pai do logs-dir, SÓ se o layout for <workdir>/.dispatch/logs."""
        if self.logs_dir.name == "logs" and self.logs_dir.parent.name == ".dispatch":
            return self.logs_dir.parent.parent
        return None

    def _handle_gui_modes(self) -> None:
        """Modes e adapters reais para o formulário — o que `oracfit run`
        resolveria: workdir overlay primeiro, root depois."""
        modes: list[str] = []
        workdir = self._gui_workdir()
        for base_dir in filter(None, (workdir, self.oracfit_root)):
            modes_dir = base_dir / "core" / "modes"
            if not modes_dir.is_dir():
                continue
            for f in sorted(modes_dir.glob("*.yaml")):
                if f.stem not in modes:
                    modes.append(f.stem)
        adapters = sorted(
            d.name for d in (self.oracfit_root / "adapters").glob("*")
            if (d / "env.sh").is_file()
        ) if (self.oracfit_root / "adapters").is_dir() else []
        self._json_response(200, {
            "ok": True, "modes": modes, "adapters": adapters,
            # regra 38: estado declarado, não omitido
            "dispatch_enabled": self.dispatch_enabled,
            "auth": self.auth_token is not None,
        })

    def _handle_dispatch(self, body: dict) -> None:
        if not self.dispatch_enabled:
            self._json_response(404, {"ok": False,
                                      "error": "dispatch pela GUI desligado — suba o servidor com --enable-dispatch"})
            return
        workdir = self._gui_workdir()
        if workdir is None:
            self._json_response(500, {"ok": False,
                                      "error": f"logs-dir {self.logs_dir} não segue <workdir>/.dispatch/logs — dispatch não sabe onde rodar"})
            return

        mode = str(body.get("mode", ""))
        spec = str(body.get("spec", ""))
        task = str(body.get("task", ""))
        adapter = str(body.get("adapter", "stub"))
        if not MODE_ID_RE.match(mode):
            self._json_response(400, {"ok": False, "error": f"mode={mode!r} inválido (esperado id tipo 'normal')"})
            return
        if not TASK_NAME_RE.match(task):
            self._json_response(400, {"ok": False, "error": f"task={task!r} inválida ([a-z0-9._-], começa com alfanumérico)"})
            return
        if not ADAPTER_RE.match(adapter) or not (self.oracfit_root / "adapters" / adapter / "env.sh").is_file():
            self._json_response(400, {"ok": False, "error": f"adapter={adapter!r} sem adapters/{adapter}/env.sh"})
            return
        # mode TEM que existir onde `oracfit run` resolveria (overlay + root)
        mode_yaml = (workdir / "core" / "modes" / f"{mode}.yaml")
        if not mode_yaml.is_file():
            mode_yaml = self.oracfit_root / "core" / "modes" / f"{mode}.yaml"
        if not mode_yaml.is_file():
            self._json_response(400, {"ok": False, "error": f"mode {mode!r} não existe (core/modes/{mode}.yaml não achado)"})
            return
        # spec resolve DENTRO do workdir e é .md — nada de /etc, nada de fora
        cand = Path(spec) if spec.startswith("/") else workdir / spec
        try:
            resolved = cand.resolve()
            resolved.relative_to(workdir.resolve())
        except (ValueError, OSError):
            self._json_response(400, {"ok": False, "error": f"spec {spec!r} fora do workdir {workdir}"})
            return
        if resolved.suffix != ".md" or not resolved.is_file():
            self._json_response(400, {"ok": False, "error": f"spec {spec!r} não é um .md existente dentro de {workdir}"})
            return

        # mesmo mecanismo do terminal: daemon start (double-fork+setsid,
        # imune à morte da GUI/sessão) + launcher que sourceia o adapter
        ts = time.strftime("%Y%m%d-%H%M%S")
        log = self.logs_dir / f"gui-dispatch-{ts}-{task}.log"
        cmd = [
            "bash", str(self.oracfit_root / "bin" / "oracfit-daemon.sh"), "start", str(log),
            "bash", str(self.oracfit_root / "bin" / "oracfit-dispatch-gui.sh"),
            adapter, mode, str(resolved), task,
        ]
        try:
            proc = subprocess.run(
                cmd, cwd=str(workdir), timeout=60, capture_output=True, text=True,
                env={**os.environ, "ORACFIT_WORKDIR": str(workdir)},
            )
        except subprocess.TimeoutExpired:
            self._json_response(500, {"ok": False, "error": "daemon start estourou 60s"})
            return
        if proc.returncode != 0:
            detail = " · ".join((proc.stderr.strip() or proc.stdout.strip()).splitlines()[-3:])
            self._json_response(500, {"ok": False, "exit": proc.returncode,
                                      "error": detail or f"daemon start saiu {proc.returncode} sem mensagem"})
            return
        self._json_response(200, {
            "ok": True, "task": task, "mode": mode, "adapter": adapter,
            "spec": str(resolved), "log": str(log), "pid_file": f"{log}.pid",
            "watch": "index.html",
            "hint": "acompanhe em Run ao vivo; o run entra no events.jsonl em segundos",
        })

    def _handle_gui_corte(self) -> None:
        # /api/gui/corte — payload do bin/corte-review.py --json (read-only:
        # o apply é do publish-cut no CLI, AD-14). Corte vem do env
        # ORACFIT_CORTE_DIR (default do próprio corte-review). Teto: regra 12.
        cmd = ["python3", str(self.oracfit_root / "bin" / "corte-review.py"), "--json"]
        try:
            proc = subprocess.run(
                cmd, cwd=str(self.oracfit_root), timeout=120,
                capture_output=True, text=True,
            )
        except subprocess.TimeoutExpired:
            self._json_response(500, {"ok": False, "error": "corte-review estourou 120s"})
            return
        if proc.returncode != 0:
            detail = " ".join((proc.stderr.strip() or proc.stdout.strip()).splitlines()[-1:])
            self._json_response(500, {"ok": False, "exit": proc.returncode,
                                      "error": detail or f"corte-review saiu {proc.returncode}"})
            return
        try:
            payload = json.loads(proc.stdout)
        except json.JSONDecodeError:
            self._json_response(500, {"ok": False, "error": "corte-review não devolveu JSON"})
            return
        self._json_response(200, payload)

    def _handle_ring_score(self, body: dict) -> None:
        if self.ring_target is None:
            self._json_response(404, {"ok": False, "error": "GUI subiu sem --ring-target"})
            return
        ring = str(body.get("ring", ""))
        real_raw = body.get("real")
        if not RING_ID_RE.match(ring):
            self._json_response(400, {"ok": False, "error": "ring inválido (esperado id tipo RING-1)"})
            return
        # N inteiro 0-10 — bool é int em Python, e float/str fora do padrão recusam
        if isinstance(real_raw, bool) or not REAL_SCORE_RE.match(str(real_raw)):
            self._json_response(400, {"ok": False, "error": f"real={real_raw!r} — nota é inteiro de 0 a 10"})
            return
        real = int(str(real_raw))
        try:
            data = extract_target_rings(self.ring_target)
        except FileNotFoundError as exc:
            self._json_response(404, {"ok": False, "error": str(exc)})
            return
        match = next((r for r in data["rings"] if r["ring"] == ring), None)
        if match is None:
            self._json_response(404, {"ok": False, "error": f"{ring} não tem close no run {data['run']}"})
            return
        if match.get("scored"):
            self._json_response(409, {"ok": False, "error": f"{ring} já tem nota real ({match.get('real')})"})
            return
        try:
            proc = subprocess.run(
                ["bash", str(RING_SCRIPT), "score", ring,
                 "--real", str(real), "--target", str(self.ring_target)],
                timeout=60, capture_output=True, text=True,
            )
        except subprocess.TimeoutExpired:
            self._json_response(500, {"ok": False, "error": "score estourou 60s"})
            return
        if proc.returncode != 0:
            # regra 8 da skill: causa + correção, nunca "exit N" seco
            detail = " · ".join(
                (proc.stderr.strip() or proc.stdout.strip()).splitlines()[-3:])
            if not detail:
                detail = (f"o runner saiu com exit {proc.returncode} sem mensagem — "
                          f"provável bug do runner; para ver de perto, rode no terminal: "
                          f"oracfit ring score {ring} --real {real} --target {self.ring_target}")
            self._json_response(500, {"ok": False, "exit": proc.returncode, "error": detail})
            return
        # reler o ledger: o delta que volta é o que foi GRAVADO, não um recálculo
        data = extract_target_rings(self.ring_target)
        scored = next((r for r in data["rings"] if r["ring"] == ring and r.get("scored")), None)
        if scored is None:
            self._json_response(500, {"ok": False, "error": "score rodou mas owner_score não apareceu no ledger"})
            return
        payload = {"ok": True, "ring": ring, "real": scored.get("real"),
                   "pred": scored.get("pred"), "delta": scored.get("delta"),
                   "to_score": data["to_score"]}
        # nota dada — o veredito do critic pode ser revelado junto com o delta
        critic = critic_verdict(self.ring_target, ring)
        if critic:
            payload["critic"] = critic
        self._json_response(200, payload)

    def _handle_ring_file(self, rel: str) -> None:
        """Arquivo estático RESTRITO ao ring/ do --ring-target (evidências da
        calibração: imagem de gate visual, render de terminal, nota). Traversal
        bloqueado por os.path.realpath dentro da raiz + whitelist de extensão."""
        if self.ring_target is None:
            self.send_error(404, "GUI subiu sem --ring-target")
            return
        rel = unquote(rel)
        root = os.path.realpath(str(self.ring_target / "ring"))
        full = os.path.realpath(os.path.join(root, rel))
        if not full.startswith(root + os.sep):
            self.send_error(403, "fora do ring/ do alvo")
            return
        ctype = RING_FILE_TYPES.get(os.path.splitext(full)[1].lower())
        if ctype is None:
            self.send_error(403, "tipo de arquivo não permitido")
            return
        if not os.path.isfile(full):
            self.send_error(404, "arquivo não existe")
            return
        try:
            with open(full, "rb") as f:
                data = f.read()
        except OSError:
            self.send_error(500, "falha ao ler o arquivo")
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if self.auth_token is not None:
            if parsed.path in ("/login", "/login/"):
                if self._authorized():  # já logado — direto pra casa
                    self.send_response(303)
                    self.send_header("Location", "home.html")
                    self.end_headers()
                    return
                self._login_page()
                return
            if not self._authorized():
                if parsed.path.startswith("/api/"):
                    self._deny_json()
                else:
                    self.send_response(303)
                    self.send_header("Location", "/login")
                    self.end_headers()
                return
        if parsed.path.startswith("/ring-file/"):
            self._handle_ring_file(parsed.path[len("/ring-file/"):])
            return
        if parsed.path in ("/runtime-config.json", "/runtime-config.json/"):
            body = self.runtime_config
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if parsed.path == "/api/runfiles":
            self._handle_runfiles(parse_qs(parsed.query))
            return
        if parsed.path == "/api/tail":
            self._handle_tail(parse_qs(parsed.query))
            return
        if parsed.path == "/api/usage":
            self._handle_usage()
            return
        if parsed.path == "/api/rings":
            self._handle_rings()
            return
        if parsed.path == "/api/gui/home":
            self._handle_gui_home()
            return
        if parsed.path == "/api/gui/dispatches":
            self._handle_gui_dispatches()
            return
        if parsed.path == "/api/gui/rings":
            self._handle_gui_rings()
            return
        if parsed.path == "/api/gui/incidents":
            self._handle_gui_incidents()
            return
        if parsed.path == "/api/gui/registry":
            self._handle_gui_registry()
            return
        if parsed.path == "/api/gui/corte":
            self._handle_gui_corte()
            return
        if parsed.path == "/api/gui/modes":
            self._handle_gui_modes()
            return
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/login" and self.auth_token is not None:
            body = self._read_json_body()
            if body is None:
                return
            self._handle_login(body)
            return
        if self.auth_token is not None and not self._authorized():
            self._deny_json()
            return
        if parsed.path not in ("/api/message", "/api/ring-score", "/api/dispatch"):
            self.send_error(404, "not found")
            return
        body = self._read_json_body()
        if body is None:
            return

        if parsed.path == "/api/ring-score":
            self._handle_ring_score(body)
            return
        if parsed.path == "/api/dispatch":
            self._handle_dispatch(body)
            return

        run_id = str(body.get("run_id", ""))
        text = str(body.get("text", "")).strip()
        interrupt = bool(body.get("interrupt", False))

        if not RUN_ID_RE.match(run_id):
            self.send_error(400, "invalid run_id")
            return
        if not text:
            self.send_error(400, "empty text")
            return

        inbox_dir = self.logs_dir / "inbox"
        inbox_dir.mkdir(parents=True, exist_ok=True)
        inbox_file = inbox_dir / f"{run_id}.jsonl"
        entry = {"ts": time.time(), "text": text, "interrupt": interrupt}
        with inbox_file.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")

        if interrupt:
            interrupt_file = inbox_dir / f"{run_id}.interrupt"
            interrupt_file.touch()

        body_out = json.dumps({"ok": True, "interrupt": interrupt}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body_out)))
        self.end_headers()
        self.wfile.write(body_out)

    def translate_path(self, path: str) -> str:  # type: ignore[override]
        parsed = urlparse(path)
        clean = parsed.path
        if clean.startswith("/logs"):
            rel = clean[len("/logs") :].lstrip("/")
            if not rel:
                # directory listing of logs — allow empty dir index via missing file
                return str(self.logs_dir)
            target = (self.logs_dir / rel).resolve()
            try:
                target.relative_to(self.logs_dir.resolve())
            except ValueError:
                return str(self.logs_dir / "__denied__")
            return str(target)
        rel = clean.lstrip("/") or "index.html"
        target = (self.panel_dir / rel).resolve()
        try:
            target.relative_to(self.panel_dir.resolve())
        except ValueError:
            return str(self.panel_dir / "__denied__")
        return str(target)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[oracfit-panel] " + (fmt % args) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--panel-dir", required=True)
    ap.add_argument("--logs-dir", required=True)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--oracfit-root", default=str(BIN_DIR.parent),
                    help="raiz da instalação oracfit (ledger central, incidents, registry)")
    ap.add_argument("--ring-target", default=None,
                    help="alvo com ring/ para a página HITL de calibração")
    ap.add_argument("--auth-token", default=os.environ.get("ORACFIT_GUI_TOKEN"),
                    help="token de acesso (também via env ORACFIT_GUI_TOKEN); obrigatório se --bind fora do loopback")
    ap.add_argument("--enable-dispatch", action="store_true",
                    help="liga POST /api/dispatch (formulário de despacho da GUI)")
    args = ap.parse_args()

    token = args.auth_token or None
    if token is not None and len(token) < MIN_TOKEN_LEN:
        print(f"ERROR: --auth-token precisa de >= {MIN_TOKEN_LEN} caracteres", file=sys.stderr)
        return 3
    guard_err = enforce_bind_guard(args.bind, token)
    if guard_err:
        print(guard_err, file=sys.stderr)
        return 3

    panel = Path(args.panel_dir).resolve()
    logs = Path(args.logs_dir).resolve()
    if not panel.is_dir():
        print(f"ERROR: panel dir missing: {panel}", file=sys.stderr)
        return 3
    ring_target: Path | None = None
    if args.ring_target:
        ring_target = Path(args.ring_target).resolve()
        if not (ring_target / "ring" / "state.json").is_file():
            print(f"ERROR: {ring_target}/ring/state.json não existe — alvo sem 'oracfit ring init'",
                  file=sys.stderr)
            return 3

    logs.mkdir(parents=True, exist_ok=True)

    meta = {
        "product": "Oracfit",
        "credit": "Oracfit — Carlos Felipe",
        "logs_url": "/logs/events.jsonl",
        "logs_dir": str(logs),
        "observe_only": False,
        "hitl_v1": True,
        "message_endpoint": "/api/message",
        "gui": True,
        "ring_target": str(ring_target) if ring_target else None,
        "auth": token is not None,
        "dispatch_enabled": bool(args.enable_dispatch),
    }
    runtime = (json.dumps(meta, indent=2) + "\n").encode("utf-8")

    OracfitPanelHandler.panel_dir = panel
    OracfitPanelHandler.logs_dir = logs
    OracfitPanelHandler.runtime_config = runtime
    OracfitPanelHandler.directory = str(panel)
    OracfitPanelHandler.oracfit_root = Path(args.oracfit_root).resolve()
    OracfitPanelHandler.ring_target = ring_target
    OracfitPanelHandler.auth_token = token
    OracfitPanelHandler.dispatch_enabled = bool(args.enable_dispatch)

    httpd = ThreadingHTTPServer((args.bind, args.port), OracfitPanelHandler)
    real_port = httpd.server_address[1]  # --port 0 = porta efêmera real aqui
    print(f"Oracfit panel http://{args.bind}:{real_port}/", flush=True)
    print(f"logs -> {logs} via /logs/")
    if token is not None:
        print("auth: token ATIVO (login em /login · Bearer também aceito)")
    if args.enable_dispatch:
        print("dispatch: ATIVO (POST /api/dispatch habilitado)")
    print("Oracfit — Carlos Felipe")
    print("observe-only · Ctrl+C to stop")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
