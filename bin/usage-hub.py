#!/usr/bin/env python3
"""usage-hub.py — hub de uso de tokens built-in (v3.5).

Sucessor do ~/ai-usage-hub (daemon HTTP Python). O daemon falhou pelas
partes remotas: a API de usage do OpenCode Go nunca existiu publicamente,
o refresh OAuth do Claude é bloqueado por Cloudflare, e limits.json ficou
todo null — o scheduler respondia "use" para sempre. O que FUNCIONAVA era
100% local, então a v3.5 embute só isso:

  1. ~/.local/share/opencode/opencode.db  — tokens reais por providerID
     (session.model é JSON com providerID: agrupar por ele elimina o drift
     de model-ids que cegava o hub antigo)
  2. core/usage-limits.json               — limites por provider/janela
     (null = só rastreia; NUNCA inventar número —
     incidents/2026-07-29-spec-com-dado-inventado-passou-no-gate.md)
  3. .dispatch/usage/observations.jsonl   — eventos reais de rate_limit /
     balance vindos da cadeia RF-08 (run-with-fallback.sh exit 2/4)
  4. model-registry.json                  — id_status / tier / provider

Subcomandos:
  status    [--json]                visão por provider (janelas 5h/day/week)
  recommend --provider ID [--json]  use/wait/exhausted — exit 0/1/4
                                    (mesmo contrato do pre-dispatch-check)
  pick      --tiers "r1 r2 …"       primeiro model ref viável (quota +
            | --tier free           observações + id_status); stdout = ref
  observe   --kind K [--provider P | --model-ref M] [--message S] [--source S]
  limits    [--set PROVIDER JANELA TOKENS]

Fail-open: sem DB ou sem limites calibrados, recommend devolve "use" com
aviso — gate nunca trava por sensor ausente (mesma filosofia do
pre-dispatch-check.sh). Rate limit observado é o único sinal que SEMPRE
bloqueia, porque é evento real, não estimativa.

Env: ORACFIT_USAGE_DB, ORACFIT_USAGE_LIMITS, ORACFIT_USAGE_OBS,
     ORACFIT_USAGE_OBS_LOOKBACK_MIN (default 15), MODEL_REGISTRY
Incidentes: 2026-07-24-rate-limit-chega-como-timeout-nao-como-e.md,
            2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-run-finished.md
"""

import argparse
import json
import os
import sqlite3
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

DB_PATH = Path(os.environ.get(
    "ORACFIT_USAGE_DB",
    Path.home() / ".local/share/opencode/opencode.db"))
LIMITS_PATH = Path(os.environ.get(
    "ORACFIT_USAGE_LIMITS", REPO_ROOT / "core/usage-limits.json"))
OBS_PATH = Path(os.environ.get(
    "ORACFIT_USAGE_OBS", REPO_ROOT / ".dispatch/usage/observations.jsonl"))
REGISTRY_PATH = Path(os.environ.get(
    "MODEL_REGISTRY", REPO_ROOT / "model-registry.json"))
OBS_LOOKBACK_MIN = int(os.environ.get("ORACFIT_USAGE_OBS_LOOKBACK_MIN", "15"))

WINDOWS = {"5h": 5 * 3600, "day": 24 * 3600, "week": 7 * 24 * 3600}
# id_status que desqualifica um modelo (mesma família do run-with-fallback.sh,
# que pula FANTASMA/NAO-VERIFICADO; APOSENTADO = retirado do catálogo upstream)
DEAD_STATUS = ("FANTASMA", "NAO-VERIFICADO", "APOSENTADO")

BLOCK_KINDS = ("rate_limit", "balance", "key_limit")


# ── fontes de dados ──────────────────────────────────────────────────────────

def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def load_limits():
    data = load_json(LIMITS_PATH) or {}
    return data.get("providers", {}), data.get("wait_pct", 85)


def load_registry_models():
    data = load_json(REGISTRY_PATH) or {}
    return data.get("models", [])


def usage_by_provider():
    """{provider: {janela: tokens_in+out}} a partir do opencode.db.

    Devolve (dict, aviso). Fail-open: DB ausente → ({}, aviso).
    """
    if not DB_PATH.exists():
        return {}, f"db-ausente:{DB_PATH}"
    now_ms = int(time.time() * 1000)
    out = {}
    try:
        con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=3)
        try:
            for wname, wsecs in WINDOWS.items():
                cutoff = now_ms - wsecs * 1000
                rows = con.execute(
                    "SELECT json_extract(model,'$.providerID'),"
                    "       SUM(tokens_input+tokens_output)"
                    " FROM session WHERE time_created > ?"
                    "   AND model IS NOT NULL GROUP BY 1",
                    (cutoff,)).fetchall()
                for prov, tok in rows:
                    if not prov:
                        continue
                    out.setdefault(prov, {})[wname] = int(tok or 0)
        finally:
            con.close()
    except sqlite3.Error as e:
        return {}, f"db-erro:{e}"
    return out, None


