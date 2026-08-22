#!/usr/bin/env python3
"""check-export-mdx.py — oracle mecânico do stage export (content_factory).

Uso: check-export-mdx.py <arquivo.mdx>

Valida que o MDX publicado é um artigo de verdade:
  1. existe e tem >= 4000 bytes
  2. tem >= 1 link markdown para /produtos/ (CTA de afiliado)
  3. tem >= 2000 chars de prose FORA de code fences e frontmatter

Exit 0 = OK · 1 = conteúdo insuficiente · 2 = uso incorreto.

Nasceu do incidente 2026-08-11-export-perdeu-artigo-bundle-layout-novo:
post "só schema" de 2.4KB foi publicado e aprovado. Antes era python
inline no stage_oracle do YAML, mas o folding do bloco `>` colava as
linhas e quebrava a sintaxe (run 5F50DC24) — script separado é imune.
"""
import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("uso: check-export-mdx.py <arquivo.mdx>", file=sys.stderr)
        return 2

    p = Path(sys.argv[1])
    if not p.is_file() or p.stat().st_size == 0:
        print(f"EXPORT ORACLE FAIL: MDX ausente ou vazio: {p}")
        return 1

    raw = p.read_text(encoding="utf-8")
    size = len(raw.encode("utf-8"))
    if size < 4000:
        print(f"EXPORT ORACLE FAIL: tamanho {size} bytes < 4000")
        return 1

    if not re.search(r"\]\(/produtos/", raw):
        print("EXPORT ORACLE FAIL: nenhum link markdown para /produtos/")
        return 1

    prose = re.sub(r"```[\s\S]*?```", "", raw)
    prose = re.sub(r"^---[\s\S]*?---\n", "", prose, count=1)
    n = len(prose.strip())
    if n < 2000:
        print(f"EXPORT ORACLE FAIL: prose fora de fences {n} chars < 2000")
        return 1

    print(f"EXPORT ORACLE OK: {size} bytes, prose={n} chars")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
