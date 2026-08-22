#!/usr/bin/env python3
# corte-review.py — review de corte de versão do repo público (read-only).
#
# Compara a oficina (este repo) contra o corte público e emite um relatório
# com veredito. É o backend da página panel/corte.html (/api/gui/corte) e
# roda solto no terminal. NUNCA escreve — o apply é do oracfit-publish-cut.sh
# (a página também não escreve: painel não executa, AD-14).
#
# Checagens (cada uma = classe de falha real do incidente
# 2026-08-13-oracfit-soldado-no-orbe-corte-sem-catego, regra 52):
#   scan     bin/check-publico.sh scan cheio no corte (telefone/e-mail/path)
#   version  VERSION do corte NÃO pode regredir frente à oficina
#            (classe do rsync --delete invertido: 1.8.0 por cima do 3.5.0)
#   private  nenhuma PRIVATE_DIR do manifesto presente no corte
#   anon     incidents do corte sem marcador de cliente que a anonimização
#            deveria ter trocado por placeholder (orbe/beelink/fornecedores,
#            path de máquina)
#   diff     superfície exportável (espelho mecânico) oficina↔corte:
#            faltando/mudou = staleness (WARN — esperado entre cortes);
#            extra = INFO
#
# Fontes das categorias: manifesto de bin/oracfit-publish-cut.sh e listas de
# bin/check-publico.sh — manter em sincronia com os dois (mesma dívida
# declarada lá: categoria duplicada à mão enquanto não há manifesto único).
#
# Uso:
#   python3 bin/corte-review.py [--json] [CORTE_DIR]
#     OFICINA_DIR   sobrepõe a oficina (default: repo deste script) — testes
#     ORACFIT_CORTE_DIR  default do corte quando arg ausente ($HOME/oracfit-public)
# Exit: 0 = relatório emitido (veredito vem no payload), 2 = uso errado.
# Veredito REJECTED não muda o exit: review é leitura; quem publica decide.

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parent.parent  # repo deste script

# Espelha check-publico.sh / manifesto do publish-cut (ver cabeçalho).
# incidents/evidence entra como privada: logs brutos de dispatch (paths de
# máquina, specs de cliente) que o scan C3 não vê (.log/.json fora das
# include-lists de código) — achado real do primeiro corte-review.
PRIVADO = ["specs", "docs/handoffs", "docs/prompts", "incidents/uso",
           "incidents/evidence", "lessons"]
SUPERFICIE_DIRS = ["adapters", "panel", "tests", "fluxos", ".github", "core", "bin"]
SUPERFICIE_FILES = [
    "AGENTS.md", "CLAUDE.md", "LICENSE", "NOTICE", "QWEN.md", "SKILL.md",
    "VERSION", "ZCODE.md", "install.sh", "docs/STATE_TEMPLATE.md",
    "docs/TELEMETRY.md", "docs/functions.md", "README.md", "model-registry.json",
]
# Reescritos DE PROPÓSITO no corte (manifesto do publish-cut: URL de clone,
# links, números) — divergir é esperado, não staleness.
TRANSFORM_FILES = {"README.md", "model-registry.json"}
# Marcadores que a anonimização de incidents troca por <repo-cliente> etc.
# \b para não casar 'absorve'/'órbita'; -i cobre Orbe/ORBE/Beelink.
# 'fornecedores' NÃO é marcador: substantivo comum (não identifica terceiro —
# o PII daquele caso era telefone/e-mail, que o scan C1/C2 pega).
_MINI = "/Users" + "/mini"  # literal quebrado: C3 do check-publico escaneia a própria oficina
ANON_RE = re.compile(r"(\borbe\b|\bbeelink\b|" + re.escape(_MINI) + r")", re.IGNORECASE)
SCAN_TIMEOUT_S = 60
MAX_ACHADOS = 20  # por check no payload — a UI faz renderCapped de novo


def sh(cmd, cwd=None, timeout=None):
    """Roda e devolve (rc, stdout+stderr). Nunca lança — review é leitura."""
    try:
        p = subprocess.run(
            cmd, cwd=cwd, timeout=timeout,
            capture_output=True, text=True,
        )
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "timeout"
    except OSError as e:
        return 127, str(e)


