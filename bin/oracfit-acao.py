#!/usr/bin/env python3
"""oracfit-acao.py — pedidos de agente ao dono (arquivo append-only).

Uso (via `oracfit acao`):
  add <id> --title T --plain P [--why W] [--command C | --href H]
           [--source S] [--blocks B] [--file PATH]
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


def _valid_id(aid: object) -> bool:
    return isinstance(aid, str) and bool(ACTION_ID_RE.match(aid))


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
    out = []
    for rec in replay(path).values():
        out.append({
            "id": rec["id"],
            "title": rec["title"],
            "plain": rec["plain"],
            "why": rec.get("why") or "",
            "source": rec.get("source") or "",
            "blocks": rec.get("blocks") or "",
            "age_days": age_days(rec.get("ts") or ""),
            "action": rec.get("action") or {"kind": "none"},
        })
    return out


def _action_from_flags(command: str | None, href: str | None) -> dict | None:
    if command and href:
        return None
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
    action = _action_from_flags(command, href)
    if action is None:
        print("use --command ou --href, não os dois", file=sys.stderr)
        return 2
    append_event(path, {
        "type": "add",
        "id": aid,
        "ts": now_iso(),
        "title": title,
        "plain": plain,
        "why": why or "",
        "action": action,
        "source": source or "",
        "blocks": blocks or "",
    })
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
