#!/usr/bin/env python3
"""check-oracle.py — separa "oráculo falha porque falta trabalho" de "oráculo
falha porque o comando está quebrado".

Uso: check-oracle.py <spec_file> <workdir> [--quiet] [--timeout N]

Exit: 0 = oráculo falha, e falha pelo motivo certo (é o que o gate quer ver)
      1 = oráculo JÁ PASSA antes do dispatch (não mede nada)
      2 = oráculo QUEBRADO — não passaria em nenhum estado do repo
      3 = erro de uso

Por que existe (medido em 2026-07-29, custo 1204s de modelo):

O gate do `bin/dispatch-batch.sh` exigia que o oráculo FALHASSE antes do
dispatch. Correto e insuficiente: exit≠0 tem duas causas e ele tratava as duas
como a mesma. O oráculo da spec `debranding-observability-classe-c.md` era

    grep -qE "(const\\|let) $n" src/metrics-registry.ts

Em ERE um pipe ESCAPADO é pipe LITERAL. O padrão procurava a string `const|let`,
que não existe em código TypeScript nenhum. O oráculo não podia passar em
NENHUM estado do repositório. O gate viu exit≠0, concluiu "falta trabalho", e
liberou o dispatch. Consequência em cascata: 3 tentativas do modelo, detector de
travamento disparando sobre entrada correta-mas-inútil, escalada para o tier
pago, e rollback desfazendo trabalho provavelmente bom. O executor acertou 3
vezes; o sensor reprovou 3 vezes.

Incidente: incidents/2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca.md

## O que este script NÃO faz, e por quê

A formulação que eu mesmo registrei como candidata — "exigir que cada padrão de
grep do oráculo case algo no workdir" — está ERRADA, e registrar isso importa
mais que o código. O oráculo mede trabalho que AINDA NÃO EXISTE: o padrão
`(const|let) ordersTotal` tem de não casar antes do dispatch. Exigir match
reprovaria todo oráculo correto e aprovaria só os inúteis. Seria trocar o falso
negativo por um falso positivo em 100% dos casos.

O que dá para medir é a DECOMPOSIÇÃO do padrão. Ele tem duas partes com estatuto
diferente:

  - o ALVO (`ordersTotal`) — é o trabalho; não casar é o esperado;
  - o ESQUELETO (`(const|let) `) — é vocabulário fixo da linguagem; existe em
    qualquer arquivo TypeScript, antes e depois do dispatch.

Se o esqueleto não casa, o padrão está quebrado (ou aponta para o arquivo
errado), e isso é verdade independente do trabalho. É a única parte do padrão
cujo match é exigível, e é exatamente a parte que o `\\|` destrói.

LIMITE DECLARADO (regra 32): o check de esqueleto só age quando TODOS os ramos de
um grupo de alternação estão no vocabulário fixo de KEYWORDS abaixo. Um oráculo
que quebre um grupo de alternação entre dois identificadores de negócio
(`(ordersTotal|cartActiveCount)`) passa por aqui sem ser julgado — não há como
distinguir "quebrado" de "ambos ainda não existem". O lint estático e a
classificação de stderr continuam valendo nesse caso.
"""
from __future__ import annotations

import re
import shlex
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

ORACLE_LINE = re.compile(r'^[-*]\s*comando:\s*(.+)$', re.I | re.M)
GREPS = {"grep", "egrep", "fgrep", "ggrep", "rg"}
SEPARATORS = {"&&", "||", ";", "|", "(", ")", "{", "}", "&", "\n",
              "do", "done", "then", "else", "elif", "fi", "esac"}

# Vocabulário FIXO da linguagem: palavra que existe no fonte independente do
# trabalho que o oráculo mede. Conservador de propósito — cada nome aqui é
# palavra-chave de JS/TS, Python ou shell, nunca identificador de negócio.
KEYWORDS = {
    "const", "let", "var", "function", "class", "export", "import", "interface",
    "type", "enum", "async", "await", "return", "extends", "implements", "new",
    "throw", "default", "from", "require", "def", "lambda", "if", "then",
    "else", "fi", "do", "done", "echo", "public", "private", "protected",
    "static", "readonly", "abstract", "declare", "namespace", "module",
}

