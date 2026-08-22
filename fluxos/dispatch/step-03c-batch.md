# Step 3.6: Batch Loop (Mode 2.2)

## O que é

O 2.1 (`step-03b`) escala **um** item **verticalmente**: flash → pro → opus até
o oráculo passar. O 2.2 percorre **N** itens **horizontalmente**, e delega a
vertical inteira ao 2.1 sem reimplementar nada dela.

```
2.1  (vertical)              2.2  (horizontal, chama o 2.1 em cada item)
─────────────────            ──────────────────────────────────────────────
  spec                         gate: check-spec.sh em TODAS as specs
   ├ flash    tent 1..N        + oráculo de cada uma tem de FALHAR agora
   ├ pro      tent 1..N          ↓ (se qualquer uma reprova: para, custo zero)
   └ opus     tent 1..N        item 1 → checkpoint → 2.1 → passou? mantém
  → success | blocked                                  falhou? ROLLBACK
                               item 2 → checkpoint → 2.1 → ...
                               item 3 → ...
                              → resumo + batch-ledger.jsonl
```

`bin/dispatch-batch.sh <batch_file> [--mode 1|2|3] [--allow-dirty]
[--gate-only] [--max-per-tier n] [--item-timeout s] [--oracle-timeout s]
[--facts-also DIR]`

`batch_file`: uma linha por item, `<spec_file>|<task_name>|<workdir>`.
`#` inicia comentário.

## Por que não é `for spec in *; do dispatch-escalate.sh; done`

Quatro coisas faltavam, medidas neste repo — não supostas:

**1. Não existia laço com gate.** `parallel-dispatch.sh` tem laço mas é anterior
ao 2.0: sem oráculo, sem escalonamento. `dispatch-escalate.sh` tem oráculo e
escalonamento, sem laço. Usar um obrigava a abrir mão do outro.

**2. Não existia rollback.** Quando um tier falha, as edições **parciais** do
modelo ficam na árvore. O 2.1 tenta de novo por cima do lixo. Num lote é pior:
o item 2 herda a sujeira do item 1, e o oráculo do item 2 passa a medir um
estado que ninguém pediu. Sem checkpoint, um lote de 3 itens tem 3 chances de
contaminar o repo e nenhuma de voltar.

**3. O gate rodava tarde, ou não rodava.** `dispatch-escalate.sh` nunca chama
`check-spec.sh` — só confere que existe a linha `- comando:`. Num lote, isso é
gastar um tier inteiro no item 1 para descobrir que o item 3 estava sem
cláusula anti-invenção. O 2.2 reprova o lote inteiro **antes** de chamar
modelo: falha cara na frente, de graça.

**4. `$SPEC_FILE.escalate` é acumulativo.** O 2.1 faz
`SPEC_FILE="$SPEC_FILE.escalate"` e na tentativa seguinte anexa ao arquivo já
anexado. Num lote isso deixa `.escalate`, `.escalate.escalate` no `specs/`. O
2.2 roda cada item numa cópia descartável em `$TMPDIR`.

## O gate: três provas, não uma

```
✅ item — spec OK, oráculo falha como deve e pelo motivo certo
```

**1. `check-spec.sh`** — a spec tem defesa (5 checks).

**2. `check-spec-facts.py`** — o que a spec afirma como existente **existe**.
`check-spec.sh` confere que a spec PROÍBE o modelo de inventar; nada conferia
que o ORQUESTRADOR não inventou. Medido em 2026-07-29: a spec
`dedupe-observability-leadher.md` passou nos 5 checks afirmando um glob de
`vitest.config.ts` que está em **outro** repo, e foi despachada. O modelo foi
olhar, não achou, não inventou e reportou — se comportou melhor que o gate.
Citação legítima a outro repo se declara com `--facts-also DIR`.

**3. `check-oracle.py`** — o oráculo tem de FALHAR agora, e falhar **pelo motivo
certo**. Duas perguntas, e o gate só fazia a primeira até 2026-07-29.

Oráculo que já passa não mede nada — mediria o estado anterior, e o item
registraria sucesso com o modelo sem ter feito coisa alguma. É a mesma classe do
sensor cego que o 2.0 corrigiu no ledger (`exit_status:"ok"` em 116 de 116
registros porque "ok" era "log não vazio"). Um oráculo verde antes do dispatch é
um `exit_status` fabricado com passos extras.

Mas `exit≠0` tem **duas** causas, e tratá-las como uma custou 1204s de modelo:

| falha do oráculo | significado | o gate antigo via |
|---|---|---|
| trabalho ainda não feito | correto, é o esperado | `exit≠0` |
| comando quebrado | inútil, não passa nunca | `exit≠0` |

O `check-oracle.py` separa as duas por exit code — **0** falha pelo motivo certo,
**1** já passa, **2** quebrado — com lint de padrão, prova de esqueleto no disco e
classificação do stderr do oráculo.

