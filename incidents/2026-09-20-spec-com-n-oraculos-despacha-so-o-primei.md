---
id: 2026-09-20-spec-com-n-oraculos-despacha-so-o-primei
titulo: spec com N oraculos despacha so o primeiro sem aviso
data: 2026-09-20
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/lib-oracfit-preflight.sh e bin/check-oracle.py recusam spec com mais de um bloco ## Oráculo/linha comando: ("1 arquivo = 1 história — recorte antes de despachar"); bin/check-spec.sh avisa (sem reprovar) quando N>1; tests/test-spec-multi-oraculo.sh cobre a recusa
status: corrigido
---

# spec com N oraculos despacha so o primeiro sem aviso

Dogfood real da v4.1.0 (2026-09-20), despachando as specs do rawpack.

## Sintoma

Arquivo com N histórias tem N seções `## Oráculo` (uma por história). O
despacho usa silenciosamente só a primeira — as demais histórias do arquivo
nunca rodam e ninguém é avisado. Consequências medidas no dogfood: o rawpack
adotou "um arquivo por história" como convenção defensiva, e a S32 (bestmodel)
ganhou nota manual "recorte a história antes de despachar" — workarounds de
humano para um silêncio de máquina.

## Causa

Três pontos de extração, todos first-match no arquivo inteiro, todos mudos
sobre excesso:

- `bin/lib-oracfit-gauntlet.sh:233` — `grep -iE '^[-*][[:space:]]*comando:' "$spec" | head -1`
- `bin/lib-oracfit-preflight.sh:128` — mesmo `grep ... | head -1`
- `bin/check-oracle.py:67+418` — `ORACLE_LINE.search(...)` (regex multiline,
  `.search()` devolve a primeira)

`bin/check-spec.sh:71-72` só exige que exista PELO MENOS um `## Oráculo` e uma
linha `comando:` — não conta. Nenhum aviso em nenhum ponto do caminho
(grep por "mais de um orácul"/"multiple oracl": zero hits).

## Correção aplicada

1. `bin/lib-oracfit-preflight.sh` + `bin/check-oracle.py` — contam blocos
   `## Oráculo` (equivalentemente, linhas `comando:`); N>1 → recusa com
   mensagem explícita: "1 arquivo = 1 história — recorte a história antes de
   despachar" (exit de erro, antes de gastar token).
2. `bin/check-spec.sh` — aviso (não reprovação) quando N>1, visível já na
   autoria.
3. `tests/test-spec-multi-oraculo.sh` — fixture com 2 oráculos deve ser
   recusada com a mensagem; fixture com 1 deve despachar normal.

## Pode acontecer de novo?

A recusa substitui o silêncio — o modo de falhar agora é alto e explícito, na
porta certa (antes do runner). Convenção "1 arquivo = 1 história" segue válida
e documentada na mensagem.