# Marca de comando quebrado no stderr. Cada uma significa "o shell/utilitário
# não conseguiu RODAR", não "o repositório está no estado errado".
BROKEN_STDERR = [
    ("command not found", "comando não existe no PATH"),
    ("No such file or directory", "arquivo do oráculo não existe"),
    ("no such file or directory", "arquivo do oráculo não existe"),
    ("Invalid regular expression", "regex inválida"),
    ("invalid option", "flag inexistente"),
    ("illegal option", "flag inexistente"),
    ("unrecognized option", "flag inexistente"),
    ("syntax error", "sintaxe de shell inválida"),
    ("Unmatched", "quote ou parêntese desbalanceado"),
    ("unexpected EOF", "quote ou parêntese desbalanceado"),
    ("Permission denied", "sem permissão de execução"),
    ("is a directory", "alvo é diretório, não arquivo"),
]


def tokenize(cmd: str) -> list[str] | None:
    """Tokeniza tratando operadores de shell como tokens próprios.

    `punctuation_chars` é o que separa `exit 1;` em `exit`,`1`,`;` — sem isso o
    `;` cola no token anterior e a varredura perde o começo da invocação
    seguinte. Retorna None quando o comando não tokeniza: quote desbalanceado JÁ
    É comando quebrado, e vale reprovar antes de rodar qualquer coisa.
    """
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    try:
        return list(lex)
    except ValueError:
        return None


class Invocation:
    """Uma chamada de grep já resolvida: modo, padrão, arquivos, cwd."""

    def __init__(self, tool: str, cwd: Path):
        self.tool = tool
        self.cwd = cwd
        self.flags: list[str] = []
        self.pattern: str | None = None
        self.files: list[str] = []

    @property
    def ere(self) -> bool:
        if self.tool in ("egrep", "rg"):
            return True
        return any(f.startswith("-") and not f.startswith("--") and "E" in f[1:]
                   for f in self.flags) or "--extended-regexp" in self.flags

    @property
    def fixed(self) -> bool:
        if self.tool == "fgrep":
            return True
        return any(f.startswith("-") and not f.startswith("--") and "F" in f[1:]
                   for f in self.flags) or "--fixed-strings" in self.flags


def parse_invocations(tokens: list[str], workdir: Path) -> list[Invocation]:
    """Extrai as invocações de grep, rastreando o `cd` que muda o cwd.

    O `cd` importa: o oráculo típico começa com `cd packages/observability &&`, e
    testar o esqueleto contra o caminho errado daria um falso "quebrado".
    """
    out: list[Invocation] = []
    cwd = workdir
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok == "cd" and i + 1 < len(tokens):
            nxt = tokens[i + 1]
            if "$" not in nxt and nxt not in SEPARATORS:
                cand = (cwd / nxt).resolve() if not nxt.startswith("/") else Path(nxt)
                if cand.is_dir():
                    cwd = cand
            i += 2
            continue
        if tok in GREPS:
            inv = Invocation(tok, cwd)
            i += 1
            while i < len(tokens) and tokens[i] not in SEPARATORS:
                t = tokens[i]
                if t == "--":
                    i += 1
                    continue
                if t in ("-e", "--regexp", "-f", "--file"):
                    inv.flags.append(t)
                    if i + 1 < len(tokens):
                        if inv.pattern is None and t in ("-e", "--regexp"):
                            inv.pattern = tokens[i + 1]
                        i += 2
                        continue
                    i += 1
                    continue
                if t.startswith("-") and len(t) > 1:
                    inv.flags.append(t)
                elif inv.pattern is None:
                    inv.pattern = t
                else:
                    inv.files.append(t)
                i += 1
            out.append(inv)
            continue
        i += 1
    return out


def split_top_alternation(group: str) -> list[str]:
    """Ramos de alternação no nível de topo do grupo."""
    parts, depth, cur, k = [], 0, "", 0
    while k < len(group):
        c = group[k]
        if c == "\\" and k + 1 < len(group):
            cur += group[k:k + 2]
            k += 2
            continue
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        if c == "|" and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += c
        k += 1
    parts.append(cur)
    return parts