A parte que não é lint é a **prova de esqueleto**, e ela vale entender porque a
formulação intuitiva é errada. "Exigir que cada padrão case algo no workdir" **não
funciona**: o oráculo mede trabalho que ainda não existe, então o padrão tem de
não casar. O que dá para exigir é a decomposição:

| parte do padrão | exemplo | casa antes do dispatch? |
|---|---|---|
| alvo | `ordersTotal` | não, e é o esperado |
| esqueleto | `(const\|let)` | **sim, sempre** — vocabulário fixo da linguagem |

Um pipe escapado destrói o esqueleto e só o esqueleto. Daí a prova ser possível
sem saber nada sobre o trabalho pedido. Limite: só vale quando todos os ramos da
alternação são palavra-chave; entre identificadores de negócio o gate não julga.
Incidente: `incidents/2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca.md`.

## Checkpoint e rollback: nunca `reset --hard` cego

A árvore pode ter trabalho não commitado do usuário. O snapshot é um objeto de
stash criado **com `-u`** (inclui não rastreados) e devolvido à árvore no ato:

```bash
git stash push -u -q -m "dispatch-batch:$RUN_ID"
SNAP=$(git rev-parse "stash@{0}")
git stash pop -q          # ref morre, objeto commit sobrevive
```

`git stash apply <sha>` aceita sha cru — o ref não precisa existir. O rollback:

```bash
git reset --hard -q "$SNAP_HEAD"
git clean -fdq            # -fd sem -x: node_modules/dist ficam
git stash apply -q "$SNAP"
```

Verificado em repo descartável antes de encostar em repo real: modificação
pré-existente volta, não rastreado pré-existente volta, arquivo que o modelo
**apagou** volta, arquivo que o modelo **criou** vai embora.

Sem `--allow-dirty`, workdir sujo é **pulado**, não arriscado.

## Teto de tempo

O 2.1 chama o CLI do runner **sem teto**. Modelo que pendura segura
o lote inteiro sem sinal — foi o que custou 52min em 2026-07-24. O 2.2 embrulha
cada item em `bin/with-timeout.sh` (default 1200s) e trata `124` como falha com
rollback, não como sucesso silencioso.

## Ordem dos itens

Do mais mecânico para o mais frágil. Se o modelo degradar, degrada no fim, e o
rollback protege quem vem depois. Corolário: ordene também por **força do
oráculo** — item cujo oráculo é o teste rodando de verdade vale mais que item
cujo oráculo é `grep = 0`, e é onde você quer que a evidência esteja.

## Registro

`.dispatch/logs/batch-ledger.jsonl`, uma linha por lote:

```json
{"run_id":"batch-...","mode":2,"total":3,"ok":2,"failed":1,"total_s":412,
 "items":[{"task":"loyalty-orphan","result":"success","duration_s":97}]}
```

`result` ∈ `success | failed | timeout | skipped-dirty`. Os logs por tentativa
continuam no 2.1 (`<task>-<tier>-<n>.log`) e o veredito por item, no
`escalate-ledger.jsonl`.

## Limite declarado (regra 32)

- **Sequencial, não paralelo.** Dois itens no mesmo workdir em paralelo
  disputariam a mesma árvore e o checkpoint de um invalidaria o do outro.
- **Rollback é por item, não por lote.** Item 1 que passou fica. Para desfazer
  o lote inteiro, use o HEAD anterior — o `run_id` está no ledger.
- **O gate não confere ESCOPO de cláusula**, só ausência dela — mesmo limite do
  `check-spec.sh`, herdado de propósito.
- **`check-spec-facts.py` prova que o literal existe em ALGUM lugar do workdir**,
  não que esteja no arquivo e na linha que a spec afirma. Atribuição trocada
  dentro do mesmo repo passa. Precisão medida: 4/4 num conjunto de 4 specs —
  amostra pequena, declarada.
- **`check-oracle.py` só exige esqueleto de alternação entre palavras-chave.**
  Oráculo que quebre uma alternação entre identificadores de negócio passa sem
  ser julgado — ali "não casa" é indistinguível de "nenhum dos dois existe
  ainda". Restam o lint estático e a leitura do stderr. Medido: 4/4 nos casos
  defeituosos construídos, 0 falso positivo nas 9 specs reais do dia.
- **Oráculo com efeito colateral roda duas vezes.** O gate executa o oráculo, e o
  2.1 o executa de novo por tentativa. Oráculo que só lê (`grep`, `tsc`,
  `vitest`) é idempotente; oráculo que escreve, não.
- **`git clean -fd` não remove arquivo ignorado.** Se o modelo escrever dentro
  de `dist/` ou `node_modules/`, o rollback não desfaz.
