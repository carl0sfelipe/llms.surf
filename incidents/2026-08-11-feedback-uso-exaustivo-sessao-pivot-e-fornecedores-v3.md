---
id: 2026-08-11-feedback-uso-exaustivo-sessao-pivot-e-fornecedores-v3
titulo: feedback de uso exaustivo — 22 despachos reais (plano de pivot + extração de 21 fornecedores), pedido explícito do humano pra v3
data: 2026-08-11
recorrivel: sim
regra: 41
status: aberto
interage_com: |
  2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback,
  2026-08-11-check-oracle-trata-arquivo-de-saida-inexistente-como-quebrado,
  2026-08-11-hand-rolled-loop-reinventa-dispatch-batch-e-cai-no-bug-de-stdin,
  2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca,
  2026-07-26-spec-sem-clausula-anti-invencao-gera-num,
  2026-07-30-feedback-de-uso-forcado-por-humano (mesmo padrão: humano pediu,
  harness não coletou sozinho — ainda vale em 2026-08-11)
---

# Feedback de uso exaustivo — 22 despachos reais, pedido explícito do dono pra v3

## Contexto

Pedido direto: "preencha um incidente de como foi usar tão exaustivamente o
oracfit pois to atualizando pra v3 e preciso de mais feedback". Sessão única
(2026-08-10 → 2026-08-11), dois workdirs diferentes
(`<repo-cliente>.live-imports`, projeto real), todos os despachos via
`deepseek_direct_flash` (DeepSeek V4 Flash, provider direto).

**Volume real:** 22 despachos de modelo — 1 plano técnico de produto (265
linhas, grounded em exploração real do repo) + 21 despachos de extração de
dados (PDF/XLSX/ODS → JSON estruturado, 5758 registros brutos, 3567 únicos
após dedup). 3 incidentes já registrados individualmente durante a sessão
(linkados acima); este é o relatório consolidado que o pedido pediu.

## O que funcionou bem (não mudar isso em v3)

1. **`check-spec.sh` + cláusula anti-invenção**: reprovou de cara duas specs
   fracas (a primeira do plano de pivot, e por padrão as 21 specs de
   fornecedores só passaram depois de eu seguir o template certo).
   Zero dado fabricado detectado num spot-check dos 3567 registros finais —
   nenhum WhatsApp, CNPJ ou nome inventado, tudo rastreável ao texto fonte.
   O mecanismo da regra 35 generaliza bem pra tarefa de extração de dados,
   não só geração de prosa/código.
2. **`check-oracle.py` pegou o bug do pipe escapado de novo**, confirmando
   que o mecanismo da regra 39 é robusto e recorrente — vale a pena manter
   e reforçar em v3, não é fluke de uma sessão.
3. **DeepSeek Flash direto (`deepseek-direct/deepseek-v4-flash`) explora o
   repo de verdade antes de escrever** — visível em `events.jsonl` como
   sequência de `tool_call` (grep/ls/cat/read) antes do primeiro `write`.
   O plano técnico saiu com caminhos reais do monorepo, não inventados.
4. **Depois de specs corrigidas, 21/21 despachos de extração terminaram com
   `exit=0`** — zero refinamento necessário na rodada final, mesmo processando
   fontes de 3.6k a 137k caracteres.

## O que foi ruim / atrito real (candidatos pra v3, em ordem de impacto)

### 1. `check-oracle.py` bloqueou 20 de 21 despachos de cara (achado maior)

Detalhe completo em `2026-08-11-check-oracle-trata-arquivo-de-saida-inexistente-como-quebrado.md`.
Resumo pra quem só ler este relatório: oráculo que usa `python3 -c
"...open('arquivo-novo')..."` pra validar arquivo que a própria tarefa vai
CRIAR é classificado como "quebrado" (`exit=2`) por causa da
`FileNotFoundError`, quando esse é o estado pré-dispatch correto e esperado.
Bloqueou o batch inteiro em 8 segundos, zero trabalho feito, sem aviso de
que o problema era o padrão de acesso ao arquivo (Python `open()` vs shell
`test -f`). Workaround aplicado manualmente (`test -f X && python3 -c ...`)
em 21 specs.

