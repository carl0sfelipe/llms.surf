---
id: 2026-09-20-heuristica-de-dados-verificados-so-casa-
titulo: heuristica de dados verificados so casa em portugues
data: 2026-09-20
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): paridade PT|EN em TODOS os casadores — bin/check-spec.sh (checks 1, 2, 3 e 5: anti-invenção, dados verificados, seção de verificação, anti-fantasma), bin/check-spec-facts.py, bin/check-bundle-facts.py, bin/lib-oracfit-gauntlet.sh (ground-truth) — + tokens aceitos declarados no fluxos/_comum/artefato-template.md; tests/test-spec-multi-oraculo.sh cobre spec EN de ponta a ponta
status: corrigido
---

# heuristica de dados verificados so casa em portugues

Dogfood real da v4.1.0 (2026-09-20), specs do rawpack escritas em inglês.

## Sintoma

Spec com seção `## Verified data` (inglês) reprovada no `bin/check-spec.sh`
com "bloco de dados verificados (o que o modelo PODE usar)" — a seção existia,
o gate não reconhecia o idioma. Só passa com os tokens portugueses. O limite
de idioma não estava documentado em lugar nenhum: nem no template, nem no
mapa-regras.

## Causa

Casadores independentes, todos só-PT — e não só o do bloco de dados
verificados; ao escrever o teste de regressão, TRÊS das cinco checagens do
check-spec eram só-PT:

- `bin/check-spec.sh:38-40` (check 2) — `grep -qiE 'dados verificados|contexto real|verificado\)|\(verificado'`
- `bin/check-spec.sh:35` (check 1, anti-invenção) — `n(a|ã)o invente|...` sem forma EN
- `bin/check-spec.sh:58` (check 3, seção de verificação) — título `.*verifica` não casa "Verified data"
- `bin/check-spec.sh:94` (check 5, anti-fantasma) — `NUNCA.*declare` sem forma EN
- `bin/check-spec-facts.py:61` — `r'^#{1,6}[^\n]*dados\s+verificados[^\n]*$(.*?)...'`
- `bin/check-bundle-facts.py:46` — `r"(?ims)^##[ \t]+dados[ \t]+verificados[^\n]*\n"`
- `bin/lib-oracfit-gauntlet.sh:313-314` — `r"(?im)^##\s*Dados(?:\s+verificados)?..."`

Uma spec em inglês morria no gate barato por até três checagens distintas —
e se passasse, ainda morreria na extração de facts, que não acharia a seção.

## Correção aplicada

1. Paridade PT|EN (case-insensitive) nos quatro consumidores de seção
   (check-spec check 2, check-spec-facts.py, check-bundle-facts.py,
   lib-oracfit-gauntlet.sh ground-truth): alternância
   `dados verificados|verified data`.
2. Nos checks 1, 3 e 5 do check-spec: `do not invent|don.t invent` (anti-invenção),
   `verified data` como título de verificação aceito (check 3),
   `never use declare|do not use declare` (anti-fantasma).
3. `fluxos/_comum/artefato-template.md` declara na seção de dados verificados
   que PT e EN são os dois únicos idiomas reconhecidos — o limite de idioma
   deixa de ser conhecimento tribal.
4. `tests/test-spec-multi-oraculo.sh` — spec EN mínima passa check-spec,
   extração de ground-truth e check-oracle (regressão dos dois lados).

## Pode acontecer de novo?

Em outros idiomas, sim — a heurística agora cobre PT e EN, o que é o universo
real do repo (specs PT + specs EN do bestmodel/rawpack). Idioma novo é caso de
estender a alternância, não de regra.
