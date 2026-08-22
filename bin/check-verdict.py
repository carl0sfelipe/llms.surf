#!/usr/bin/env python3
"""check-verdict.py — contrato canônico de veredito, fail-closed (v4).

Consolida as lições dos incidentes de contrato de juiz/critic:
  - biggest_gap vazio/evasivo loopa builder cego (t3-judge, gauntlet-biggest-gap)
  - APPROVED truncado/parcial não pode aprovar (t4-integrity-override)
  - substring "PASS" não é veredito; enum desconhecido = quebrado, não pass
    (veredito-sem-degrau: `None` passou no hard gate)
  - PASS_WITH_NOTES com CRITICAL abertos passou no gate de enum
    (veredito-sem-degrau: severidade estruturada ignorada)
  - canal do veredito é ARQUIVO, não prosa no chat (autarca 2/3 fora do canal)

Uso:
  check-verdict.py <verdict.json> [--min-score N] [--score-field CAMPO]
                   [--require-field CAMPO]... [--max-critical N]

Exit codes (fail-closed em TODAS as bordas):
  0 = APPROVED e contrato satisfeito
  1 = veredito válido mas recusado (não-APPROVED, gap vazio, score baixo,
      critical aberto, campo exigido vazio) — falha CONTÁVEL no teto
  2 = veredito QUEBRADO (arquivo ausente, JSON inválido/truncado, enum
      desconhecido) — nunca aprova, nunca conta como "falta trabalho"
"""

import argparse
import json
import sys

EVASIVE = {"nenhuma", "nenhum", "none", "n/a", "na", "-", "nada", "não há", "nao ha"}
KNOWN_VERDICTS = {"APPROVED", "REJECTED", "REVISIONS", "NEEDS_WORK", "PASS_WITH_NOTES"}
CRITICAL_MARKERS = {"critical", "blocker", "red", "🔴"}


def refuse(problems):
    print("RECUSADO pelo contrato do veredito:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)


def broken(msg):
    print(f"VEREDITO QUEBRADO (fail-closed): {msg}", file=sys.stderr)
    sys.exit(2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("verdict_file")
    ap.add_argument("--min-score", type=float, default=None,
                    help="nota mínima prevista do dono para aprovar")
    ap.add_argument("--score-field", default="owner_score_pred")
    ap.add_argument("--require-field", action="append", default=[],
                    help="campo que deve existir e ser não-vazio")
    ap.add_argument("--max-critical", type=int, default=0,
                    help="máximo de findings com severidade critical/blocker")
    args = ap.parse_args()

    try:
        raw = open(args.verdict_file, encoding="utf-8").read()
    except OSError as e:
        broken(f"arquivo ausente ou ilegível: {e}")

    try:
        v = json.loads(raw)
    except json.JSONDecodeError as e:
        # JSON truncado (contexto estourou no meio do APPROVED) cai aqui.
        broken(f"JSON inválido/truncado: {e}")

    if not isinstance(v, dict):
        broken(f"raiz não é objeto: {type(v).__name__}")

    verdict = v.get("verdict")
    if not isinstance(verdict, str) or verdict.strip() == "":
        broken(f"campo canônico 'verdict' ausente ou vazio (campos presentes: {sorted(v.keys())})")
    verdict = verdict.strip()
    if verdict not in KNOWN_VERDICTS:
        # enum desconhecido é QUEBRADO, não reprovado: "None"/"aprovado"/typo
        # não podem virar nem pass nem fail contável silencioso.
        broken(f"verdict={verdict!r} fora do vocabulário {sorted(KNOWN_VERDICTS)}")

    problems = []

    if verdict != "APPROVED":
        problems.append(f"verdict={verdict} (só APPROVED exato fecha)")

    gap = v.get("biggest_gap")
    gap = gap.strip() if isinstance(gap, str) else ""
    if not gap or gap.lower() in EVASIVE:
        problems.append("biggest_gap vazio ou evasivo (APPROVED sem gap não fecha — fail-closed)")

    if args.min_score is not None:
        score = v.get(args.score_field)
        if isinstance(score, bool) or not isinstance(score, (int, float)):
            problems.append(f"{args.score_field}={score!r} não é numérico")
        elif score < args.min_score:
            problems.append(f"{args.score_field}={score} < mínimo {args.min_score}")

    for field in args.require_field:
        val = v.get(field)
        if val is None or (isinstance(val, str) and not val.strip()):
            problems.append(f"campo exigido '{field}' ausente ou vazio")

    findings = v.get("findings")
    if isinstance(findings, list):
        crit = 0
        for f in findings:
            if not isinstance(f, dict):
                continue
            sev = str(f.get("severity", "")).strip().lower()
            resolved = f.get("resolved") is True
            if sev in CRITICAL_MARKERS and not resolved:
                crit += 1
        if crit > args.max_critical:
            problems.append(
                f"{crit} finding(s) critical/blocker não-resolvidos "
                f"(máximo {args.max_critical}) — PASS_WITH_NOTES+CRITICAL não passa"
            )

    # Escala canônica: owner_score_pred é SEMPRE 0–10 (perfil ananke). Na noite
    # de 2026-08-13 metade dos critics previu em 0–5 (4.5–4.8) e metade em 0–10
    # (7.5–9.0). Valor ≤ 5.0 sem escala declarada ("score_scale") é ambíguo —
    # WARN em stderr, NUNCA erro: vereditos existentes não quebram.
    score_val = v.get(args.score_field)
    if (not str(v.get("score_scale") or "").strip()
            and not isinstance(score_val, bool)
            and isinstance(score_val, (int, float)) and score_val <= 5.0):
        print("WARN: pred <=5.0: confirme escala 0-10 (perfil ananke) — "
              "vereditos antigos podem estar em 0-5", file=sys.stderr)

    if problems:
        refuse(problems)

    print(f"OK: verdict=APPROVED, biggest_gap presente"
          + (f", {args.score_field}={v.get(args.score_field)}" if args.min_score is not None else ""))
    sys.exit(0)


if __name__ == "__main__":
    main()