**Pergunta pra v3**: por que `test -f` ausente = "falha válida" mas
`open()` ausente = "comando quebrado"? Do ponto de vista de quem escreve o
oráculo, os dois são "arquivo não existe ainda" — o classificador de stderr
devia tratar os dois igual, ou pelo menos a mensagem de erro devia dizer
explicitamente "troque `open()` por `test -f` na frente" em vez de "erro de
comando" genérico.

### 2. `bin/dispatch-batch.sh` existe e resolve exatamente meu caso — descobri tarde demais

Detalhe completo em
`2026-08-11-hand-rolled-loop-reinventa-dispatch-batch-e-cai-no-bug-de-stdin.md`.
Escrevi um loop `while read` na mão pra rodar as 21 specs, caí no bug
clássico de stdin compartilhado (loop morre depois do item 1, sem erro
óbvio). `dispatch-batch.sh` já existe, já evita esse bug (array + `for`), e
já tem gate de `check-spec`+`check-oracle` em TODAS as specs antes de gastar
um token — estritamente melhor que o que eu escrevi. Nada no `--help` do
`oracfit` aponta pra ele.

**Pergunta pra v3**: `dispatch-batch.sh` devia ser promovido a comando de
primeira classe (`oracfit batch <arquivo>`?) em vez de ficar só em `bin/`
com prefixo antigo `dispatch-*`? A dualidade de nomenclatura (`oracfit run`
vs `bin/dispatch-batch.sh`) sozinha já escondeu a ferramenta certa de mim.

### 3. Ledger/usage-feedback ficou mudo depois de sucesso real

Detalhe completo em
`2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback.md`.
O PRIMEIRO despacho da sessão (plano técnico, sucesso completo, `exit=0`,
arquivo certo escrito) nunca apareceu em `mode.jsonl` nem gerou
`incidents/uso/*.md`. Isso é dado que a v3 provavelmente quer pra medir
adoção/telemetria — e estava sumindo silenciosamente mesmo no caminho feliz.
Causa não isolada (fica em aberto no incidente original) — mas se a v3 quer
telemetria confiável de uso, esse é o primeiro buraco a fechar, porque
afeta o caso de sucesso, não só o de erro.

### 4. Painel web: descoberta de run ativa e ordenação confusas

Não virou incidente formal ainda — registro aqui porque é feedback direto
de uso. Sintomas na sessão:
- Abri o painel (`oracfit-panel-server.py`) DEPOIS de já ter apontado
  `--logs-dir` pro workdir errado (sobra de sessão anterior) — sem aviso
  visível de "isto não é o workdir ativo".
  `runtime-config.json` expõe `logs_dir` mas nada na UI destaca isso.
- Dropdown de run (`run-switcher`) mostrava "no recent runs" mesmo com dados
  reais em `/logs/events.jsonl` — populava só no load da página, não em
  polling contínuo (usuário reportou "só vi isso: run" e teve que recarregar
  na mão).
- Ordenação do dropdown era por ordem de PRIMEIRA aparição do run_id
  (`Map` insertion order + `.reverse()`), não por última atividade — um run
  que começou cedo mas ainda tá recebendo eventos ficava fora do topo. Corrigi
  isso ao vivo em `panel/app.js` (`renderSwitcher` agora ordena por
  `lastTs`, com fallback pra `firstTs`) — patch aplicado local, não
  submetido como PR formal, fica pra quem mantém decidir se aceita.

**Pergunta pra v3**: o painel merece um indicador simples "workdir ativo: X"
no topo, e o dropdown de runs devia atualizar em tempo real (mesmo poll de
≤2s que já existe pros eventos), não só no load.

### 5. Zero visibilidade de progresso DENTRO de um despacho longo

