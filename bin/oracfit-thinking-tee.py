#!/usr/bin/env python3
"""oracfit-thinking-tee.py — le stdout do runner em --format json, traduz de
volta pra texto legivel no PROPRIO stdout (nao quebra run.log dos
chamadores) e emite eventos estruturados em events.jsonl: 'thinking' (texto
narrativo, em lote) e 'tool_call' (qual ferramenta rodou + argumento real).

Por que existe (2026-08-01): stdout default do opencode (prosa) nunca
mostrava qual grep/edit/read rodou, so' a narracao textual — usuario pediu
"Total significa que eu quero tudo". --format json expoe isso
(type=tool_use, part.tool, part.state.input) mas e' JSON cru, ilegivel se
jogado direto no run.log. Este script faz a traducao.

Por que nao 1 evento por linha: cada emissao de evento hoje spawna um
processo python (oracfit_emit_event) - fazer isso por linha explodiria
custo de processo. Continua 1 processo long-lived, thinking em lote
(por tempo/linha), tool_call emitido na hora (sao poucos, discretos, cada
um e' informacao nova de verdade — nao faz sentido tentar agrupar).

Env:
  ORACFIT_RUN_ID       obrigatorio pra emitir evento (sem ele, so' traduz e
                        faz tee, sem gravar events.jsonl)
  ORACFIT_EVENTS_FILE  caminho de events.jsonl
  ORACFIT_SESSION_FILE opcional — se setado, grava o sessionID do primeiro
                        evento JSON visto (redundante com a captura via
                        stderr do proprio runner.sh, mas nao custa nada e
                        cobre o caso de quem desligar --log-level INFO)

Se stdin NAO for JSON valido (--format json desligado via
DISPATCH_RUNNER_FORMAT_JSON=0, ou runner que nao seja opencode), cai pra
tee puro linha a linha — nao quebra o comportamento antigo.
"""
import sys
import os
import json
import time
from datetime import datetime, timezone

FLUSH_LINES = 20
FLUSH_SECONDS = 2.0


def main():
    run_id = os.environ.get("ORACFIT_RUN_ID")
    events_file = os.environ.get("ORACFIT_EVENTS_FILE")
    session_file = os.environ.get("ORACFIT_SESSION_FILE")
    emit = bool(run_id and events_file)
    session_written = False

    text_buf = []
    last_flush = time.time()
    tools_emitted = set()  # callID ja' emitido — tool_use repete por status

    def emit_event(obj_type, **fields):
        if not emit:
            return
        obj = {
            "v": 1,
            "ts": datetime.now(timezone.utc).isoformat(),
            "run_id": run_id,
            "type": obj_type,
        }
        obj.update(fields)
        try:
            os.makedirs(os.path.dirname(events_file), exist_ok=True)
            with open(events_file, "a") as f:
                f.write(json.dumps(obj, ensure_ascii=False) + "\n")
        except OSError:
            pass

    def flush_text():
        nonlocal text_buf, last_flush
        if text_buf:
            emit_event("thinking", detail="\n".join(text_buf))
        text_buf = []
        last_flush = time.time()

    def maybe_capture_session(sid):
        nonlocal session_written
        if session_written or not session_file or not sid:
            return
        try:
            os.makedirs(os.path.dirname(session_file), exist_ok=True)
            with open(session_file, "w") as f:
                f.write(sid)
            session_written = True
        except OSError:
            pass

    def tool_summary(part):
        tool = part.get("tool", "?")
        state = part.get("state", {}) or {}
        title = state.get("title")
        inp = state.get("input", {}) or {}
        if title:
            return f"[{tool}] {title}"
        if inp:
            first_val = next(iter(inp.values()), "")
            return f"[{tool}] {first_val}"
        return f"[{tool}]"

    for raw_line in sys.stdin:
        stripped = raw_line.rstrip("\n")
        if not stripped:
            continue

        parsed = None
        try:
            parsed = json.loads(stripped)
        except json.JSONDecodeError:
            pass

        if parsed is None:
            # nao e' JSON — modo antigo, tee puro + acumula como thinking
            sys.stdout.write(raw_line)
            sys.stdout.flush()
            text_buf.append(stripped)
            if len(text_buf) >= FLUSH_LINES or (time.time() - last_flush) >= FLUSH_SECONDS:
                flush_text()
            continue

        maybe_capture_session(parsed.get("sessionID"))
        ev_type = parsed.get("type")
        part = parsed.get("part", {}) or {}

        if ev_type == "text":
            text = part.get("text", "")
            if text:
                sys.stdout.write(text + "\n")
                sys.stdout.flush()
                text_buf.append(text)
        elif ev_type == "tool_use":
            state = part.get("state", {}) or {}
            call_id = part.get("callID", "")
            status = state.get("status")
            key = (call_id, status)
            if status == "completed" and key not in tools_emitted:
                tools_emitted.add(key)
                summary = tool_summary(part)
                sys.stdout.write(summary + "\n")
                sys.stdout.flush()
                metadata = state.get("metadata", {}) or {}
                preview = metadata.get("preview")
                kwargs = {
                    "tool": part.get("tool", "?"),
                    "detail": summary,
                    # objeto nativo, NAO json.dumps — senao vira string escapada
                    # dentro de JSON (ilegivel no painel, achado real 2026-08-01)
                    "input": state.get("input", {}),
                }
                if isinstance(preview, str) and preview:
                    kwargs["preview"] = preview[:300]
                emit_event("tool_call", **kwargs)
        # step_start/step_finish e outros tipos estruturais: sem valor
        # narrativo, nao vao pro stdout (mantem run.log limpo) nem viram
        # evento — so' sessionID (ja capturado acima) importa deles.

        if len(text_buf) >= FLUSH_LINES or (time.time() - last_flush) >= FLUSH_SECONDS:
            flush_text()

    flush_text()


if __name__ == "__main__":
    main()
