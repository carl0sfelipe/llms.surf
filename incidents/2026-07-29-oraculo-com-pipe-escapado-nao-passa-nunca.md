---
id: 2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca
titulo: oraculo com pipe escapado nao passa em nenhum estado
data: 2026-07-29
recorrivel: sim
regra: 39
status: promovido
---

# Oráculo com pipe escapado não passa em nenhum estado

## Sintoma

Dois lotes do dispatch 2.2 bloquearam no mesmo item (`obs-classe-c` e
`obs-classe-c-a`), somando **1204s** de modelo queimado:

```
❌ oráculo FALHOU | 377s | tentativa 1/2
❌ oráculo FALHOU | 185s | tentativa 2/2
❌ oráculo FALHOU |  38s | tentativa 1/2
🚨 modelo TRAVADO — 3 erros similares. Escalando.
BLOQUEADO | todos os tiers falharam | total=600s
```

O detector de travamento disparou corretamente e o rollback devolveu a árvore
limpa. A conclusão que se tirou na hora — "o modelo se perdeu nos pacotes
consumidores, escopo grande demais" — estava **errada**.

## Causa

O oráculo da spec trazia, no padrão de busca da declaração:

```
grep -qE "(const\|let) $n"
```

Em ERE, um pipe escapado é **caractere literal**, não alternação. O padrão
procurava a string `const|let`. Nenhum arquivo de código contém isso, então o
oráculo **não podia passar em nenhum estado do repositório**.

Origem do erro: o formato do batch file do 2.2 é `spec|task|workdir`, onde o
pipe é delimitador. Escapar o pipe virou reflexo, e vazou para dentro do
oráculo, onde ele era só regex.

Consequência em cadeia, medida:

1. oráculo falso-negativo em qualquer estado
2. as 3 tentativas provavelmente **fizeram o trabalho certo**
3. as 3 assinaturas de erro ficaram idênticas — e eram idênticas de verdade
4. detector de travamento escalou (comportamento correto, entrada errada)
5. tier Pro "falhou" igual
6. rollback desfez trabalho possivelmente bom

## Correção aplicada

`(const\|let)` → `(const|let)` em `specs/obs-classe-c-a-pacote.md` e
`specs/debranding-observability-classe-c.md`. Verificado antes de redespachar,
com as duas metades da prova:

```
grep -qE "(const|let) orbeOrdersTotal" src/metrics-registry.ts   # casa  → alternação funciona
grep -qE "(const|let) ordersTotal"     src/metrics-registry.ts   # ausente → falha pelo motivo CERTO
```

## Mecanismo aplicado

`bin/check-oracle.py`, ligado ao gate de `bin/dispatch-batch.sh`. Responde a
pergunta que faltava com três vias por exit code: **0** o oráculo falha e falha
pelo motivo certo, **1** já passa antes do dispatch, **2** está quebrado.

Três checagens, em ordem de custo:

1. **Lint de padrão**, sem rodar nada: `\|` em padrão ERE; alternação ou
   metacaractere dentro de `-F`; pipe cru em BRE (que é literal no grep do macOS
   e alternação só com barra no GNU — o mesmo oráculo dando resultado diferente
   por máquina).
2. **Prova de esqueleto**, medida no disco. É a parte que não é lint e que
   generaliza: para cada grupo de alternação cujos ramos são **todos** palavra-
   chave de linguagem, o grupo é testado isolado contra o arquivo alvo. Reprova
   com o veredito útil — `grep -qE '(const\|let)' arquivo` não casa, e
   `grep -qE '(const|let)' arquivo` casa: o defeito está no padrão, não no
   repositório.
3. **Classificação do stderr** depois de rodar o oráculo com teto
   (`bin/with-timeout.sh`, regra 12/21): `command not found`,
   `No such file or directory`, `Invalid regular expression`, quote
   desbalanceado. Falha do comando, não do estado do repo.

Medido: 4/4 nos casos defeituosos construídos (o `\|` original, `-F` com
alternação, arquivo alvo inexistente, quote desbalanceado) e **0 falso positivo**
nas 9 specs reais do dia.

## O mecanismo proposto estava errado — e registrar isso vale mais que o código

A proposta desta página era "exigir que cada padrão de `grep` do oráculo case
**algo** em algum arquivo do workdir". **Não funciona, e não foi implementada.**
O oráculo mede trabalho que **ainda não existe**: o padrão
`(const|let) ordersTotal` *tem de* não casar antes do dispatch. Exigir match
reprovaria todo oráculo correto e aprovaria só os que medem o passado — trocaria
este falso negativo por um falso positivo em 100% dos casos.

O que dá para medir é a **decomposição** do padrão em duas partes de estatuto
diferente:

| parte | exemplo | casa antes do dispatch? |
|---|---|---|
| alvo | `ordersTotal` | não, e é o esperado |
| esqueleto | `(const\|let) ` | **sim, sempre** — é vocabulário fixo da linguagem |

O `\|` destrói exatamente o esqueleto, que é a única parte do padrão cujo match é
exigível. Daí a checagem 2.

**Limite declarado (regra 32):** o esqueleto só é exigido quando todos os ramos
da alternação são palavra-chave de linguagem. Um oráculo que quebre uma
alternação entre identificadores de negócio (`(ordersTotal|cartActiveCount)`)
passa sem ser julgado — ali "não casa" é indistinguível de "nenhum dos dois
existe ainda". Nesse caso restam o lint e o stderr.

E o mecanismo cobre só o caminho do **lote**: `dispatch-escalate.sh` e
`dispatch.sh` chamados direto seguem sem ele. Por isso a regra 39 continua
classe **R** no `fluxos/_comum/mapa-regras.md`, com a dívida menor e nomeada.

## Pode acontecer de novo?

Sim, e é a lacuna mais importante achada neste dia. `bin/dispatch-batch.sh`
exige que o oráculo **falhe antes** do dispatch — justamente para não medir o
estado anterior. Mas o gate **não distingue duas falhas diferentes**:

| falha do oráculo | significado | o gate vê |
|---|---|---|
| trabalho ainda não feito | correto, é o esperado | exit≠0 |
| comando quebrado | inútil, nunca vai passar | exit≠0 |

Oráculo que falha em **qualquer** estado era indistinguível de oráculo correto.
Fechado pelo mecanismo acima, no caminho do lote.

interage_com: **reforça** a 24 (`$?` após pipe mente) e a 37 (o gate mede quem
escreve a spec) — as três são o orquestrador errando o instrumento, não o
executor. **Restringe** a 31 (exit 0 não é prova de trabalho): o inverso também
vale, **exit≠0 não é prova de trabalho faltando**. É a sexta ocorrência do dia
da família "o sensor mentiu, não o executor", e a primeira que custou tempo de
modelo em vez de só um número errado num relatório.
