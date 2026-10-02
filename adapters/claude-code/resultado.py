#!/usr/bin/env python3
"""Resumo de uma resposta `claude -p --output-format json` (stdin) em UMA linha JSON (stdout).

    {"cost_usd": 0.41, "in_tok": 1200, "cache_read_tok": 80000, "cache_write_tok": 9000,
     "out_tok": 3100, "denied": ["Write", "Bash"], "denied_writes": 2}

Usado pelo runner.sh para (1) o custo real do executor ir para o ledger (proposta
docs/proposta-check-delegacao.md §4 — antes o ledger gravava estimated_cost="0") e (2) falhar na
hora quando toda escrita foi negada (incidente 2026-10-02-claude-code-runner-sai-0-com-escrita-negada).
A saída do runner vem com stderr misturado: pega o ÚLTIMO objeto JSON com "type": "result".
Sem objeto reconhecível: imprime nada e sai 0 — o runner segue como antes.
"""

from __future__ import annotations

import json
import sys

WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}


def ultimo_resultado(texto: str) -> dict | None:
    candidatos = [texto] + texto.splitlines()[::-1]
    for bloco in candidatos:
        bloco = bloco.strip()
        if not bloco.startswith("{"):
            continue
        try:
            doc = json.loads(bloco)
        except ValueError:
            continue
        if isinstance(doc, dict) and doc.get("type") == "result":
            return doc
    return None


def resumo(doc: dict) -> dict:
    usage = doc.get("usage") or {}
    negadas = [d.get("tool_name", "?") for d in doc.get("permission_denials") or [] if isinstance(d, dict)]
    return {
        "cost_usd": doc.get("total_cost_usd") or 0,
        "in_tok": usage.get("input_tokens") or 0,
        "cache_read_tok": usage.get("cache_read_input_tokens") or 0,
        "cache_write_tok": usage.get("cache_creation_input_tokens") or 0,
        "out_tok": usage.get("output_tokens") or 0,
        "denied": negadas,
        "denied_writes": sum(1 for n in negadas if n in WRITE_TOOLS),
    }


if __name__ == "__main__":
    doc = ultimo_resultado(sys.stdin.read())
    if doc is not None:
        print(json.dumps(resumo(doc)))
