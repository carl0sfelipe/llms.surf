---
id: 2026-08-12-biggest-gap-heuristic-pega-boilerplate-em-vez-do-gap-real
titulo: "oracfit_gauntlet_biggest_gap pega 'STAGE ORACLE FAILED' (boilerplate) em vez do gap articulado pelo juiz — builder refaz às cegas"
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): filtro de boilerplate + preferencia pela linha VISION GATE REJECTED + skip de linhas de progresso ^slice em oracfit_gauntlet_biggest_gap (commits 34a707d e 995ff67; testes em tests/test-gauntlet-feedback.sh)
status: promovido
interage_com: "2026-08-11-vision-gate-gap-nao-injetado-no-feedback-do-gauntlet"
interage_com: "2026-08-11-t3-judge-biggest-gap-vazio-max-iterations-20-loop-patologico"
---

# `oracfit_gauntlet_biggest_gap` pega boilerplate em vez do gap real do juiz

## Confirmar antes de aprovar

- [x] A correção NÃO foi commitada nem pushada (só working tree suja)
- [x] `git diff bin/lib-oracfit-gauntlet.sh` mostra +10/-3 linhas
- [x] HEAD continua em `8adce72` (inalterado)
- [x] Teste unitário do fix passou (ver §6)

## Revisão do mantenedor (2026-08-12 ~01:00)

Fix correto na intenção, mas a **Análise de regressão errou o Caso 1**: com o
filtro, a heurística não pegava o traceback real — pegava a linha 2 do
boilerplate ("The stage oracle and ordinary spec oracle were skipped."), que
contém "oracle" e casa o grep positivo. Pior: `tests/test-stage-runner.sh`
quebrou (15/16) porque o false-green guard dependia do `gap=` no console
conter "STAGE COMMAND FAILED".

Correções adicionais aplicadas na revisão:

1. `bin/dispatch-stages.sh`: quando o runner falha, o dispatch agora imprime
   `STAGE COMMAND FAILED: ...` **diretamente no stderr** — o sinal do
   false-green guard não depende mais da heurística de gap.
2. `bin/lib-oracfit-gauntlet.sh`: filtro estendido para pular também
   `^The stage oracle and ordinary spec oracle were skipped`.
3. `tests/test-gauntlet-feedback.sh`: +2 testes de regressão (gap real do
   juiz extraído; logfile só-boilerplate cai no fallback seguro).

Suítes: stage-runner 16/16 · feedback 8/8 · critic 10/10.

## Sintoma

Modo `infografico_v3` (e anteriormente `card_redesign`): o vision_gate (gemma
free) **articulou corretamente** o gap no verdict.txt:

```json
{"verdict":"REJECTED","biggest_gap":"The text contrast is poor; the small white
labels and thin lines are swallowed by the map details"}
```

O `stage_oracle` (corrigido no modo) extraiu esse gap e escreveu no logfile do
oráculo. Mas `oracfit_gauntlet_biggest_gap`, que lê o logfile para injetar no
`feedback.md`, retornou:

```
STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1
```

O gap real foi ignorado. O builder recebeu "STAGE ORACLE FAILED" — informação
inútil, não-acionável. O loop rodou 2+ iterações sem convergir.

## Causa raiz

O logfile do oráculo (construído por `dispatch-stages.sh:338-346`) tem este
formato quando o `stage_oracle` falha:

```
STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1
VISION GATE REJECTED — biggest_gap:
The text contrast is poor; the small white labels and thin lines are swallowed by the map details.
```

Linha 1: boilerplate do dispatch-stages (sempre presente quando stage_oracle falha)
Linha 2: label do stage_oracle customizado
Linha 3: o gap real articulado pelo juiz

A heurística original (`lib-oracfit-gauntlet.sh:257`):

```bash
gap="$(grep -iE 'FAIL|ERROR|not found|...|REJECTED|ORACLE' "$logfile" | head -1 | ...)"
```

O `grep` casa linha 1 (contém "FAIL" em "FAILED"). O `head -1` pega a primeira
linha — o boilerplate. As linhas 2-3 (o gap real) são ignoradas.

## Por que é um bug do core (não do modo)

O `stage_oracle` do modo **está correto** — ele extrai o gap e escreve no
logfile. O problema é que `oracfit_gauntlet_biggest_gap` não distingue o
boilerplate do dispatch-stages do conteúdo real do oracle. A função é
chamada por `oracfit_gauntlet_append_feedback` (linha 523) que é chamada
por TODOS os modos — não é específica do vision_gate.

