#!/usr/bin/env python3
"""oracfit-todo-server.py — panel server + visão TODO/backlog de anéis.

Extensão do bin/oracfit-panel-server.py por import+subclass — o arquivo
base está com trabalho em andamento de outro fluxo nesta árvore, então a
extensão NÃO toca nele: importa o módulo em runtime e herda toda a
superfície (páginas, /logs, /api/*, score do HITL). O que muda:

  /api/gui/todo  -> checklist do run de UM alvo (read-only):
    itens do docs/BACKLOG.md do alvo (parse tolerante: tabela markdown,
    checkboxes e headings que citam id de anel) casados com os anéis do
    ring/ledger.jsonl (ring-v1) do run atual. Estado por item:
      feito      anel com close no ledger
      andamento  anel aberto agora (com contagem de closes recusados)
      fila       item do backlog ainda sem anel  (vocabulário sem
                 vergonha do gui.js: nunca "pendente"/"atrasado")
      abortado   anel com abort
    Fonte ausente é DECLARADA no payload (regra 38): alvo sem ring init
    responde ok com ring_initialized=false; backlog ausente responde ok
    com backlog.exists=false — nunca 500, nunca some em silêncio.
    ?project= resolve na frota wt-* exatamente como /api/rings.
    ANTI-ÂNCORA: anel fechado sem nota real nunca carrega pred/delta.

  --ring-target sem ring/state.json aqui é AVISO, não erro: a visão TODO
    existe justamente para acompanhar um alvo desde antes do ring init.
    (O oracfit-gui.sh mantém a exigência dele para o HITL.)

Página: /todo.html. Quem me executa é o bin/oracfit-gui.sh (oracfit gui).
Acoplamento declarado: este main espelha o wiring do main do base
(atributos de classe do handler + runtime-config). Se o base ganhar
atributo novo obrigatório, replicar aqui.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BIN_DIR = Path(__file__).resolve().parent

_spec = importlib.util.spec_from_file_location(
    "oracfit_panel_server", BIN_DIR / "oracfit-panel-server.py")
if _spec is None or _spec.loader is None:
    print("ERROR: bin/oracfit-panel-server.py não encontrado ao lado deste script",
          file=sys.stderr)
    raise SystemExit(3)
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)

# id de anel dentro de texto livre do backlog: RING-1, G-2, PILAR-10…
RING_TOKEN_RE = re.compile(r"\b([A-Z][A-Z0-9]{0,15}-\d{1,5})\b")
CHECKBOX_RE = re.compile(r"^[-*]\s*\[([ xX])\]\s*(.+)$")
HEADING_RE = re.compile(r"^#{1,6}\s+(.+)$")

# headers de coluna reconhecidos (>=2 numa linha de tabela = linha é header)
_HEADERISH = {"anel", "ring", "item", "id", "tarefa", "escopo", "scope",
              "descrição", "descricao", "título", "titulo", "title",
              "estado", "status", "state", "artefatos", "artefato",
              "arquivos", "entregável", "entregavel"}
_ID_COLS = ("anel", "ring", "id", "item", "tarefa")
_TITLE_COLS = ("escopo", "descrição", "descricao", "título", "titulo",
               "title", "scope")
_STATE_COLS = ("estado", "status", "state")
_ARTIFACT_COLS = ("artefatos", "artefato", "arquivos", "entregável",
                  "entregavel")


def _ring_token(text: str) -> str:
    m = RING_TOKEN_RE.search(text or "")
    return m.group(1) if m else ""


def _norm_backlog_state(text: str) -> str:
    """Texto livre de estado do backlog → feito/andamento/'' (só HINT;
    quando existe anel no ledger, o ledger vence)."""
    t = (text or "").lower()
    if any(k in t for k in ("feito", "fechado", "done", "conclu", "entregue", "closed")):
        return "feito"
    if any(k in t for k in ("andamento", "aberto", "doing", "wip", "progress", "open")):
        return "andamento"
    return ""


def _col(cells: list[str], header: list[str] | None, names: tuple[str, ...],
         default_idx: int | None) -> str:
    if header:
        for i, h in enumerate(header):
            if h in names and i < len(cells):
                return cells[i]
    if default_idx is not None and default_idx < len(cells):
        return cells[default_idx]
    return ""


def parse_backlog(path: Path) -> list[dict]:
    """Itens do BACKLOG.md — parse tolerante, nunca lança.

    Reconhece tabela markdown (header por palavra-chave, separador |---|
    pulado), checkbox `- [ ]`/`- [x]` e heading que cite um id de anel.
    Linha que não casa nada é ignorada — backlog é texto de gente, não
    schema."""
    items: list[dict] = []
    if not path.is_file():
        return items
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return items
    header: list[str] | None = None
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("|") and line.count("|") >= 2:
            cells = [c.strip() for c in line.strip("|").split("|")]
            if all(set(c) <= set("-: ") for c in cells):
                continue  # separador |---|
            lowered = [c.lower() for c in cells]
            if sum(1 for c in lowered if c in _HEADERISH) >= 2:
                header = lowered
                continue
            id_raw = _col(cells, header, _ID_COLS, 0)
            title = _col(cells, header, _TITLE_COLS, 1 if len(cells) > 1 else 0)
            if not (id_raw or title):
                continue
            items.append({
                "id": _ring_token(id_raw) or id_raw,
                "title": title or id_raw,
                "artifacts": _col(cells, header, _ARTIFACT_COLS, None),
                "backlog_state": _norm_backlog_state(
                    _col(cells, header, _STATE_COLS, None)),
            })
            continue
        m = CHECKBOX_RE.match(line)
        if m:
            text = m.group(2).strip()
            items.append({
                "id": _ring_token(text),
                "title": text,
                "artifacts": "",
                "backlog_state": "feito" if m.group(1).lower() == "x" else "",
            })
            continue
        m = HEADING_RE.match(line)
        if m and _ring_token(m.group(1)):
            text = m.group(1).strip()
            items.append({"id": _ring_token(text), "title": text,
                          "artifacts": "", "backlog_state": ""})
    return items


def _find_backlog(target: Path) -> tuple[Path, bool]:
    """docs/BACKLOG.md primeiro; BACKLOG.md na raiz como fallback."""
    for rel in ("docs/BACKLOG.md", "BACKLOG.md"):
        p = target / rel
        if p.is_file():
            return p, True
    return target / "docs" / "BACKLOG.md", False


_RING_STATUS = {"fechado": "feito", "aberto": "andamento", "abortado": "abortado"}


def _ring_fields(r: dict) -> dict:
    """Campos MECÂNICOS do anel para um item do checklist.
    Anti-âncora: pred/delta só quando o anel já tem nota real."""
    out = {
        "status": _RING_STATUS.get(r.get("status") or "", "andamento"),
        "hypothesis": r.get("hypothesis") or "",
        "attempts": len(r.get("close_attempts") or []),
        "opened_at": r.get("opened_at"),
        "closed_at": r.get("closed_at"),
        "scored": bool(r.get("scored")),
    }
    if r.get("build_commit"):
        out["build_commit"] = r["build_commit"]
    if r.get("files_staged") is not None:
        out["files_staged"] = r.get("files_staged")
    oracle = r.get("oracle") or {}
    if oracle.get("runs"):
        out["oracle_runs"] = oracle.get("runs")
    if r.get("abort_reason"):
        out["abort_reason"] = r.get("abort_reason")
    if r.get("scored"):
        out["real"] = r.get("real")
    return out


def todo_payload(target: Path) -> dict:
    """Checklist do alvo: backlog é a ORDEM mestra do plano; o ledger é a
    verdade mecânica do que já virou anel. Nunca lança por arquivo ausente."""
    state: dict | None = None
    state_file = target / "ring" / "state.json"
    ring_initialized = state_file.is_file()
    if ring_initialized:
        try:
            loaded = json.loads(state_file.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                state = loaded
        except (OSError, json.JSONDecodeError):
            state = None
    run = (state or {}).get("run") or ""
    score_field = (state or {}).get("score_field") or "owner_score_pred"

    events = [e for e in base.read_jsonl(target / "ring" / "ledger.jsonl")
              if e.get("schema") == "ring-v1"]
    if run:
        events = [e for e in events if e.get("run") == run]
    rings = base.merge_ring_events(events, score_field)
    for r in rings:
        if not r.get("scored"):
            r.pop("pred", None)
            r.pop("delta", None)
    by_id = {(r.get("ring") or "").upper(): r for r in rings if r.get("ring")}

    backlog_path, backlog_exists = _find_backlog(target)
    backlog_items = parse_backlog(backlog_path) if backlog_exists else []

    items: list[dict] = []
    matched: set[str] = set()
    for b in backlog_items:
        bid = (b["id"] or "").upper()
        item = {"id": b["id"], "title": b["title"], "artifacts": b["artifacts"],
                "backlog_state": b["backlog_state"], "source": "backlog"}
        r = by_id.get(bid) if bid else None
        if r is not None:
            matched.add(bid)
            item.update(_ring_fields(r))
            item["source"] = "backlog+ledger"
        else:
            # sem anel no ledger: o hint do backlog vale; sem hint = na fila
            item["status"] = b["backlog_state"] or "fila"
        items.append(item)
    for r in rings:
        rid = (r.get("ring") or "").upper()
        if not rid or rid in matched:
            continue
        item = {"id": r.get("ring"), "title": r.get("hypothesis") or "",
                "artifacts": "", "backlog_state": "", "source": "ledger"}
        item.update(_ring_fields(r))
        items.append(item)

    counters = {
        "feito": sum(1 for i in items if i["status"] == "feito"),
        "andamento": sum(1 for i in items if i["status"] == "andamento"),
        "fila": sum(1 for i in items if i["status"] == "fila"),
        "abortado": sum(1 for i in items if i["status"] == "abortado"),
        "total": len(items),
        "closes_recusados": sum(len(r.get("close_attempts") or []) for r in rings),
    }
    state_out = None
    if state:
        state_out = {
            "current_ring": state.get("current_ring"),
            "ring_ceiling": state.get("ceiling"),
            "close_attempt_ceiling": state.get("close_attempt_ceiling"),
        }
    # worktrees da casa chamam-se wt-<projeto> — MESMA convenção inline do
    # central_ring_groups do panel-server (base.project_name NUNCA existiu:
    # referência fantasma desde b5f5462, vermelho invisível porque a suíte
    # não está na bateria — incidente 2026-08-22)
    name = target.name
    project = name[3:] if name.startswith("wt-") else name
    return {
        "ok": True,
        "target": str(target),
        "project": project,
        "run": run,
        "mode": (state or {}).get("mode"),
        "ring_initialized": ring_initialized,
        "state": state_out,
        "backlog": {"path": str(backlog_path), "exists": backlog_exists,
                    "items": len(backlog_items)},
        "items": items,
        "counters": counters,
    }


class OracfitTodoHandler(base.OracfitPanelHandler):
    def _handle_gui_todo(self, qs: dict[str, list[str]]) -> None:
        project = (qs.get("project") or [""])[0]
        target = self._resolve_target(project or None)
        if target is None:
            self._json_response(404, {
                "ok": False,
                "error": "GUI subiu sem --ring-target e sem frota wt-* (rode: oracfit gui --target <dir>)"
                         if not project else
                         "projeto fora da frota (só wt-* irmãos do --ring-target, sem path)",
            })
            return
        try:
            payload = todo_payload(target)
        except Exception as exc:  # arquivo quebrado nunca derruba a visão
            self._json_response(500, {"ok": False, "error": str(exc)})
            return
        self._json_response(200, payload)

    def do_GET(self) -> None:  # noqa: N802
        # AUTH antes de tudo: a rota /api/gui/todo roda ANTES do super() e
        # não pode furar o token (mesma regra do base, replicada aqui porque
        # a subclasse intercepta o caminho primeiro)
        if self.auth_token is not None and not self._authorized():
            parsed0 = urlparse(self.path)
            if parsed0.path in ("/login", "/login/"):
                super().do_GET()
                return
            if parsed0.path.startswith("/api/"):
                self._deny_json()
            else:
                self.send_response(303)
                self.send_header("Location", "/login")
                self.end_headers()
            return
        parsed = urlparse(self.path)
        if parsed.path == "/api/gui/todo":
            self._handle_gui_todo(parse_qs(parsed.query))
            return
        super().do_GET()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--panel-dir", required=True)
    ap.add_argument("--logs-dir", required=True)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--oracfit-root", default=str(BIN_DIR.parent),
                    help="raiz da instalação oracfit (ledger central, incidents, registry)")
    ap.add_argument("--ring-target", default=None,
                    help="alvo acompanhado (ring/ e docs/BACKLOG.md); sem ring init = aviso")
    ap.add_argument("--auth-token", default=os.environ.get("ORACFIT_GUI_TOKEN"),
                    help="token de acesso (idem base: obrigatório fora do loopback)")
    ap.add_argument("--enable-dispatch", action="store_true",
                    help="liga POST /api/dispatch (formulário de despacho)")
    args = ap.parse_args()

    token = args.auth_token or None
    if token is not None and len(token) < base.MIN_TOKEN_LEN:
        print(f"ERROR: --auth-token precisa de >= {base.MIN_TOKEN_LEN} caracteres",
              file=sys.stderr)
        return 3
    guard_err = base.enforce_bind_guard(args.bind, token)
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
            # diferente do base: TODO acompanha alvo desde ANTES do ring init
            print(f"WARN: {ring_target}/ring/state.json não existe ainda — "
                  "TODO mostra só o backlog; HITL indisponível até o ring init",
                  file=sys.stderr)

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
        "todo": True,
        "ring_target": str(ring_target) if ring_target else None,
        "auth": token is not None,
        "dispatch_enabled": bool(args.enable_dispatch),
    }
    runtime = (json.dumps(meta, indent=2) + "\n").encode("utf-8")

    OracfitTodoHandler.panel_dir = panel
    OracfitTodoHandler.logs_dir = logs
    OracfitTodoHandler.runtime_config = runtime
    OracfitTodoHandler.directory = str(panel)
    OracfitTodoHandler.oracfit_root = Path(args.oracfit_root).resolve()
    OracfitTodoHandler.ring_target = ring_target
    OracfitTodoHandler.auth_token = token
    OracfitTodoHandler.dispatch_enabled = bool(args.enable_dispatch)

    httpd = ThreadingHTTPServer((args.bind, args.port), OracfitTodoHandler)
    real_port = httpd.server_address[1]  # --port 0 = porta efêmera real aqui
    print(f"Oracfit panel http://{args.bind}:{real_port}/", flush=True)
    print(f"logs -> {logs} via /logs/")
    if token is not None:
        print("auth: token ATIVO (login em /login · Bearer também aceito)")
    if args.enable_dispatch:
        print("dispatch: ATIVO (POST /api/dispatch habilitado)")
    print("TODO/backlog -> /todo.html · /api/gui/todo")
    print("Oracfit — Carlos Felipe")
    print("observe-only · Ctrl+C to stop")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