def groups(pattern: str) -> list[str]:
    """Conteúdo de cada grupo `(...)` do padrão, sem aninhar."""
    out, depth, start = [], 0, -1
    k = 0
    while k < len(pattern):
        c = pattern[k]
        if c == "\\":
            k += 2
            continue
        if c == "(":
            if depth == 0:
                start = k + 1
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0 and start >= 0:
                out.append(pattern[start:k])
        k += 1
    return out


def lint(inv: Invocation) -> list[str]:
    """Defeitos visíveis no padrão sem rodar nada."""
    p = inv.pattern
    if p is None:
        return []
    bad: list[str] = []

    if inv.ere and r"\|" in p:
        bad.append(
            f"padrão ERE com pipe ESCAPADO: `{p}`\n"
            f"       Em ERE `\\|` é pipe LITERAL, não alternação — este padrão "
            f"procura a string `|` dentro do texto.\n"
            f"       Use `(a|b)` sem barra, ou `-F` se o pipe é mesmo literal.")

    if inv.fixed and re.search(r'\([^)]*\|', p):
        bad.append(
            f"padrão de `-F` (busca literal) com alternação: `{p}`\n"
            f"       `-F` desliga regex: `(a|b)` é procurado como os 5 "
            f"caracteres `(a|b)`. Troque para `-E`.")

    if not inv.ere and not inv.fixed and "|" in p:
        bad.append(
            f"pipe em padrão BRE: `{p}`\n"
            f"       Sem `-E`, `|` é literal no BSD grep (macOS) e alternação só "
            f"com `\\|` no GNU — o mesmo oráculo dá resultados diferentes por "
            f"máquina. Use `-E` e pipe sem barra.")

    if inv.fixed and re.search(r'(?<!\\)\.\*|\\d|\[\^', p):
        bad.append(
            f"padrão de `-F` com metacaractere de regex: `{p}`\n"
            f"       `-F` procura os caracteres como estão. Troque para `-E`.")

    return bad


def skeleton_probe(inv: Invocation) -> list[str]:
    """Testa, no disco, os grupos de alternação puramente estruturais.

    Só age quando TODOS os ramos são KEYWORDS. Grupo assim casa em qualquer
    arquivo da linguagem, antes ou depois do trabalho — se não casa, o padrão
    está quebrado ou o arquivo é o errado. Grupo com identificador de negócio
    não é julgado: ali "não casa" é indistinguível de "ainda não existe".
    """
    p = inv.pattern
    if p is None or not inv.files:
        return []
    targets = [f for f in inv.files if "$" not in f and "*" not in f]
    if not targets:
        return []

    bad: list[str] = []
    for g in groups(p):
        branches = [b.strip() for b in split_top_alternation(g)]
        if len(branches) < 2:
            # `\|` não produz ramos: split_top_alternation ignora o escapado, de
            # propósito. Reconstrói os ramos para MEDIR o que o lint já viu.
            if r"\|" in g:
                branches = [b.strip() for b in g.split(r"\|")]
            else:
                continue
        if not all(b and b.lower() in KEYWORDS for b in branches):
            continue

        for f in targets:
            path = inv.cwd / f
            if not path.is_file():
                bad.append(
                    f"esqueleto `({g})` aponta para arquivo que não existe: "
                    f"{path}\n"
                    f"       O oráculo falha pelo caminho, não pelo trabalho.")
                continue
            # Mede o grupo COMO ESCRITO, e só então a forma canônica. A ordem é o
            # ponto: o veredito útil não é "não casa", é "a sua forma não casa e
            # a canônica casa" — isso localiza o defeito no padrão, não no repo.
            orig = "(" + g + ")"
            probe = "(" + "|".join(branches) + ")"
            if subprocess.run(["grep", "-qE", orig, str(path)],
                              capture_output=True, timeout=60).returncode == 0:
                continue
            canon_ok = subprocess.run(["grep", "-qE", probe, str(path)],
                                      capture_output=True, timeout=60).returncode == 0
            if canon_ok:
                bad.append(
                    f"esqueleto não casa como está escrito, mas casa na forma "
                    f"canônica, em {f}:\n"
                    f"       `grep -qE '{orig}' {f}` → não casa\n"
                    f"       `grep -qE '{probe}' {f}` → casa\n"
                    f"       O defeito está no padrão, não no repositório.")
            else:
                bad.append(
                    f"esqueleto `{orig}` não casa NADA em {f}.\n"
                    f"       Vocabulário fixo da linguagem tem de casar em "
                    f"qualquer estado do repo — antes e depois do trabalho. "
                    f"Padrão quebrado, ou arquivo errado.")
    return bad


