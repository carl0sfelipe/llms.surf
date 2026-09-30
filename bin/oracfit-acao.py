#!/usr/bin/env python3
"""oracfit-acao.py — pedidos de agente ao dono (arquivo append-only).

Uso (via `oracfit acao`):
  add <id> --title T --plain P [--why W] [--command C] [--href H]
           [--step "texto[|href=URL][|copy=TEXTO]"]…
           [--artifact P] [--context P]… [--prioridade alta|normal]
           [--decisao] [--source S] [--blocks B] [--file PATH]
  done <id>
  snooze <id> <horas>
  list [--json]

Caminho: --file, senão env ORACFIT_OWNER_ACTIONS, senão
~/.config/llms-surf/acoes-do-dono.jsonl. Arquivo ausente = nenhuma ação.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ACTION_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
DEFAULT_PATH = Path.home() / ".config" / "llms-surf" / "acoes-do-dono.jsonl"
STEP_TEXT_MAX = 90
STEPS_MAX = 6
PRIORIDADES = ("alta", "normal")


def resolve_path(explicit: str | Path | None = None) -> Path:
    if explicit:
        return Path(explicit).expanduser()
    env = os.environ.get("ORACFIT_OWNER_ACTIONS")
    if env:
        return Path(env).expanduser()
    return DEFAULT_PATH


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_ts(ts: str) -> datetime | None:
    if not ts or not isinstance(ts, str):
        return None
    raw = ts.strip()
    try:
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        dt = datetime.fromisoformat(raw)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def valid_href(href: object) -> bool:
    if not isinstance(href, str) or not href:
        return False
    if href.startswith("https://"):
        return True
    if href.startswith("http://127.0.0.1") or href.startswith("http://localhost"):
        return True
    return False


def _valid_id(aid: object) -> bool:
    return isinstance(aid, str) and bool(ACTION_ID_RE.match(aid))


def parse_step(raw: str) -> dict | str:
    """Dicionário do step, ou mensagem de erro."""
    if not isinstance(raw, str):
        return "step inválido"
    parts = raw.split("|")
    text = parts[0]
    if len(text) > STEP_TEXT_MAX:
        return "step passa de 90 caracteres"
    step: dict = {"text": text}
    for part in parts[1:]:
        if part.startswith("href="):
            href = part[5:]
            if not valid_href(href):
                return "href inválido"
            step["href"] = href
        elif part.startswith("copy="):
            step["copy"] = part[5:]
    return step


def ago_from_dt(dt: datetime) -> str:
    delta = datetime.now(timezone.utc) - dt
    secs = max(0, int(delta.total_seconds()))
    if secs < 60:
        return "há 0 min"
    mins = secs // 60
    if mins < 60:
        return f"há {mins} min"
    hours = mins // 60
    if hours < 24:
        return f"há {hours} h"
    days = hours // 24
    if days == 1:
        return "há 1 dia"
    return f"há {days} dias"


def ago_label(ts: str) -> str:
    dt = parse_ts(ts)
    if dt is None:
        return "há 0 min"
    return ago_from_dt(dt)


def mtime_iso(path: Path) -> str:
    dt = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def artifact_status(path: str, context: list | None) -> dict:
    p = Path(path)
    if not p.is_file():
        return {
            "path": path,
            "exists": False,
            "generated_at": "",
            "generated_ago": "",
            "status": "sumiu",
        }
    art_mtime = p.stat().st_mtime
    info = {
        "path": path,
        "exists": True,
        "generated_at": mtime_iso(p),
        "generated_ago": ago_from_dt(
            datetime.fromtimestamp(art_mtime, tz=timezone.utc)),
        "status": "ok",
    }
    newest_path = None
    newest_mt = art_mtime
    for c in context or []:
        if not isinstance(c, str) or not c:
            continue
        cp = Path(c)
        if not cp.is_file():
            continue
        mt = cp.stat().st_mtime
        if mt > newest_mt:
            newest_mt = mt
            newest_path = c
    if newest_path is not None:
        info["status"] = "velho"
        info["stale_because"] = newest_path
    return info


def gui_item(rec: dict) -> dict:
    """Item do passo dono: asked_at/ago, steps, artifact com status."""
    item = {
        "id": rec["id"],
        "title": rec["title"],
        "plain": rec.get("plain") or "",
        "why": rec.get("why") or "",
        "source": rec.get("source") or "",
        "blocks": rec.get("blocks") or "",
        "age_days": rec.get("age_days") if rec.get("age_days") is not None
                    else age_days(rec.get("ts") or ""),
        "asked_at": rec.get("ts") or rec.get("asked_at") or "",
        "asked_ago": ago_label(rec.get("ts") or rec.get("asked_at") or ""),
        "steps": list(rec.get("steps") or []),
    }
    raw = rec.get("artifact")
    path = raw if isinstance(raw, str) and raw else ""
    if path:
        ctx = rec.get("context") if isinstance(rec.get("context"), list) else []
        item["artifact"] = artifact_status(path, ctx)
    return item


def _open_sort_key(rec: dict) -> tuple:
    pri = 0 if rec.get("priority") == "alta" else 1
    return (pri, rec.get("ts") or "")


def _valid_add(ev: dict) -> bool:
    if ev.get("type") != "add" or not _valid_id(ev.get("id")):
        return False
    title = ev.get("title")
    if not isinstance(title, str) or not title.strip():
        return False
    plain = ev.get("plain")
    if not isinstance(plain, str) or len(plain) > 140:
        return False
    return True


def _iter_events(path: Path):
    if not path.is_file():
        return
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(ev, dict):
            yield ev


def replay(path: Path) -> dict[str, dict]:
    """Ações abertas, mais antiga primeiro. add com id repetido substitui."""
    items: dict[str, dict] = {}
    for ev in _iter_events(path):
        typ = ev.get("type")
        aid = ev.get("id")
        if not _valid_id(aid):
            continue
        if typ == "add":
            if not _valid_add(ev):
                continue
            action = ev.get("action")
            if not isinstance(action, dict):
                action = {"kind": "none"}
            steps = ev.get("steps") if isinstance(ev.get("steps"), list) else []
            ctx = ev.get("context") if isinstance(ev.get("context"), list) else []
            pri = ev.get("priority")
            if pri not in PRIORIDADES:
                pri = "normal"
            art = ev.get("artifact") if isinstance(ev.get("artifact"), str) else ""
            items[aid] = {
                "id": aid,
                "ts": ev.get("ts") or "",
                "title": ev.get("title") or "",
                "plain": ev.get("plain") or "",
                "why": ev.get("why") or "",
                "action": action,
                "source": ev.get("source") or "",
                "blocks": ev.get("blocks") or "",
                "until": None,
                "steps": steps,
                "artifact": art,
                "context": ctx,
                "priority": pri,
                "decision": bool(ev.get("decision")),
            }
        elif typ == "done":
            items.pop(aid, None)
        elif typ == "snooze" and aid in items:
            items[aid]["until"] = ev.get("until")

    now = datetime.now(timezone.utc)
    open_items: dict[str, dict] = {}
    for aid, rec in items.items():
        until = rec.get("until")
        if until:
            dt = parse_ts(str(until))
            if dt is not None and dt > now:
                continue
        open_items[aid] = rec
    return open_items


def append_event(path: Path, event: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event, ensure_ascii=False) + "\n")


def age_days(ts: str) -> int:
    dt = parse_ts(ts)
    if dt is None:
        return 0
    delta = datetime.now(timezone.utc) - dt
    return max(0, int(delta.total_seconds() // 86400))


def open_list(path: Path) -> list[dict]:
    recs = sorted(replay(path).values(), key=_open_sort_key)
    out = []
    for rec in recs:
        item = {
            "id": rec["id"],
            "title": rec["title"],
            "plain": rec["plain"],
            "why": rec.get("why") or "",
            "source": rec.get("source") or "",
            "blocks": rec.get("blocks") or "",
            "age_days": age_days(rec.get("ts") or ""),
            "action": rec.get("action") or {"kind": "none"},
            "ts": rec.get("ts") or "",
            "steps": rec.get("steps") or [],
            "priority": rec.get("priority") or "normal",
            "decision": bool(rec.get("decision")),
        }
        if rec.get("artifact"):
            item["artifact"] = rec["artifact"]
        if rec.get("context"):
            item["context"] = rec["context"]
        out.append(item)
    return out


def _action_from_flags(command: str | None, href: str | None) -> dict:
    if command and href:
        return {"kind": "link", "label": "Abrir", "href": href, "command": command}
    if command:
        return {"kind": "copy", "label": "Copiar comando", "command": command}
    if href:
        return {"kind": "link", "label": "Abrir", "href": href}
    return {"kind": "none"}


def add_action(
    path: Path,
    aid: str,
    title: str,
    plain: str,
    why: str = "",
    command: str | None = None,
    href: str | None = None,
    source: str = "",
    blocks: str = "",
    steps_raw: list[str] | None = None,
    artifact: str | None = None,
    context: list[str] | None = None,
    prioridade: str = "normal",
    decisao: bool = False,
) -> int:
    if not ACTION_ID_RE.match(aid):
        print("id inválido (use letras minúsculas, números e hífen)", file=sys.stderr)
        return 2
    title = title.strip() if isinstance(title, str) else ""
    if not title:
        print("title vazio", file=sys.stderr)
        return 2
    if not isinstance(plain, str) or len(plain) > 140:
        print("plain passa de 140 caracteres", file=sys.stderr)
        return 2
    raw_steps = list(steps_raw or [])
    if len(raw_steps) > STEPS_MAX:
        print("no máximo 6 steps", file=sys.stderr)
        return 2
    steps: list[dict] = []
    for raw in raw_steps:
        parsed = parse_step(raw)
        if isinstance(parsed, str):
            print(parsed, file=sys.stderr)
            return 2
        steps.append(parsed)
    href = href.strip() if isinstance(href, str) and href.strip() else None
    command = command.strip() if isinstance(command, str) and command.strip() else None
    if href and not valid_href(href):
        print("href inválido", file=sys.stderr)
        return 2
    if not href and not command and not steps and not decisao:
        print("ação precisa de --href, --command, --step ou --decisao", file=sys.stderr)
        return 2
    if prioridade not in PRIORIDADES:
        print("prioridade inválida", file=sys.stderr)
        return 2
    art = ""
    if artifact and str(artifact).strip():
        art = str(Path(str(artifact).strip()).expanduser())
    ctx: list[str] = []
    for c in context or []:
        if c and str(c).strip():
            ctx.append(str(Path(str(c).strip()).expanduser()))
    ev: dict = {
        "type": "add",
        "id": aid,
        "ts": now_iso(),
        "title": title,
        "plain": plain,
        "why": why or "",
        "action": _action_from_flags(command, href),
        "source": source or "",
        "blocks": blocks or "",
        "priority": prioridade,
    }
    if steps:
        ev["steps"] = steps
    if art:
        ev["artifact"] = art
    if ctx:
        ev["context"] = ctx
    if decisao:
        ev["decision"] = True
    append_event(path, ev)
    return 0


def close_action(path: Path, aid: str) -> int:
    if aid not in replay(path):
        print("ação inexistente ou já fechada", file=sys.stderr)
        return 2
    append_event(path, {"type": "done", "id": aid, "ts": now_iso()})
    return 0


def snooze_action(path: Path, aid: str, hours: float) -> int:
    if hours <= 0:
        print("horas precisa ser maior que zero", file=sys.stderr)
        return 2
    if aid not in replay(path):
        print("ação inexistente ou já fechada", file=sys.stderr)
        return 2
    until = datetime.now(timezone.utc) + timedelta(hours=hours)
    append_event(path, {
        "type": "snooze",
        "id": aid,
        "ts": now_iso(),
        "until": until.strftime("%Y-%m-%dT%H:%M:%SZ"),
    })
    return 0


def apply_choice(path: Path, aid: str, choice: str) -> bool:
    """POST /api/gui/acao: feito → done; depois → snooze +24h. False = não gravou."""
    if choice == "feito":
        return close_action(path, aid) == 0
    if choice == "depois":
        return snooze_action(path, aid, 24) == 0
    return False


def _age_label(days: int) -> str:
    if days <= 0:
        return "hoje"
    if days == 1:
        return "1d"
    return f"{days}d"


def list_actions(path: Path, as_json: bool) -> int:
    items = open_list(path)
    if as_json:
        print(json.dumps(items, ensure_ascii=False))
        return 0
    for it in items:
        print(f"{it['id']}\t{_age_label(it['age_days'])}\t{it['title']}")
    return 0


def _take_file(argv: list[str]) -> tuple[str | None, list[str]]:
    file_arg = None
    out: list[str] = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--file":
            if i + 1 >= len(argv):
                print("ERROR: --file requer um caminho", file=sys.stderr)
                raise SystemExit(2)
            file_arg = argv[i + 1]
            i += 2
            continue
        if a.startswith("--file="):
            file_arg = a.split("=", 1)[1]
            i += 1
            continue
        out.append(a)
        i += 1
    return file_arg, out


def main(argv: list[str] | None = None) -> int:
    raw = list(sys.argv[1:] if argv is None else argv)
    try:
        file_arg, raw = _take_file(raw)
    except SystemExit as exc:
        return int(exc.code or 2)
    path = resolve_path(file_arg)

    ap = argparse.ArgumentParser(
        prog="oracfit acao",
        description="Pedidos de agente ao dono — viram passo na GUI.",
    )
    sub = ap.add_subparsers(dest="cmd")

    p_add = sub.add_parser("add", help="registrar um pedido")
    p_add.add_argument("id")
    p_add.add_argument("--title", required=True)
    p_add.add_argument("--plain", required=True)
    p_add.add_argument("--why", default="")
    p_add.add_argument("--command", default=None)
    p_add.add_argument("--href", default=None)
    p_add.add_argument("--step", action="append", default=[])
    p_add.add_argument("--artifact", default=None)
    p_add.add_argument("--context", action="append", default=[])
    p_add.add_argument("--prioridade", choices=PRIORIDADES, default="normal")
    p_add.add_argument("--decisao", action="store_true")
    p_add.add_argument("--source", default="")
    p_add.add_argument("--blocks", default="")

    p_done = sub.add_parser("done", help="marcar feito")
    p_done.add_argument("id")

    p_sn = sub.add_parser("snooze", help="esconder por N horas")
    p_sn.add_argument("id")
    p_sn.add_argument("horas")

    p_list = sub.add_parser("list", help="listar abertas")
    p_list.add_argument("--json", action="store_true")

    args = ap.parse_args(raw)
    if not args.cmd:
        ap.print_usage(sys.stderr)
        return 2
    if args.cmd == "add":
        return add_action(
            path, args.id, args.title, args.plain,
            why=args.why, command=args.command, href=args.href,
            source=args.source, blocks=args.blocks,
            steps_raw=args.step, artifact=args.artifact,
            context=args.context, prioridade=args.prioridade,
            decisao=args.decisao,
        )
    if args.cmd == "done":
        return close_action(path, args.id)
    if args.cmd == "snooze":
        try:
            hours = float(args.horas)
        except ValueError:
            print("horas inválidas", file=sys.stderr)
            return 2
        return snooze_action(path, args.id, hours)
    if args.cmd == "list":
        return list_actions(path, args.json)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