def recent_observations(provider=None, lookback_min=None):
    """Observações dos últimos N minutos, mais recente primeiro."""
    lookback = (lookback_min or OBS_LOOKBACK_MIN) * 60
    cutoff = time.time() - lookback
    hits = []
    if not OBS_PATH.exists():
        return hits
    try:
        lines = OBS_PATH.read_text(encoding="utf-8").splitlines()
    except OSError:
        return hits
    # arquivo é append-only: as recentes estão no fim
    for line in reversed(lines[-500:]):
        try:
            obs = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obs.get("epoch", 0) < cutoff:
            break
        # canoniza os dois lados: observação antiga pode ter sido gravada com
        # vocabulário do registry (ex: "zen") antes da normalização
        if provider and canon_provider(obs.get("provider", "")) != \
                canon_provider(provider):
            continue
        hits.append(obs)
    return hits


# ── mapeamento model ref → provider ──────────────────────────────────────────

# O vocabulário canônico é o providerID do opencode.db (é onde o uso vive).
# O campo `provider` do registry usa OUTRO vocabulário (zen, z.ai, anthropic…)
# — verificado em 2026-08-12: registry diz "zen", o db grava "opencode".
# Extensível sem código via chave "aliases" do core/usage-limits.json.
PROVIDER_ALIASES = {
    "zen": "opencode",
    "z.ai": "zhipuai-coding-plan",
    "zhipuai": "zhipuai-coding-plan",
    "anthropic": "claude",
}


def canon_provider(prov):
    data = load_json(LIMITS_PATH) or {}
    aliases = dict(PROVIDER_ALIASES, **(data.get("aliases") or {}))
    return aliases.get(prov, prov)


def provider_of(ref, models=None):
    """providerID (vocabulário do opencode.db) de um model ref.

    Ordem: cli_hints.opencode do registry (formato `<providerID>/<model>` —
    fonte exata; o campo `provider` do registry é ambíguo: "deepseek" roteia
    ora via nvidia, ora via deepseek-direct) → campo provider canonizado →
    prefixo `cli:` → primeiro segmento de path → `opencode` (refs nus são os
    ids zen free do adapter default).
    """
    models = models if models is not None else load_registry_models()
    for m in models:
        hints = m.get("cli_hints") or {}
        if ref == m.get("id") or ref in hints.values():
            oc_hint = hints.get("opencode") or ""
            if "/" in oc_hint:
                return oc_hint.split("/", 1)[0]
            prov = m.get("provider")
            if prov:
                return canon_provider(prov)
    if ":" in ref and "/" not in ref.split(":", 1)[0]:
        return ref.split(":", 1)[0]        # claude:opus → claude
    if "/" in ref:
        return ref.split("/", 1)[0]        # openrouter/deepseek/… → openrouter
    return "opencode"


def registry_entry(ref, models):
    for m in models:
        hints = (m.get("cli_hints") or {}).values()
        if ref == m.get("id") or ref in hints:
            return m
    return None


# ── decisão ──────────────────────────────────────────────────────────────────