def run_oracle(cmd: str, workdir: Path, secs: int) -> tuple[int, str]:
    """Roda o oráculo com teto que mata a árvore de processos (regra 12/21)."""
    r = subprocess.run(
        ["bash", str(REPO_ROOT / "bin" / "with-timeout.sh"), str(secs),
         "bash", "-c", cmd],
        cwd=workdir, capture_output=True, text=True, errors="replace",
    )
    return r.returncode, r.stderr


# Paths ausentes citados no stderr. Cobre a exceção do Python (open() de
# arquivo-alvo) e o formato `utilitário: path: No such file...` do grep/cat.
MISSING_PATH_RES = [
    re.compile(r"FileNotFoundError: \[Errno 2\] No such file or directory: '([^']+)'"),
    re.compile(r"(?:^|:\s)([^:\n]+): No such file or directory", re.M),
]


def missing_work_paths(err: str, workdir: Path) -> list[str]:
    """Paths ausentes do stderr que são consistentes com "trabalho ainda não
    criado": resolvem para DENTRO do workdir e de fato não existem.

    Incidente 2026-08-11-check-oracle-trata-arquivo-de-saida-inexistente-como-
    quebrado: oráculo `python3 -c "...open('data/.../out.json')..."` levanta
    FileNotFoundError ANTES do dispatch porque o arquivo é o que o modelo vai
    CRIAR — estado pré-dispatch esperado da task de criação (o caso mais comum
    do projeto), análogo ao grep que ainda não casa. 20 de 21 dispatches de um
    batch foram bloqueados com exit=2 por isso. Path fora do workdir continua
    sendo tratado como oráculo quebrado (typo de caminho, dependência ausente).
    """
    wd = workdir.resolve()
    hits: list[str] = []
    for rx in MISSING_PATH_RES:
        for p in rx.findall(err):
            p = p.strip()
            cand = Path(p) if p.startswith("/") else workdir / p
            try:
                inside = cand.resolve().is_relative_to(wd)
            except (OSError, ValueError):
                continue
            if inside and not cand.exists():
                hits.append(p)
    return hits


def classify_stderr(err: str) -> list[str]:
    hits = []
    for needle, why in BROKEN_STDERR:
        if needle in err:
            line = next((l.strip() for l in err.splitlines() if needle in l), needle)
            hits.append(f"{why}: {line[:200]}")
    return hits