Despachos de extração variaram de **40 segundos a 26 minutos** (o mesmo
modo, mesmo provider, só mudando o tamanho da fonte/quantidade de
fornecedores a extrair — de 3.6k a 137k caracteres, de 0 a 1250 registros
por arquivo). Durante esse tempo, a única visibilidade é o log bruto de
eventos (`thinking`, `tool_call`) sem nenhum agregado tipo "N registros
gerados até agora" ou ETA. Tive que escrever um script de barra de progresso
caseiro rodando por fora (contando linhas `— fim` no MEU log de wrapper, não
em nada nativo do oracfit) só pra dar visibilidade ao usuário humano.

**Pergunta pra v3**: dá pra expor uma métrica de progresso incremental por
despacho (ex.: linhas escritas até agora no arquivo de saída, ou heurística
de "tokens gerados / estimativa") no painel ou no CLI, em vez de silêncio
total até o fim?

### 6. Bytes não-UTF8 vazando de extração de PDF quebram `check-spec.sh` sem diagnóstico claro

Um PDF (`Lista de Fornecedores Drop Nacional (1)`) teve **1 byte nulo
(`\x00`)** sobrevivendo à extração de texto (via PyMuPDF, fora do oracfit,
mas o byte foi parar dentro da spec `.md` que virou input do oracfit).
Resultado: `check-spec.sh` reportou `Binary file ... matches` em vez de
rodar os checks de texto normalmente — mensagem correta tecnicamente (é o
que o `grep` faz mesmo), mas não deixa óbvio que a causa é "1 byte de lixo
no meio de 8KB de texto normal", e não "spec malformada".

**Pergunta pra v3**: `check-spec.sh`/`check-oracle.py` podiam detectar NUL
byte na spec ANTES de rodar os greps semânticos, e dar mensagem específica
("spec contém byte(s) não-texto — provavelmente lixo de extração de
PDF/OCR; rode `tr -d '\\000' < spec > spec.limpo`") em vez de deixar o
usuário decifrar pela saída padrão do `grep`.

### 7. Env var de workdir errada falha silenciosa (achado em sessão anterior, reconfirmado aqui)

Já não é incidente novo (mencionado no de 2026-08-10), mas vale reforçar no
relatório de v3: `WORKDIR` (nome errado) vs `ORACFIT_WORKDIR` (certo) — sem
aviso, sem erro, só silenciosamente ignora e cai no `$PWD`. Aconteceu de
novo nesta sessão antes de eu aprender o nome certo.

## Números da sessão (pra dar peso quantitativo ao feedback)

```
despachos totais:        22 (1 doc de plano + 21 extração)
modo:                     deepseek_direct_flash (100% dos despachos)
provider:                 deepseek-direct/deepseek-v4-flash
exit=0 na rodada final:   22/22 (100%, depois das correções de spec/oracle)
tempo por despacho:       40s a 26min (variação de ~40x)
registros extraídos:      5758 brutos → 3567 únicos após dedup
incidentes novos gerados: 4 (este + os 3 linkados acima)
bugs achados no MEU código (não do oracfit):
  - $? depois de pipe mentindo (regra 24, reincidência minha própria)
  - grep -c "" || echo 0 duplicando linha de saída
  - while read < arquivo consumindo stdin do comando de dentro
```

## Resumo pra quem for ler só o topo (v3 priorização sugerida)

Prioridade real, na minha leitura de impacto:

1. **#1 (check-oracle FileNotFoundError)** — bloqueia despacho legítimo sem
   aviso claro, é o que mais custou tempo nesta sessão.
2. **#3 (ledger mudo no sucesso)** — se v3 quer decidir prioridade por
   telemetria de uso real, esse buraco distorce os dados desde já.
3. **#2 (dispatch-batch.sh escondido)** — não é bug, é descoberta; resolve
   com documentação/promoção de comando, não com código novo.
4. **#4-#7** — polish de UX, menor urgência que os 3 de cima, mas todos
   custaram tempo real de debug nesta sessão específica.