def recommend(provider, usage=None, warn=None):
    """Decisão para UM provider. Retorna dict com action/exit/message.

    exit: 0=use, 1=wait, 4=exhausted (contrato do pre-dispatch-check.sh).
    """
    provider = canon_provider(provider)
    if usage is None:
        usage, warn = usage_by_provider()
    limits, wait_pct = load_limits()

    # 1. evento real vence estimativa: rate limit / saldo observado há pouco
    for obs in recent_observations(provider):
        kind = obs.get("kind")
        if kind not in BLOCK_KINDS:
            continue
        age_min = max(0, (time.time() - obs.get("epoch", 0)) / 60)
        if kind == "rate_limit":
            minutes = max(1, round(OBS_LOOKBACK_MIN - age_min))
            return {"provider": provider, "action": "wait", "exit": 1,
                    "minutes_to_reset": minutes,
                    "message": (f"rate_limit observado ha {age_min:.0f}min"
                                f" ({obs.get('source', '?')}:"
                                f" {obs.get('model', '?')})")}
        return {"provider": provider, "action": "exhausted", "exit": 4,
                "minutes_to_reset": None,
                "message": (f"{kind} observado ha {age_min:.0f}min"
                            f" ({obs.get('source', '?')}:"
                            f" {obs.get('model', '?')})")}

    # 2. limites calibrados (null = só rastreia, nunca bloqueia)
    prov_usage = usage.get(provider, {})
    prov_limits = (limits.get(provider) or {}).get("windows", {})
    worst = None
    for wname, wcfg in prov_limits.items():
        limit = (wcfg or {}).get("limit_tokens")
        if not limit:
            continue
        used = prov_usage.get(wname, 0)
        pct = used * 100.0 / limit
        if worst is None or pct > worst[1]:
            worst = (wname, pct, used, limit)
    if worst:
        wname, pct, used, limit = worst
        detail = f"{wname}: {used}/{limit} tokens ({pct:.0f}%)"
        if pct >= 100:
            return {"provider": provider, "action": "exhausted", "exit": 4,
                    "minutes_to_reset": None,
                    "message": f"limite estourado — {detail}"}
        if pct >= wait_pct:
            return {"provider": provider, "action": "wait", "exit": 1,
                    "minutes_to_reset": None,
                    "message": f"acima de {wait_pct}% — {detail}"}

    # 3. livre — com transparência sobre o que o sensor NÃO vê
    parts = []
    if prov_usage:
        parts.append("uso 5h/day/week: " + "/".join(
            str(prov_usage.get(w, 0)) for w in WINDOWS))
    if not prov_limits or not any(
            (w or {}).get("limit_tokens") for w in prov_limits.values()):
        parts.append("sem limite calibrado (so rastreio)")
    if warn:
        parts.append(f"fail-open: {warn}")
    return {"provider": provider, "action": "use", "exit": 0,
            "minutes_to_reset": None,
            "message": "; ".join(parts) or "sem uso na janela"}


def pick(refs, as_json=False):
    """Primeiro model ref viável da lista, na ordem dada.

    Pula id_status morto (registry) e provider bloqueado (recommend).
    stdout = só o ref (composável: DISPATCH_MODEL_REF=$(… pick …)).
    Exit 0 = escolhido; 1 = nenhum viável agora.
    """
    models = load_registry_models()
    usage, warn = usage_by_provider()
    trail = []
    for ref in refs:
        entry = registry_entry(ref, models)
        # Incidente 2026-08-12 (baseline da release): ref AUSENTE do registry
        # passava batido (entry None -> id_status "" -> não morto) e o pick
        # aprovava um modelo que o runner rejeita em ~0s ("ausente do
        # model-registry.json", regra 11.2) — o batch queimou 2x600s em
        # attempts de 0s. O catálogo é o registry: ref fora dele é invento
        # do chamador, nunca escolha viável.
        if entry is None:
            trail.append({"ref": ref, "skipped":
                          "ausente do model-registry (runner rejeitaria — regra 11.2)"})
            continue
        status = entry.get("id_status") or ""
        if any(d in status for d in DEAD_STATUS):
            trail.append({"ref": ref, "skipped": f"id_status: {status[:60]}"})
            continue
        prov = provider_of(ref, models)
        rec = recommend(prov, usage=usage, warn=warn)
        trail.append({"ref": ref, "provider": prov,
                      "action": rec["action"], "message": rec["message"]})
        if rec["action"] == "use":
            if as_json:
                print(json.dumps({"picked": ref, "provider": prov,
                                  "trail": trail}, ensure_ascii=False))
            else:
                print(ref)
            return 0
    if as_json:
        print(json.dumps({"picked": None, "trail": trail},
                         ensure_ascii=False))
    else:
        for t in trail:
            print(f"  ✗ {t['ref']}: {t.get('skipped') or t.get('message')}",
                  file=sys.stderr)
        print("usage-hub: nenhum ref viável agora — espere ou amplie a lista",
              file=sys.stderr)
    return 1


# ── subcomandos ──────────────────────────────────────────────────────────────

def cmd_status(args):
    usage, warn = usage_by_provider()
    limits, _ = load_limits()
    providers = sorted(set(usage) | set(limits))
    rows = []
    for prov in providers:
        u = usage.get(prov, {})
        wins = (limits.get(prov) or {}).get("windows", {})
        pcts = {}
        for wname, wcfg in wins.items():
            limit = (wcfg or {}).get("limit_tokens")
            if limit:
                pcts[wname] = round(u.get(wname, 0) * 100.0 / limit, 1)
        obs = recent_observations(prov, lookback_min=24 * 60)
        last_obs = obs[0] if obs else None
        rows.append({"provider": prov,
                     "tokens": {w: u.get(w, 0) for w in WINDOWS},
                     "limit_pct": pcts or None,
                     "last_observation_24h": last_obs})
    if args.json:
        print(json.dumps({"warn": warn, "providers": rows},
                         ensure_ascii=False, indent=1))
        return 0
    if warn:
        print(f"⚠ {warn}")
    fmt = "{:<24}{:>12}{:>14}{:>14}  {:<18}{}"
    print(fmt.format("provider", "5h", "day", "week", "limite", "obs 24h"))
    for r in rows:
        t = r["tokens"]
        lp = r["limit_pct"]
        lim = ",".join(f"{k}:{v}%" for k, v in lp.items()) if lp else "—"
        o = r["last_observation_24h"]
        otxt = f"{o['kind']} ({o.get('model') or o.get('provider')})" if o else ""
        print(fmt.format(r["provider"], t["5h"], t["day"], t["week"],
                         lim, otxt))
    return 0


