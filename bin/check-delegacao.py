#!/usr/bin/env python3
"""check-delegacao.py — vale a pena delegar esta spec a este executor?"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

TOK_POR_CHAR = 0.25
TOK_POR_LINHA = 12
VOLTAS = 6
FATOR_SAIDA = 1.3
TENTATIVAS_PADRAO = 1.5
RAZAO_MAX = 0.5
MARGEM = 0.7
ORCAMENTO = re.compile(r"(?:≤|<=)\s*(\d+)\s+(?:linhas|lines)", re.I)
TICK = re.compile(r"`([^`]+)`")


def die(code, msg):
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def secao(texto, nome):
    linhas = texto.splitlines(True)
    ini = next((i for i, l in enumerate(linhas) if l.startswith("#") and nome in l), None)
    if ini is None:
        return ""
    corpo = []
    for l in linhas[ini + 1:]:
        if l.startswith("## "):
            break
        corpo.append(l)
    return "".join(corpo)


def media_tentativas(workdir, executor):
    p = Path(workdir) / ".dispatch/ledger/mode.jsonl"
    if not p.is_file():
        return TENTATIVAS_PADRAO
    vals = []
    for line in p.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if d.get("model_id") == executor and "attempt" in d:
            try:
                vals.append(float(d["attempt"]))
            except (TypeError, ValueError):
                continue
    return sum(vals) / len(vals) if len(vals) >= 3 else TENTATIVAS_PADRAO


def preco(doc, mid):
    m = (doc.get("modelos") or {}).get(mid)
    if not isinstance(m, dict) or m.get("in") is None or m.get("out") is None:
        die(4, f"check-delegacao: preço desconhecido para {mid} — preencha core/precos.json")
    return float(m["in"]), float(m["out"])


def inteiro_se_cabe(x):
    return int(x) if float(x) == int(x) else x


class Parser(argparse.ArgumentParser):
    def error(self, message):
        die(3, f"check-delegacao: {message}")


def main():
    raiz = Path(__file__).resolve().parent.parent
    ap = Parser(prog="check-delegacao")
    ap.add_argument("spec")
    ap.add_argument("--executor", required=True)
    ap.add_argument("--orquestrador", default="claude-opus-5-5")
    ap.add_argument("--precos", default=str(raiz / "core/precos.json"))
    ap.add_argument("--workdir", default=".")
    ap.add_argument("--paralelo", action="store_true")
    ap.add_argument("--proteger-contexto", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    try:
        texto = Path(args.spec).read_text(encoding="utf-8")
    except OSError as e:
        die(3, f"check-delegacao: {e}")
    spec_tok = math.ceil(len(texto) * TOK_POR_CHAR)
    ns = [int(n) for n in ORCAMENTO.findall(secao(texto, "ENTREGÁVEIS"))]
    if not ns:
        die(3, 'check-delegacao: declare o orçamento de linhas nos ENTREGÁVEIS (ex.: "arquivo.py (≤ 80 linhas)")')
    saida_tok = sum(ns) * TOK_POR_LINHA
    ctx = 0.0
    for raw in TICK.findall(secao(texto, "Dados verificados")):
        f = Path(args.workdir) / raw
        if f.is_file():
            ctx += f.stat().st_size * TOK_POR_CHAR
    tent = media_tentativas(args.workdir, args.executor)
    try:
        doc = json.loads(Path(args.precos).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        die(4, f"check-delegacao: preço desconhecido para {args.executor} — preencha core/precos.json")
    ex_in, ex_out = preco(doc, args.executor)
    orq_in, orq_out = preco(doc, args.orquestrador)
    m = 1e6
    delegar = (spec_tok * orq_out + saida_tok * orq_in) / m + tent * (
        ctx * VOLTAS * ex_in + saida_tok * FATOR_SAIDA * ex_out) / m
    direto = (saida_tok * FATOR_SAIDA * orq_out + tent * ctx * VOLTAS * orq_in) / m
    if ex_in == 0 and ex_out == 0:
        veredito, motivo = "DELEGAR", "executor sem custo por token"
    elif args.paralelo:
        veredito, motivo = "DELEGAR", "orquestrador tem trabalho em paralelo"
    elif args.proteger_contexto:
        veredito, motivo = "DELEGAR", "proteger o contexto do orquestrador"
    elif spec_tok / saida_tok > RAZAO_MAX:
        pct = round(100 * spec_tok / saida_tok)
        veredito, motivo = "DIRETO", f"spec é {pct}% da entrega ({spec_tok} de {saida_tok} tok)"
    else:
        pct = round(100 * delegar / direto) if direto else 0
        motivo = f"delegar custa {pct}% de fazer direto"
        veredito = "DELEGAR" if delegar <= MARGEM * direto else "DIRETO"
    rec = {
        "veredito": veredito, "motivo": motivo, "spec_tok": spec_tok,
        "saida_tok": saida_tok, "contexto_tok": inteiro_se_cabe(ctx),
        "tentativas": inteiro_se_cabe(tent), "custo_delegar": delegar,
        "custo_direto": direto, "executor": args.executor,
        "orquestrador": args.orquestrador,
    }
    if args.json:
        print(json.dumps(rec, ensure_ascii=False))
    else:
        print(f"{veredito} — {motivo}; delegar ≈ US${delegar:.4f} vs direto ≈ US${direto:.4f} "
              f"(executor {args.executor}).")
    raise SystemExit(0 if veredito == "DELEGAR" else 10)


if __name__ == "__main__":
    main()
