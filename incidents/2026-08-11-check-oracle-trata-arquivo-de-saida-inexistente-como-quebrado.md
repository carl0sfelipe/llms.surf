---
id: 2026-08-11-check-oracle-trata-arquivo-de-saida-inexistente-como-quebrado
titulo: check-oracle.py classifica FileNotFoundError do arquivo-alvo como oraculo quebrado, nao como falta de trabalho
data: 2026-08-11
recorrivel: sim
regra: 39
status: promovido
interage_com: "2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca (mesmo mecanismo, defeito oposto), 2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback"
---

# `check-oracle.py` classifica `FileNotFoundError` do arquivo-alvo como quebrado, não como falta de trabalho

## Sintoma

Batch de 21 despachos (`deepseek_direct_flash`, extração de fornecedores de
PDF/XLSX/ODS pra JSON) — todo o loop rodou em **8 segundos** e nenhum dos 21
chegou a chamar o modelo. Log:

```
[1/21] fornecedores-01.json — fim 02:24:09 exit=2
...
[21/21] fornecedores-21.json — fim 02:24:17 exit=2
ERROR: preflight: broken oracle (oracle_exit=2) — runner MUST NOT start
```

20 de 21 bloqueados com `oracle_exit=2` ("broken oracle" — runner nem começa).
Custo evitado, mas trabalho todo perdido — nenhum arquivo foi gerado.

## Causa

Oráculo de cada spec:

```
python3 -c "import json,sys; d=json.load(open('data/fornecedores/extracted/fornecedores-01.json')); sys.exit(0 if isinstance(d, list) and all('nome_fantasia' in x for x in d) else 1)"
```

Antes do dispatch, o arquivo de saída **obviamente não existe ainda** — é
o que o modelo vai criar. `open()` do Python levanta `FileNotFoundError`
nesse caso. `check-oracle.py` intercepta essa exceção e classifica como:

```
❌ oráculo falhou por ERRO DE COMANDO, não por trabalho faltando:
   - arquivo do oráculo não existe: FileNotFoundError: [Errno 2] No such file or directory: '...'
```
→ `exit=2` (broken, bloqueia).

Isso está **errado para qualquer tarefa de criação de arquivo novo** — que é
o caso mais comum de despacho neste projeto (gerar doc, gerar JSON, gerar
código novo). "Arquivo alvo não existe ainda" é exatamente o estado
pré-dispatch esperado, análogo ao "grep não casa ainda" que o mesmo script
trata corretamente como falha válida quando o padrão é `grep`/`test -f`.

**Confirmado que é o padrão de acesso ao arquivo, não o conteúdo do
oráculo**, comparando com a spec que passou de primeira nesta mesma sessão
(`<repo-cliente>-pivot-ecommerce-hibrido-plano-implementacao.md`), cujo oráculo é:

```
test -f docs/.../plano-implementacao.md && grep -qE "..." docs/.../plano-implementacao.md && ...
```

`test -f` num arquivo ausente retorna `exit 1` silenciosamente (sem
exceção) — `check-oracle.py` classifica certo como "falha válida,
trabalho ainda não existe". `open()` do Python no mesmo cenário lança
exceção com traceback — e o classificador de stderr trata QUALQUER
`FileNotFoundError`/`No such file or directory` vindo de dentro de um
`python3 -c` como comando quebrado, sem diferenciar "arquivo auxiliar que
deveria existir antes" de "arquivo de saída que a tarefa VAI criar".

## Erro meu ao investigar (registrando por transparência, é o mesmo padrão do regra-24)

Testei `check-oracle.py` manualmente ANTES de rodar o batch, mas com:

```bash
python3 bin/check-oracle.py "$SPEC" <home-do-dono>/<repo-cliente>.live-imports 2>&1 | tail -20
echo "exit=$?"
```

`$?` depois de um pipe reflete o exit code do **último comando do pipe**
(`tail`), não do `check-oracle.py`. Li "exit=0" e concluí (errado) que a
spec passava. Rodei o batch inteiro em cima dessa leitura errada. Exatamente
o padrão descrito na regra 24 ("`$?` após pipe mente") — citada como
`interage_com` do próprio incidente de 2026-07-29 que este aqui espelha.
Reproduzido depois sem pipe: `exit=2` direto, consistente, os dois testes
(com e sem `--quiet`) batem.

## Pode acontecer de novo?

Sim, toda vez que uma spec usar `python3 -c "...open('arquivo-novo')..."` em
vez de `test -f arquivo-novo && ...` no comando do oráculo — e é o padrão
mais natural de se escrever quando o critério de aceite é "JSON válido",
porque `test -f` sozinho não valida conteúdo, só existência. Ou seja, o
`check-oracle.py` empurra o autor de spec pro padrão shell (`test -f` +
`grep`) e penaliza silenciosamente quem preferir Python pra validação
semântica mais rica (parse de JSON, schema) — que é objetivamente melhor
verificação de conteúdo.

## Correção aplicada (workaround, não no código do oracfit)

Reescrevi os 21 oráculos pra formato shell puro:

```
test -f data/fornecedores/extracted/fornecedores-01.json && python3 -c "import json,sys; d=json.load(open('data/fornecedores/extracted/fornecedores-01.json')); sys.exit(0 if isinstance(d, list) and all('nome_fantasia' in x for x in d) else 1)"
```

O `test -f` na frente faz o curto-circuito `&&` nunca chegar no `python3 -c`
quando o arquivo não existe — evita a exceção, `check-oracle.py` vê
`exit 1` limpo (via `test`), classifica certo como falha válida
pré-dispatch. Ainda preserva a validação de conteúdo real (JSON parse +
schema) depois que o arquivo existir.

**Não editei `bin/check-oracle.py`** — não tenho certeza se a correção certa
é "ignorar `FileNotFoundError` do arquivo que o próprio path do oráculo
aponta como alvo de escrita" (arriscado de generalizar sem quebrar a
proteção original) ou documentar a regra "oráculo de conteúdo sempre precisa
de `test -f` na frente". Fica pra quem manter o core decidir — este
incidente é o registro da evidência, não a correção do mecanismo.

## Correção no core (2026-08-12, v3.5)

Decisão tomada no meio-termo: path ausente citado no stderr que resolve para
DENTRO do workdir e não existe = estado pré-dispatch esperado de task de
criação → exit 0 ("falha pelo motivo certo") com dica recomendando
`test -f <alvo> && …`. Path fora do workdir (typo, dependência ausente)
continua exit 2. De quebra, exit 127 ganhou via própria (chega com stderr
vazio quando a causa é crase — regra 46). Verificado com o oráculo literal
deste incidente (exit 0 + dica) e com `cat /etc/inexistente` (exit 2).