def main() -> int:
    argv = sys.argv[1:]
    quiet = "--quiet" in argv
    # Auditar uma spec já despachada sem pagar `tsc`/`vitest` de novo. Existe
    # para medir falso positivo do lint em lote — a medição do próprio mecanismo
    # tem de ser barata, ou não é feita.
    static_only = "--static-only" in argv
    timeout = 600
    args: list[str] = []
    i = 0
    while i < len(argv):
        if argv[i] in ("--quiet", "--static-only"):
            i += 1
        elif argv[i] == "--timeout":
            if i + 1 >= len(argv):
                print("--timeout requer segundos", file=sys.stderr)
                return 3
            timeout = int(argv[i + 1]); i += 2
        else:
            args.append(argv[i]); i += 1

    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 3
    spec, workdir = Path(args[0]), Path(args[1])
    if not spec.is_file():
        print(f"spec não encontrada: {spec}", file=sys.stderr)
        return 3
    if not workdir.is_dir():
        print(f"workdir não é diretório: {workdir}", file=sys.stderr)
        return 3

    m = ORACLE_LINE.search(spec.read_text(encoding="utf-8"))
    if not m:
        print(f"❌ {spec.name}: sem linha `- comando:` no bloco Oráculo",
              file=sys.stderr)
        return 3
    cmd = m.group(1).strip().strip("`").strip()

    problems: list[str] = []

    # ── estático ────────────────────────────────────────────────────────────
    tokens = tokenize(cmd)
    if tokens is None:
        print(f"❌ {spec.name}: oráculo não tokeniza — quote ou parêntese "
              f"desbalanceado.", file=sys.stderr)
        return 2

    for inv in parse_invocations(tokens, workdir):
        problems += lint(inv)
        problems += skeleton_probe(inv)

    if problems:
        print(f"❌ {spec.name}: oráculo QUEBRADO — não passaria em nenhum estado "
              f"do repositório:", file=sys.stderr)
        for p in problems:
            print(f"   - {p}", file=sys.stderr)
        print("   exit≠0 aqui não prova trabalho faltando. Conserte o oráculo "
              "ANTES de chamar modelo "
              "(incidents/2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca.md).",
              file=sys.stderr)
        return 2

    if static_only:
        if not quiet:
            print(f"✅ {spec.name}: sem defeito estático de padrão "
                  f"(--static-only: oráculo NÃO foi executado)")
        return 0

    # ── execução ────────────────────────────────────────────────────────────
    code, err = run_oracle(cmd, workdir, timeout)

    if code == 0:
        print(f"❌ {spec.name}: oráculo JÁ PASSA antes do dispatch — não mede "
              f"nada.", file=sys.stderr)
        return 1

    if code == 124:
        print(f"❌ {spec.name}: oráculo estourou {timeout}s. Oráculo sem teto "
              f"próprio segura o lote inteiro.", file=sys.stderr)
        return 2

    # exit 127 é invocação quebrada (comando inexistente, ou crase virando
    # substituição — regra 46), nunca falta de trabalho. Vem em via própria
    # porque pode chegar com stderr VAZIO (medido no overnight de 2026-08-10:
    # 3 ciclos mortos com rc=127 sem mensagem) — o classificador de stderr
    # não teria o que casar. Incidente 2026-08-10-backtick-no-comando-do-
    # oraculo-vira-substituicao-e-127.
    if code == 127:
        print(f"❌ {spec.name}: oráculo saiu com exit 127 — comando não "
              f"encontrado ou substituição de comando quebrada (crase na "
              f"linha `- comando:`? regra 46). Invocação quebrada, não "
              f"trabalho faltando.", file=sys.stderr)
        return 2

    broken = classify_stderr(err)
    if broken:
        # Incidente 2026-08-11-check-oracle-trata-arquivo-de-saida-inexistente:
        # se TODO o "quebrado" se resume a arquivo ausente, e todo path ausente
        # citado resolve para dentro do workdir, isso é o estado pré-dispatch
        # esperado de task de criação — falha pelo motivo certo, com aviso.
        fnf_only = all("arquivo do oráculo não existe" in b for b in broken)
        work_missing = missing_work_paths(err, workdir)
        if fnf_only and work_missing:
            if not quiet:
                print(f"✅ {spec.name}: oráculo falha (exit {code}) porque o "
                      f"arquivo-alvo ainda não existe ({', '.join(work_missing[:3])}) "
                      f"— falta de trabalho, não oráculo quebrado.")
                print(f"   dica: prefira `test -f <alvo> && …` na frente da "
                      f"validação de conteúdo — falha limpa, sem traceback.")
            return 0
        print(f"❌ {spec.name}: oráculo falhou por ERRO DE COMANDO, não por "
              f"trabalho faltando:", file=sys.stderr)
        for b in broken:
            print(f"   - {b}", file=sys.stderr)
        return 2

    if not quiet:
        print(f"✅ {spec.name}: oráculo falha (exit {code}) e falha pelo motivo "
              f"certo — sem defeito de padrão, sem erro de comando.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
