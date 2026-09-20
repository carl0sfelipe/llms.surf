---
id: "" # Identificador único do artefato
schema: 1 # Versão do schema; ainda NÃO está congelado
status: draft # Estados possíveis: draft, ready, in-progress, in-review, done, blocked
owner: "" # Responsável atual pelo trabalho
modelo: "" # Modelo de IA utilizado neste artefato
tentativas: 0 # Número de tentativas de execução
bloqueio: false # Indica se o artefato está bloqueado para edição
evidencia: "" # Caminho ou referência para a evidência do trabalho
---

## Objetivo

Descreva o objetivo deste artefato.

## Barra

Referência concreta, fetchable e comparável do que “bom” significa
([gauntlet-loop](https://github.com/robonuggets/gauntlet-loop)). Sem barra
vaga (“bonito”, “profissional”). Preferir: URL live, arquivo canônico no
repo, suite de teste, ou screenshot de referência.

- nome: <produto/página/repo/teste nomeado>
- como fetchar: <url | path | comando que materializa a referência>
- como comparar: <oracle/teste | A/B visual | checklist>

## Dados verificados (o que o modelo PODE usar — tudo conferido na árvore)

Todo fato que a spec afirma sobre o repo (path, número, nome, comando que
existe) lista aqui — conferido na árvore na data do artefato. O heading em
inglês "Verified data" também é aceito pelos gates; português e inglês são
os dois únicos idiomas reconhecidos.

- <fato verificado 1 — path/nome/número conferido>
- <fato verificado 2>

Não invente número, prazo, nome, caminho ou fonte além dos listados em
“Dados verificados”. Campo que você não conseguir determinar a partir da
árvore fica marcado [A DEFINIR], nunca em branco. NUNCA use declare const
como workaround — importe de verdade.

## Passos

- Passo 1
- Passo 2

## Oráculo

Comando + exit esperado que prova que o trabalho foi feito — não que o modelo
rodou, que o resultado é verdade. Sem isto, `bin/ledger-finalize.sh` só sabe
dizer se o log não ficou vazio, e "log não vazio" já registrou como "ok" um
dispatch que alucinou e não fez nada (incident: exit_status fabricado).

O oráculo é a Metric hard do gauntlet. Em falha, `dispatch-mode` /
`dispatch-escalate` injetam `## GAUNTLET FEEDBACK` (biggest_gap) no próximo
attempt até exit 0 (ou safety_ceiling).

A linha de comando é TEXTO CRU, sem crase (regra 46): crase vira substituição
de comando no eval e gera exit 127 fantasma. E 1 arquivo = 1 história — só o
primeiro `## Oráculo` de um arquivo é despachado; spec com vários é recusada
no preflight (incidente 2026-09-20-spec-com-n-oraculos-despacha-so-o-primei).

- comando: <comando shell exato, com cd embutido se precisar de outro diretório>
- exit esperado: <inteiro, default 0 se omitido>

Exemplo (recorte e ajuste — indentado de propósito, para não contar como uma
segunda linha "comando:" do arquivo):

    comando: cd <workdir-alvo> && bash scripts/check-dup-kit.sh | tail -1 | grep -q '^total=0$'
    exit esperado: 0

## Resultado

Descreva o resultado esperado.