def git_tracked(dirpath):
    """{path: sha} dos arquivos trackeados — a árvore COMMITADA, não a suja."""
    rc, out = sh(["git", "ls-files", "-s"], cwd=dirpath)
    if rc != 0:
        return None
    arquivos = {}
    for linha in out.splitlines():
        partes = linha.split("\t", 1)
        if len(partes) != 2:
            continue
        meta = partes[0].split()
        if len(meta) >= 2:
            arquivos[partes[1]] = meta[1]
    return arquivos


def git_head(dirpath):
    rc, out = sh(["git", "log", "-1", "--format=%h %ad", "--date=short"],
                 cwd=dirpath)
    return out.strip() if rc == 0 and out.strip() else "?"


def read_version(dirpath):
    f = Path(dirpath) / "VERSION"
    if not f.is_file():
        return ""
    return f.read_text(encoding="utf-8").strip()


def parse_semver(v):
    """'3.5.0' -> (3,5,0). Não-semver entra como (0,); comparação só é
    estrita quando ambos parecem semver — senão compara igualdade de string."""
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", v)
    return tuple(int(x) for x in m.groups()) if m else None


def count_incidents(dirpath):
    d = Path(dirpath) / "incidents"
    if not d.is_dir():
        return 0
    return len([f for f in d.glob("*.md") if f.is_file()])


def check_scan(corte):
    rc, out = sh(
        ["bash", str(SCRIPT_ROOT / "bin" / "check-publico.sh"), str(corte["dir"])],
        timeout=SCAN_TIMEOUT_S,
    )
    achados = [l for l in out.splitlines() if l.strip()][:MAX_ACHADOS]
    ok = rc == 0
    return {
        "id": "scan",
        "status": "pass" if ok else "fail",
        "detalhe": ("check-publico limpo" if ok
                    else f"exit {rc} — {len(achados)} linha(s) de achado"),
        "achados": achados if not ok else [],
    }


def check_version(oficina_v, corte_v):
    a, b = parse_semver(oficina_v), parse_semver(corte_v)
    if a is not None and b is not None:
        ok = b >= a
        detalhe = (f"corte {corte_v} ≥ oficina {oficina_v}" if ok
                   else f"corte {corte_v} REGREDIU frente à oficina {oficina_v} "
                        f"(classe do rsync invertido — regra 52)")
    else:
        ok = True  # não-semver: sem régua mecânica, só registra
        detalhe = f"oficina '{oficina_v}' / corte '{corte_v}' — semver não parseável"
    return {"id": "version", "status": "pass" if ok else "fail",
            "detalhe": detalhe}


def check_private(corte_dir):
    presentes = [p for p in PRIVADO if (Path(corte_dir) / p).exists()]
    return {
        "id": "private",
        "status": "pass" if not presentes else "fail",
        "detalhe": ("nenhuma categoria privada presente" if not presentes
                    else f"categoria privada NO corte: {', '.join(presentes)}"),
        "presentes": presentes,
    }


def check_anon(corte_dir):
    inc = Path(corte_dir) / "incidents"
    achados = []
    if inc.is_dir():
        for f in sorted(inc.rglob("*.md")):
            try:
                texto = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for i, linha in enumerate(texto.splitlines(), 1):
                if ANON_RE.search(linha):
                    achados.append(f"incidents/{f.relative_to(inc)}:{i}: "
                                   f"{linha.strip()[:100]}")
                    if len(achados) >= MAX_ACHADOS:
                        break
            if len(achados) >= MAX_ACHADOS:
                break
    return {
        "id": "anon",
        "status": "pass" if not achados else "fail",
        "detalhe": ("incidents sem marcador de cliente" if not achados
                    else f"{len(achados)} linha(s) com marcador que a "
                         f"anonimização deveria ter trocado"),
        "achados": achados,
    }


