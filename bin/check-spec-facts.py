#!/usr/bin/env python3
"""check-spec-facts.py — confere se o bloco "Dados verificados" da spec é VERDADE.

Uso: check-spec-facts.py <spec_file> <workdir> [--quiet]

Por que existe (medido em 2026-07-29):

`bin/check-spec.sh` detecta AUSÊNCIA de cláusula anti-invenção. Não detecta
DADO FALSO — o bloco "Dados verificados" é aceito por fé. Na spec
`specs/dedupe-observability-leadher.md` o orquestrador escreveu:

    Em `apps/backend/vitest.config.ts` existe o glob
    `src/observability/**/__tests__/**/*.test.ts`. Remover essa entrada.

O glob existe, mas em OUTRO repo (`<repo-cliente>.live-imports`), não no alvo
(`leadher.living`). A spec passou nos 5 checks do `check-spec.sh` e foi
despachada. O modelo se comportou melhor que o gate: não inventou o glob, foi
olhar, não achou, e disse. O gate não olhou nada.

A ironia é o ponto: a spec proibia o MODELO de inventar e o framework não tinha
nada que proibisse o ORQUESTRADOR. Cláusula é para quem lê a spec; este script
é para quem a escreve.

O que faz: coleta literais entre backticks em DOIS lugares e exige que cada um
exista no workdir — como arquivo, ou como texto dentro de arquivo rastreado:

  1. A seção "Dados verificados" inteira. Por definição, ela é afirmação sobre
     o estado ATUAL.
  2. Qualquer frase, em qualquer seção, que AFIRME existência ("existe", "já
     declara", "hoje", "atualmente", "tem N linhas"...). Uma afirmação de fato
     não deixa de ser factual por estar sob "O que fazer".

O item 2 é o que faltava na primeira versão deste script, e a prova está na
própria história dele: a versão que só olhava "Dados verificados" NÃO pegou o
defeito que a motivou, porque a frase do glob estava sob `## O que fazer`. O
mecanismo tinha o formato certo e o escopo errado.

Literal em frase imperativa ("crie `x.ts`") continua livre — é o que o modelo
vai produzir, não uma afirmação sobre o presente.

Use `--also DIR` para citações legítimas a outro repo (ex.: comparar com o fonte
do framework). Literal encontrado em qualquer DIR extra é aceito.

LIMITE DECLARADO (regra 32): prova que o literal EXISTE em algum lugar do
workdir, não que esteja no arquivo/linha que a spec afirma. Uma spec que cite o
literal certo atribuído ao arquivo errado passa aqui se o literal existir em
outro arquivo do mesmo repo. Pega o caso medido (literal ausente do repo
inteiro), não atribuição trocada dentro do repo.

Exit: 0 = todo literal confere, 1 = algum literal não existe no workdir,
      3 = erro de uso ou seção ausente
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

SECTION = re.compile(
    r'^#{1,6}[^\n]*dados\s+verificados[^\n]*$(.*?)(?=^#{1,6}\s|\Z)',
    re.I | re.M | re.S,
)
BACKTICK = re.compile(r'`([^`\n]+)`')

# Frase que AFIRMA o presente. Cada verbo aqui apareceu numa spec real deste
# repo afirmando estado — e é afirmação de fato, não instrução.
CLAIM = re.compile(
    r'\b(existe|existem|já\s+(declara|existe|aponta|consome|importa|há)|'
    r'hoje|atualmente|não\s+existe|tem\s+\d|contém|aponta\s+para|'
    r'está\s+em|ficaram|continua)\b', re.I)

# Literais que não valem checar: prosa curta, comandos de shell, nome de campo
# JSON, número solto. Cada exclusão aqui é uma fonte de falso positivo medida.
SKIP_EXACT = {"main", "dist", "src", "exports", "main:", "types", "declare const",
              "as any", "@ts-ignore", "node_modules", "tsc --noEmit", "--lockfile-only"}
SHELLISH = re.compile(r'^(npx|pnpm|npm|node|git|bash|python3|test|grep|cd|rm|docker)\b')


def tracked_files(workdir: Path) -> list[Path]:
    """Arquivos rastreados MAIS não rastreados não ignorados.

    Os `--others --exclude-standard` importam: um arquivo recém-criado nesta
    mesma sessão (o próprio `bin/check-spec-facts.py`, na primeira vez que uma
    spec o citou) ainda é untracked. Só `git ls-files` o deixaria invisível, e o
    checker reprovaria a spec por citar algo que existe no disco.
    """
    out = ""
    for args in (["git", "ls-files", "-z"],
                 ["git", "ls-files", "-zo", "--exclude-standard"]):
        try:
            out += subprocess.run(
                args, cwd=workdir, capture_output=True, text=True,
                timeout=60, check=True,
            ).stdout
        except (subprocess.SubprocessError, OSError):
            continue
    return [workdir / p for p in out.split("\0") if p]


def literal_present(lit: str, workdir: Path, files: list[Path]) -> bool:
    # 1. É um caminho que existe?
    cand = lit.split(":", 1)[0].strip()
    if cand and (workdir / cand).exists():
        return True
    # 1b. Nome de arquivo solto (`request-context.ts`) casa por basename. Sem
    #     isso, citar um arquivo pelo nome curto — como toda spec faz — dava
    #     falso positivo.
    if "/" not in cand and files and any(f.name == cand for f in files):
        return True
    # 2. Aparece como texto em algum arquivo rastreado? `grep -rF` do git é o
    #    caminho rápido; ele respeita .gitignore e não varre node_modules.
    try:
        # --untracked: mesmo motivo do tracked_files(). Sem isso, literal que só
        # existe em arquivo novo dá falso positivo.
        r = subprocess.run(
            ["git", "grep", "--untracked", "-qF", "--", lit], cwd=workdir,
            capture_output=True, timeout=120,
        )
        if r.returncode == 0:
            return True
    except (subprocess.SubprocessError, OSError):
        pass
    # 3. Fallback sem git (workdir não versionado): varredura direta.
    if not files:
        for f in workdir.rglob("*"):
            if not f.is_file() or "node_modules" in f.parts or ".git" in f.parts:
                continue
            try:
                if lit in f.read_text(encoding="utf-8", errors="ignore"):
                    return True
            except OSError:
                continue
    return False


def interesting(lit: str) -> bool:
    """Vale conferir este literal contra o disco?

    Cada exclusão abaixo é um falso positivo MEDIDO nas 4 specs deste lote, não
    uma precaução hipotética. A regra que as une: só é conferível o literal que
    o autor afirma estar no disco *como está escrito*.
    """
    lit = lit.strip()
    if len(lit) < 6 or lit in SKIP_EXACT or SHELLISH.match(lit):
        return False
    # prosa: 4+ palavras sem nenhum caractere de código
    if lit.count(" ") >= 3 and not re.search(r'[/@._*(){}\[\]:=]', lit):
        return False
    if re.fullmatch(r'[\d\s.,%-]+', lit):
        return False
    # 1. Elipse do autor: `vi.mock("...", ...)`. O `...` é dele, não do arquivo.
    if "..." in lit or "…" in lit:
        return False
    # 2. Nome de teste na notação do vitest, `describe > it`. Existe na SAÍDA do
    #    runner, nunca como texto no fonte.
    if " > " in lit:
        return False
    # 3. Glob de prosa: `tsconfig*.json`, `*.tsx`. Curinga em nome de arquivo
    #    SEM diretório é abreviação do autor. Glob COM diretório
    #    (`src/x/**/*.test.ts`) é valor de config e existe literal — foi
    #    justamente o defeito que motivou este script, então não pode cair aqui.
    if "*" in lit and "/" not in lit:
        return False
    # 4. Moldura de saída de terminal (`── seção ──`): é formatada por f-string,
    #    não existe literal no fonte.
    if lit.startswith("──") or lit.startswith("==="):
        return False
    return True


def unwrap(md: str) -> str:
    """Desfaz dobra de linha DENTRO do parágrafo, preservando linha vazia.

    Sem isto o split de frases quebrava na dobra e separava o verbo do literal:
    a linha `... existe o glob` ia para um pedaço e
    `` `src/observability/**/...` `` para o seguinte, então nenhuma "frase"
    continha os dois. Foi exatamente por isso que a primeira versão deste
    script deu VERDE na spec defeituosa que o motivou.
    """
    return re.sub(r'(?<!\n)\n(?![\n\s*\-#|`])[ \t]*', ' ', md)


def claim_literals(text: str, skip: str) -> dict[str, str]:
    """literal -> frase que o afirma. Ignora o que já veio da seção."""
    out: dict[str, str] = {}
    flat = unwrap(text)
    skip_flat = unwrap(skip)
    for sent in re.split(r'(?<=[.:;])\s+|\n{2,}', flat):
        if not sent or not CLAIM.search(sent):
            continue
        if sent in skip_flat:
            continue  # já coberta pela seção 'Dados verificados'
        for lit in BACKTICK.findall(sent):
            lit = lit.strip()
            if interesting(lit):
                out.setdefault(lit, " ".join(sent.split())[:110])
    return out


def main() -> int:
    argv = sys.argv[1:]
    quiet = "--quiet" in argv
    also: list[Path] = []
    args: list[str] = []
    i = 0
    while i < len(argv):
        if argv[i] == "--quiet":
            i += 1
        elif argv[i] == "--also":
            if i + 1 >= len(argv):
                print("--also requer DIR", file=sys.stderr)
                return 3
            also.append(Path(argv[i + 1])); i += 2
        else:
            args.append(argv[i]); i += 1

    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 3
    spec, workdir = Path(args[0]), Path(args[1])
    if not spec.is_file():
        print(f"spec não encontrada: {spec}", file=sys.stderr)
        return 3
    for d in [workdir, *also]:
        if not d.is_dir():
            print(f"não é diretório: {d}", file=sys.stderr)
            return 3

    text = spec.read_text(encoding="utf-8")
    m = SECTION.search(text)
    if not m:
        print(f"spec sem seção 'Dados verificados': {spec}", file=sys.stderr)
        return 3

    # origem de cada literal, para a mensagem de erro apontar onde corrigir
    origem: dict[str, str] = {}
    for lit in BACKTICK.findall(m.group(1)):
        lit = lit.strip()
        if interesting(lit):
            origem.setdefault(lit, "seção 'Dados verificados'")
    for lit, sent in claim_literals(text, m.group(1)).items():
        origem.setdefault(lit, f'afirmação: "{sent}"')

    if not origem:
        if not quiet:
            print(f"⚠️  nenhum literal conferível em {spec.name}")
        return 0

    dirs = [workdir, *also]
    cache = {d: tracked_files(d) for d in dirs}
    missing = [l for l in origem
               if not any(literal_present(l, d, cache[d]) for d in dirs)]

    if missing:
        print(f"❌ {spec.name}: literal afirmado como EXISTENTE que não está em "
              f"{workdir}" + (f" nem em {', '.join(map(str, also))}" if also else "")
              + ":", file=sys.stderr)
        for l in missing:
            print(f"   - `{l}`", file=sys.stderr)
            print(f"     vindo de {origem[l]}", file=sys.stderr)
        print("   Afirmação sobre o presente é dado verificável. Corrija a spec, "
              "aponte --also pro repo certo, ou reescreva como instrução.",
              file=sys.stderr)
        return 1

    if not quiet:
        print(f"✅ {spec.name}: {len(origem)} literal(is) afirmado(s) como existentes "
              f"conferem em {workdir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
