#!/usr/bin/env python3
"""check-english.py — code, identifiers, comments and messages are written in English.

llms.surf is open source and its contributors are international, so a Portuguese variable name or a
comment in Portuguese is a barrier for whoever forks the project. The rule is in AGENTS.md
("Language"); this script is how it is enforced.

By default it checks only the lines a branch ADDS compared to a base (origin/main), so the existing
Portuguese debt does not block anyone; that debt is removed by the planned rename
(docs/english-refactor-plan.md). `--all` reports the debt of the whole tree.

A line is flagged when, in a code file, it has:
  - an accented Latin letter (a with acute, c with cedilla, ...) — Portuguese text or a non-ASCII identifier; or
  - a word from the Portuguese deny-list below, also inside snake_case / camelCase / kebab-case names.

Escape hatches, for the few places that must read Portuguese input (e.g. spec headings that the
gate still parses): `english-ok` on the line, or `english-ok-begin` ... `english-ok-end` around a
block. Paths that stay in Portuguese on purpose are in EXEMPT_PREFIXES.

Usage: bin/check-english.py [--base REF] [--all] [paths...]
Exit: 0 clean · 1 violations · 3 usage error (bad base ref, not a git repo)
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

CODE_SUFFIXES = {".py", ".sh", ".bash", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".css",
                 ".html", ".yaml", ".yml", ".toml", ".json", ".sql"}
SHEBANG = re.compile(rb"^#!.*\b(bash|sh|python3?|node)\b")

# Kept in Portuguese on purpose: historical records, test data that reproduces real Portuguese specs,
# blog posts written for Portuguese readers,
# translation files, and dispatch specs that were already sent (they are what the executor received).
EXEMPT_PREFIXES = ("incidents/", "tests/fixtures/", "docs/stories/", "logs/", "locales/", "site/blog/",
                   "gui/locales/")

LATIN_ACCENTED = "\u00c0-\u00d6\u00d8-\u00f6\u00f8-\u00ff"
ACCENTED = re.compile(f"[{LATIN_ACCENTED}]")

# english-ok-begin: the deny-list is Portuguese by definition
# Words that are Portuguese and not English, written without accents (identifiers rarely carry them).
# Only add words that cannot be an English word or a common abbreviation.
DENY = {
    "acao", "acoes", "agora", "ainda", "ajuda", "antes", "aqui", "arquivo", "arquivos", "aviso",
    "caminho", "catalogo", "chave", "conta", "contexto", "custo", "custos", "dados", "delegacao",
    "delegar", "demanda", "depois", "despachar", "despacho", "diretorio", "direto", "dono",
    "entao", "entrada", "entrega", "entregas", "entregaveis", "erro", "erros", "esse", "esta",
    "este", "falha", "falhas", "falhou", "feito", "fila", "isso", "linha", "linhas", "mensagem",
    "modelo", "modelos", "motivo", "nao", "nenhum", "nome", "orcamento", "orquestrador", "painel",
    "passo", "passos", "passou", "pasta", "placa", "porque", "preco", "precos", "quando", "regra",
    "regras", "resultado", "retomada", "rotulo", "saida", "saude", "sucesso", "tambem", "tarefa",
    "tarefas", "tentativa", "tentativas", "todos", "trocar", "trocador", "usuario", "valor",
    "veredito", "verificacao", "verificar", "voce",
}
# Names of interfaces that already exist (CLI subcommands, routes, headers, file names). New code has
# to call them until docs/english-refactor-plan.md phase 1 renames them; that phase empties this set.
LEGACY_NAMES = {"acao", "acoes", "adiar", "delegar", "feito", "painel", "saude"}
# english-ok-end
MARK = "english-ok"
WORD = re.compile(f"[A-Za-z{LATIN_ACCENTED}]+")
CAMEL = re.compile("[A-Z]?[a-z\u00df-\u00f6\u00f8-\u00ff]+|[A-Z]+(?![a-z])")


def fail(code, message):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def is_code(path, root):
    p = Path(path)
    if any(path.startswith(e) for e in EXEMPT_PREFIXES):
        return False
    if p.suffix in CODE_SUFFIXES:
        return True
    if p.suffix:
        return False
    try:
        with open(root / p, "rb") as f:
            return bool(SHEBANG.match(f.readline()))
    except OSError:
        return False


def words(line):
    for token in WORD.findall(line):
        for part in CAMEL.findall(token) or [token]:
            yield part.lower()


def problems(line):
    found = []
    m = ACCENTED.search(line)
    if m:
        found.append(f"non-English letter '{m.group()}'")
    hits = sorted({w for w in words(line) if w in DENY and w not in LEGACY_NAMES})
    if hits:
        found.append("Portuguese word(s): " + ", ".join(hits))
    return found


def scan(path, lines):
    """lines: iterable of (line_no, text) in file order. Yields (line_no, text, problems)."""
    skipping = False
    for no, text in lines:
        opens, closes = f"{MARK}-begin" in text, f"{MARK}-end" in text
        if opens and not closes:
            skipping = True
        elif closes and not opens:
            skipping = False
            continue
        if skipping or MARK in text:
            continue
        found = problems(text)
        if found:
            yield no, text, found


def added_lines(base, root, only):
    """{path: {line numbers added by the branch}}. The caller scans whole files and keeps only these
    lines, so an english-ok-begin/end block opened on an unchanged line still applies."""
    fork = git("-C", str(root), "merge-base", base, "HEAD")
    if fork.returncode != 0:
        fail(3, f"check-english: cannot find where this branch left '{base}': {fork.stderr.strip()}")
    # Against the working tree, so uncommitted edits are checked too (usable before a commit).
    diff = git("-C", str(root), "diff", "--unified=0", "--no-color", "--diff-filter=AMR", "--src-prefix=a/", "--dst-prefix=b/",
               fork.stdout.strip(), "--", *only)
    if diff.returncode != 0:
        fail(3, f"check-english: git diff failed: {diff.stderr.strip()}")
    added, path, line_no = {}, None, 0
    for raw in diff.stdout.splitlines():
        if raw.startswith("+++ "):
            path = raw[6:] if raw.startswith("+++ b/") else None
            continue
        if raw.startswith("@@"):
            line_no = int(re.match(r"@@ -\S+ \+(\d+)", raw).group(1))
            continue
        if path and raw.startswith("+"):
            added.setdefault(path, set()).add(line_no)
            line_no += 1
    untracked = git("-C", str(root), "ls-files", "--others", "--exclude-standard", "--", *only)
    for path in untracked.stdout.splitlines():
        added[path] = None  # a new file: every line is added
    return added


def main():
    ap = argparse.ArgumentParser(prog="check-english")
    ap.add_argument("--base", default="origin/main", help="compare against this ref (default origin/main)")
    ap.add_argument("--all", action="store_true", help="scan whole files, not only added lines")
    ap.add_argument("paths", nargs="*", help="limit to these paths")
    args = ap.parse_args()
    top = git("rev-parse", "--show-toplevel")
    if top.returncode != 0:
        fail(3, "check-english: not inside a git repository")
    root = Path(top.stdout.strip())

    if args.all:
        listed = git("-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard",
                     "--", *args.paths).stdout.splitlines()
        targets = {p: None for p in listed}
    else:
        targets = added_lines(args.base, root, args.paths)

    total = 0
    for path in sorted(targets):
        if not is_code(path, root):
            continue
        try:
            text = (root / path).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        wanted = targets[path]
        for no, line, found in scan(path, enumerate(text, 1)):
            if wanted is not None and no not in wanted:
                continue
            total += 1
            print(f"{path}:{no}: {'; '.join(found)}\n    {line.strip()[:160]}")
    if total:
        scope = "in the whole tree" if args.all else f"added since {args.base}"
        print(f"\ncheck-english: {total} line(s) not in English {scope}. Code, identifiers, comments and "
              f"messages must be English (AGENTS.md, \"Language\"). If a line must read Portuguese input, "
              f"mark it with '{MARK}' and say why.", file=sys.stderr)
        raise SystemExit(1)
    print("check-english: ok")


if __name__ == "__main__":
    main()