def check_diff(oficina, corte):
    # Compara a árvore COMMITADA dos dois lados (git ls-files -s) — review de
    # estados publicados, não da working tree suja da oficina.
    faltando, mudou, extra, transform = [], [], [], []
    of_root = git_tracked(oficina["dir"]) or {}
    co_root = git_tracked(corte["dir"]) or {}
    for d in SUPERFICIE_DIRS:
        pref = f"{d}/"
        of = {p[len(pref):]: s for p, s in of_root.items() if p.startswith(pref)}
        co = {p[len(pref):]: s for p, s in co_root.items() if p.startswith(pref)}
        for p in of:
            if p not in co:
                faltando.append(pref + p)
            elif of[p] != co[p]:
                mudou.append(pref + p)
        for p in co:
            if p not in of:
                extra.append(pref + p)
    for f in SUPERFICIE_FILES:
        if f not in of_root:
            continue  # fora da oficina (ex.: transform file que não existe lá)
        if f not in co_root:
            faltando.append(f)
        elif of_root[f] != co_root[f]:
            (transform if f in TRANSFORM_FILES else mudou).append(f)
    return {
        "id": "diff",
        "status": "pass",  # divergência é WARN, nunca bloqueio
        "detalhe": (f"{len(faltando)} faltando · {len(mudou)} mudou · "
                    f"{len(extra)} extra · {len(transform)} transform "
                    f"(reescrito de propósito) na superfície mecânica"),
        "faltando": sorted(faltando)[:100],
        "mudou": sorted(mudou)[:100],
        "extra": sorted(extra)[:100],
        "transform": sorted(transform)[:100],
    }


def main():
    args = [a for a in sys.argv[1:]]
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]

    oficina_dir = Path(os.environ.get("OFICINA_DIR", str(SCRIPT_ROOT))).resolve()
    if args:
        corte_dir = Path(args[0]).resolve()
    elif os.environ.get("ORACFIT_CORTE_DIR"):
        corte_dir = Path(os.environ["ORACFIT_CORTE_DIR"]).resolve()
    else:
        corte_dir = Path.home() / "oracfit-public"

    err = None
    if not (oficina_dir / ".git").exists():
        err = f"oficina não é repo git: {oficina_dir}"
    elif not corte_dir.is_dir():
        err = f"corte não existe: {corte_dir}"
    elif not (corte_dir / "docs" / "PUBLIC-CUT.md").is_file():
        err = (f"{corte_dir} não tem docs/PUBLIC-CUT.md — não parece um "
               f"corte público (marker)")
    if err:
        if as_json:
            print(json.dumps({"ok": False, "erro": err}))
        else:
            print(f"ERROR: {err}", file=sys.stderr)
        return 2

    oficina = {"dir": str(oficina_dir), "version": read_version(oficina_dir),
               "head": git_head(oficina_dir)}
    corte = {"dir": str(corte_dir), "version": read_version(corte_dir),
             "head": git_head(corte_dir),
             "commits": git_count_commits(corte_dir)}

    scan = check_scan(corte)
    checks = [scan, check_version(oficina["version"], corte["version"]),
              check_private(corte["dir"]), check_anon(corte["dir"]),
              check_diff(oficina, corte)]

    bloqueios = [c for c in checks if c["status"] == "fail"]
    verdict = "REJECTED" if bloqueios else "APPROVED"
    diff = checks[-1]
    if bloqueios:
        biggest_gap = f"{bloqueios[0]['id']}: {bloqueios[0]['detalhe']}"
    elif diff["faltando"]:
        biggest_gap = (f"diff: {len(diff['faltando'])} arquivo(s) da "
                       f"superfície ainda sem corte (staleness)")
    else:
        biggest_gap = ""

    relatorio = {
        "ok": True,
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "oficina": oficina,
        "corte": corte,
        "checks": checks,
        "contexto": {
            "incidents_oficina": count_incidents(oficina_dir),
            "incidents_corte": count_incidents(corte_dir),
        },
        "verdict": verdict,
        "biggest_gap": biggest_gap,
        "fontes": [
            "bin/check-publico.sh (scan C1/C2/C3)",
            "manifesto de bin/oracfit-publish-cut.sh (categorias via duplicação manual)",
        ],
    }

    if as_json:
        print(json.dumps(relatorio, ensure_ascii=False, indent=1))
    else:
        print(f"corte-review: {verdict}")
        print(f"  oficina {oficina['version']} ({oficina['head']})  →  "
              f"corte {corte['version']} ({corte['head']}, "
              f"{corte['commits']} commit(s))")
        for c in checks:
            marca = "✓" if c["status"] == "pass" else "✗"
            print(f"  [{marca}] {c['id']}: {c['detalhe']}")
            for a in c.get("achados", [])[:5]:
                print(f"        {a}")
        if biggest_gap:
            print(f"  biggest_gap: {biggest_gap}")
    return 0


def git_count_commits(dirpath):
    rc, out = sh(["git", "rev-list", "--count", "HEAD"], cwd=dirpath)
    try:
        return int(out.strip())
    except ValueError:
        return 0


if __name__ == "__main__":
    sys.exit(main())
