#!/usr/bin/env bash
# Oráculo 41-05: todo link relativo em site/**/*.html, SKILL.md e fluxos/**/SKILL.md resolve,
# e um gate novo (tests/test-links.sh) mantém isso.
. "$(dirname "$0")/_lib.sh"
QUEBRADOS=$(python3 - <<'PY'
import re, os, glob
root = os.getcwd(); bad = 0
files = glob.glob("site/**/*.html", recursive=True) + ["SKILL.md"] + glob.glob("fluxos/**/SKILL.md", recursive=True)
for f in files:
    base = os.path.dirname(f) or "."
    txt = open(f, encoding="utf-8", errors="ignore").read()
    alvos = re.findall(r'(?:href|src)="([^"#?]+)', txt) + re.findall(r'\]\(([^)#?\s]+)\)', txt)
    for a in set(alvos):
        if re.match(r'^(https?:|mailto:|data:|javascript:|tel:)', a) or a.startswith("/"): continue
        if not (os.path.exists(os.path.join(base, a)) or os.path.exists(os.path.join(root, a))):
            print(f"quebrado em {f}: {a}", file=__import__("sys").stderr); bad += 1
print(bad)
PY
)
[ "$QUEBRADOS" = "0" ] && ok "nenhum link relativo quebrado" || falha "$QUEBRADOS link(s) quebrado(s)"
exige_arquivo tests/test-links.sh
passa "tests/test-links.sh" bash tests/test-links.sh
mutacao_deve_falhar "link quebrado injetado" site/readme.html 's#</body>#<a href="nao-existe-xyz.html">x</a></body>#' tests/test-links.sh
contagens_publicas_batem
veredito