def cmd_recommend(args):
    rec = recommend(args.provider)
    if args.json:
        print(json.dumps(rec, ensure_ascii=False))
    else:
        extra = (f" {rec['minutes_to_reset']}min"
                 if rec.get("minutes_to_reset") else "")
        print(f"{rec['action'].upper()}{extra} {rec['message']}")
    return rec["exit"]


def cmd_pick(args):
    if args.tiers:
        refs = args.tiers.split()
    elif args.tier:
        models = load_registry_models()
        cands = [m for m in models
                 if m.get("tier") == args.tier
                 and not any(d in (m.get("id_status") or "")
                             for d in DEAD_STATUS)]
        cands.sort(key=lambda m: m.get("accuracy") or 0, reverse=True)
        refs = [m["id"] for m in cands]
    else:
        print("usage-hub pick: use --tiers \"ref1 ref2\" ou --tier free",
              file=sys.stderr)
        return 3
    if not refs:
        print("usage-hub pick: lista de refs vazia", file=sys.stderr)
        return 3
    return pick(refs, as_json=args.json)


def cmd_observe(args):
    provider = canon_provider(args.provider) if args.provider else None
    if not provider and args.model_ref:
        provider = provider_of(args.model_ref)
    if not provider:
        print("usage-hub observe: --provider ou --model-ref obrigatório",
              file=sys.stderr)
        return 3
    OBS_PATH.parent.mkdir(parents=True, exist_ok=True)
    obs = {"epoch": time.time(),
           "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "provider": provider,
           "model": args.model_ref or "",
           "kind": args.kind,
           "message": args.message or "",
           "source": args.source or "manual"}
    with OBS_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obs, ensure_ascii=False) + "\n")
    print(f"observação gravada: {provider} {args.kind} → {OBS_PATH}",
          file=sys.stderr)
    return 0


def cmd_limits(args):
    data = load_json(LIMITS_PATH) or {"providers": {}, "wait_pct": 85}
    if args.set:
        prov, window, tokens = args.set
        if window not in WINDOWS:
            print(f"janela inválida: {window} (use {'/'.join(WINDOWS)})",
                  file=sys.stderr)
            return 3
        wins = data["providers"].setdefault(prov, {}).setdefault("windows", {})
        wins[window] = {"limit_tokens": (None if tokens in ("null", "none")
                                         else int(tokens))}
        LIMITS_PATH.write_text(
            json.dumps(data, ensure_ascii=False, indent=1) + "\n",
            encoding="utf-8")
        print(f"limite gravado: {prov}.{window} = {tokens} → {LIMITS_PATH}",
              file=sys.stderr)
        return 0
    print(json.dumps(data, ensure_ascii=False, indent=1))
    return 0


def main():
    ap = argparse.ArgumentParser(prog="usage-hub.py",
                                 description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("status")
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("recommend")
    p.add_argument("--provider", required=True)
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("pick")
    p.add_argument("--tiers", help="lista de model refs (formato DISPATCH_TIERS)")
    p.add_argument("--tier", help="tier do registry (free/paid/…)")
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("observe")
    # "hang": item/chamada estourou o teto do with-timeout (v3.5, triagem
    # fábrica-agentic §A3). Fora de BLOCK_KINDS de propósito: registra no
    # trail, não veta — a melhoria 1.2 (abort por transporte repetido)
    # decidirá com dados acumulados quando N hangs valem veto temporário.
    p.add_argument("--kind", required=True,
                   choices=["rate_limit", "balance", "key_limit", "hang", "ok"])
    p.add_argument("--provider")
    p.add_argument("--model-ref")
    p.add_argument("--message")
    p.add_argument("--source")

    p = sub.add_parser("limits")
    p.add_argument("--set", nargs=3, metavar=("PROVIDER", "JANELA", "TOKENS"))

    args = ap.parse_args()
    fn = {"status": cmd_status, "recommend": cmd_recommend,
          "pick": cmd_pick, "observe": cmd_observe, "limits": cmd_limits}
    sys.exit(fn[args.cmd](args))


if __name__ == "__main__":
    main()