## Correção aplicada (NÃO commitada — revisar antes)

Arquivo: `bin/lib-oracfit-gauntlet.sh`, função `oracfit_gauntlet_biggest_gap`.

```diff
- gap="$(grep -iE 'FAIL|ERROR|...|REJECTED|ORACLE' "$logfile" | head -1 | ...)"
+ gap="$(grep -iE 'FAIL|ERROR|...|REJECTED|ORACLE' "$logfile" \
+       | grep -ivE '^STAGE (ORACLE|COMMAND) FAILED|^VISION GATE REJECTED|^FRESHNESS GATE' \
+       | head -1 | ...)"
```

Adicionado `grep -ivE` (case-insensitive, negate) que filtra 3 padrões de
boilerplate:

1. `^STAGE (ORACLE|COMMAND) FAILED` — boilerplate do dispatch-stages.sh
2. `^VISION GATE REJECTED` — label do stage_oracle customizado
3. `^FRESHNESS GATE` — label do freshness gate

O filtro é ** ancorado em `^`** (início de linha) — só casa linhas que COMEÇAM
com esses padrões. O gap real ("The text contrast is poor...") não começa com
nenhum deles, então passa.

O mesmo filtro é aplicado no fallback (segundo `if [ -z "$gap" ]`).

## Análise de regressão — esta correção quebra algo?

### Caso 1: oracle normal (grep/shell) falha sem stage_oracle

Logfile típico:
```
STAGE COMMAND FAILED: role=run attempt=1 exit=1
The stage oracle and ordinary spec oracle were skipped.
[output do runner com traceback de erro]
```

**Antes:** heurística pega linha 1 ("STAGE COMMAND FAILED") — boilerplate.
**Depois:** heurística pula linha 1, pega linha 3+ (o traceback real).
**Veredito:** melhoria — o traceback é mais útil que o boilerplate.

### Caso 2: stage_oracle falha com gap curto

Logfile:
```
STAGE ORACLE FAILED: role=render attempt=1 exit=1
missing target: /tmp/screenshot.png
```

**Antes:** pega "STAGE ORACLE FAILED" (linha 1).
**Depois:** pula linha 1, pega "missing target:..." (linha 2 — contém "missing"
que casa o grep `-iE`). ✓ Correto.

### Caso 3: oracle de spec falha (## Oraculo)

Logfile:
```
[output do comando oracle]
FAIL: expected 'APPROVED' but got 'REJECTED'
```

**Antes e depois:** nenhuma linha começa com o boilerplate filtrado. A
heurística funciona igual — pega a linha com FAIL. ✓ Sem regressão.

### Caso 4: logfile só com boilerplate (gap vazio)

Logfile:
```
STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1
```

**Depois:** ambas as passagens do grep retornam vazio. Cai no fallback final:
`gap="oracle exited ${oracle_exit} — inspect captured log"`. ✓ Seguro.

### Caso 5: gap do juiz contém palavra filtrada

Gap: `"REJECTED layout — text too small"`

**Antes:** `grep -iE` casa "REJECTED" → pega a linha (se não for linha 1).
**Depois:** `grep -ivE '^STAGE...'` NÃO filtra (não começa com "STAGE"). ✓ Passa.

## Teste executado

```bash
$ printf 'STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1\nVISION GATE REJECTED — biggest_gap:\nThe text contrast is poor; labels swallowed by map.\n' > /tmp/test-gap.log
$ source ~/oracfit/bin/lib-oracfit-gauntlet.sh
$ oracfit_gauntlet_biggest_gap /tmp/test-gap.log 1
The text contrast is poor; labels swallowed by map.
```

**Antes do fix:** retornava `STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1`
**Depois do fix:** retorna `The text contrast is poor; labels swallowed by map.`

## O que falta (se aprovado)

1. Commit no oracfit com mensagem `fix(gauntlet): biggest_gap pula boilerplate do dispatch-stages`
2. Adicionar teste no `test-gauntlet-feedback.sh` com fixture de logfile de vision_gate
3. Relançar o dispatch `infografico_v3` com o core corrigido
4. Verificar convergência do loop (deve melhorar drasticamente)

## Não pushei

- `git status` mostra `M bin/lib-oracfit-gauntlet.sh` (modificado, não staged)
- HEAD em `8adce72` (inalterado)
- Zero push
