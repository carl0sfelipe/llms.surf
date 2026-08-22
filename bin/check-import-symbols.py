#!/usr/bin/env python3
"""check-import-symbols.py — prova que todo símbolo importado de um pacote é
realmente exportado por ele, LENDO O FONTE do pacote. Sem node_modules.

Uso: check-import-symbols.py <dir_consumidor> <especificador> <dir_fonte_do_pacote>

Exemplo:
  check-import-symbols.py apps/backend/src @carl0sfelipe/observability \\
      ~/medusa-br-framework/packages/observability/src

Por que existe: um repo sem `node_modules` não tem `tsc` nem `vitest`, e sem
compilador o oráculo de uma migração de import viraria `grep -c '../local' = 0`
— que passa se o modelo trocar o caminho morto por OUTRO caminho morto, ou se
errar o nome do símbolo (`orbeCartActiveCounts`). Este script fecha essa
lacuna: compara o CONJUNTO de símbolos importados com o CONJUNTO de símbolos
reexportados pelo index do pacote.

LIMITE (regra 32 — declare o mecanismo, não exagere): isto NÃO substitui o
compilador. Não confere tipo, aridade, nem `export *` encadeado em mais de um
nível. Prova só uma propriedade: nome importado existe na lista de exports.

Exit: 0 = todo símbolo existe, 1 = algum símbolo não é exportado, 3 = erro de uso
"""
import re
import sys
from pathlib import Path

TS = ("*.ts", "*.tsx", "*.mts", "*.cts")

# import { a, b as c } from "spec"   /   import type { a } from "spec"
NAMED_IMPORT = re.compile(
    r'import\s+(?:type\s+)?\{([^}]*)\}\s*from\s*["\']%s["\']', re.S
)
# export { a, b } from "./x"  /  export const a  /  export function a  /  export class a
EXPORT_NAMED = re.compile(r'export\s+(?:type\s+)?\{([^}]*)\}', re.S)
EXPORT_DECL = re.compile(
    r'export\s+(?:declare\s+)?(?:async\s+)?'
    r'(?:const|let|var|function|class|interface|type|enum)\s+([A-Za-z_$][\w$]*)'
)


def files(root: Path):
    for pat in TS:
        yield from root.rglob(pat)


def imported_symbols(consumer: Path, spec: str) -> dict[str, list[str]]:
    """símbolo -> arquivos que o importam"""
    pattern = re.compile(
        NAMED_IMPORT.pattern % re.escape(spec), re.S
    )
    found: dict[str, list[str]] = {}
    for f in files(consumer):
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for block in pattern.findall(text):
            for raw in block.split(","):
                name = raw.strip().split(" as ")[0].strip()
                if not name:
                    continue
                found.setdefault(name, []).append(str(f))
    return found


def exported_symbols(pkg_src: Path) -> set[str]:
    """Superfície pública do pacote.

    Prefere o `index.ts`: é ele que o `exports` do package.json aponta, e um
    símbolo exportado de um arquivo interno que o index NÃO reexporta é
    inalcançável para quem importa `@escopo/pacote`. Aceitar esses nomes
    tornaria o check permissivo justamente no erro mais provável.

    Só cai no varredura-geral quando o index usa `export *`, que este script
    não resolve (limite declarado).
    """
    index = pkg_src / "index.ts"
    if index.is_file():
        text = index.read_text(encoding="utf-8")
        if "export *" not in text:
            names = {
                raw.strip().split(" as ")[-1].strip()
                for block in EXPORT_NAMED.findall(text)
                for raw in block.split(",")
            }
            names.update(EXPORT_DECL.findall(text))
            names.discard("")
            if names:
                return names

    names: set[str] = set()
    for f in files(pkg_src):
        # __tests__ não faz parte da superfície pública
        if "__tests__" in f.parts:
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for block in EXPORT_NAMED.findall(text):
            for raw in block.split(","):
                name = raw.strip().split(" as ")
                # `export { a as b }` publica b, não a
                names.add(name[-1].strip())
        names.update(EXPORT_DECL.findall(text))
    names.discard("")
    return names


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 3
    consumer, spec, pkg_src = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    for p in (consumer, pkg_src):
        if not p.is_dir():
            print(f"não é diretório: {p}", file=sys.stderr)
            return 3

    imports = imported_symbols(consumer, spec)
    if not imports:
        print(f"nenhum import nomeado de '{spec}' em {consumer}", file=sys.stderr)
        return 1

    exports = exported_symbols(pkg_src)
    missing = {s: fs for s, fs in imports.items() if s not in exports}

    if missing:
        print(f"❌ símbolos importados de '{spec}' que o pacote NÃO exporta:",
              file=sys.stderr)
        for s, fs in sorted(missing.items()):
            print(f"   - {s}  ({len(fs)} arquivo(s), ex.: {fs[0]})", file=sys.stderr)
        print(f"   exports encontrados em {pkg_src}: {', '.join(sorted(exports))}",
              file=sys.stderr)
        return 1

    print(f"✅ {len(imports)} símbolo(s) de '{spec}' conferem com o fonte do pacote: "
          f"{', '.join(sorted(imports))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
