EXECUTE A ESPEC ABAIXO por completo (o cabeçalho YAML e as seções são contrato, não comentário).

---
id: "check-delegacao-2-roi"
schema: 1
status: ready
owner: "claude-opus (orquestrador)"
modelo: "grok-4.6-xhigh-fast"
tentativas: 3
bloqueio: false
evidencia: "docs/proposta-check-delegacao.md"
---

# oracfit roi — o que cada executor custou e acertou, a partir dos ledgers

REGRAS DE OURO (violar qualquer uma = reprovação imediata):
- Workdir: a raiz deste repositório (worktree feat/check-delegacao). Escreva SÓ os arquivos de ENTREGÁVEIS.
- NUNCA git commit, push, reset, checkout, switch, stash, rebase; nada de rm -rf.
- Python stdlib only. Nenhuma rede, nenhum modelo. Só LÊ ledgers — nunca escreve neles.
- Nao invente numero, campo, regra ou fonte alem dos listados nesta espec. Valor nao decidido = [A DEFINIR].
- NUNCA use declare const, stub vazio ou `pass` como workaround para passar teste — implemente de verdade.
- Não edite core/precos.json, docs/proposta-check-delegacao.md, bin/check-delegacao.py, tests/fixtures/.

## Dados verificados (copie SEM ALTERAR)
- Proposta §4: docs/proposta-check-delegacao.md
- Ledger: `<workdir>/.dispatch/ledger/mode.jsonl`, uma linha JSON por run. Campos usados (todos strings no
  arquivo): `ts`, `model_id`, `task`, `status` ("pass"/"fail"), `attempt`, `estimated_cost`, `flash_work_s`; opcionais
  `executor_in_tok`, `executor_out_tok`, `cost_source`. `model_id == "orquestrador"` = modo direto (`oracfit verificar`).
  `cost_source == "orquestrador-nao-medido"` = custo NÃO medido (o 0 não significa grátis).
- Linhas antigas têm `estimated_cost` "0" sem `executor_out_tok`: custo NÃO medido.
- Padrão de teste shell: tests/test-verificar.sh.

## Objetivo

`bin/oracfit-roi.py [--workdir DIR]... [--desde AAAA-MM-DD] [--json]` (sem --workdir: cwd; vários permitidos).

Para cada `model_id`, sobre as linhas com `ts >= desde` (se dado):
- `runs`, `pass` (contagem de status pass), `taxa_pass` (pass/runs), `primeira` (% com status pass e attempt == "1"),
  `tentativas_media`, `tempo_medio_s` (média de flash_work_s), `custo_medido_usd` (soma de estimated_cost SÓ das linhas
  com `executor_out_tok` presente e > 0), `runs_com_custo` (quantas entraram nessa soma),
  `custo_por_pass_usd` (custo_medido_usd / pass das linhas com custo; "n/d" se 0).
- Linha malformada é ignorada e contada em `linhas_ignoradas` (total).
- Saída padrão: tabela de texto, uma linha por modelo, ordenada por runs desc; custo não medido aparece "n/d", nunca "0".
  Rodapé: `tentativas_esperadas sugeridas para check-delegacao: <model_id>=<media>` para modelos com ≥ 3 runs.
- `--json`: `{"modelos": {id: {...campos acima...}}, "linhas_ignoradas": N}`.
- Exit 0; nenhum ledger encontrado em nenhum workdir → exit 3 com mensagem citando o caminho procurado.

Registre o subcomando no `bin/oracfit` ao lado de `verificar`:
`roi) exec python3 "$SCRIPT_DIR/oracfit-roi.py" "$@" ;;` e uma linha de ajuda no mesmo estilo da de `verificar`.

## Testes — `tests/test-oracfit-roi.sh`
Ledger sintético num diretório temporário com: 3 runs claude-sonnet-5 pass attempt 1 com executor_out_tok e
estimated_cost 0.4, 0.5, 0.6; 1 run claude-sonnet-5 fail attempt 5 sem executor_out_tok e estimated_cost "0";
2 runs orquestrador pass com cost_source orquestrador-nao-medido; 1 linha lixo. Prove no `--json`:
- claude-sonnet-5: runs 4, pass 3, primeira 75 (%), custo_medido_usd 1.5, runs_com_custo 3, custo_por_pass_usd 0.5.
- orquestrador: custo "n/d"/não medido (custo_medido_usd 0 e runs_com_custo 0) e a tabela mostra "n/d".
- linhas_ignoradas 1; `--desde` posterior a todas as linhas → nenhum modelo; dois --workdir somam;
  workdir sem ledger → exit 3; `bin/oracfit roi --json` igual ao script.

## Barra
- nome: tests/test-oracfit-roi.sh verde; tests/test-verificar.sh continua verde
- como fetchar: ORACFIT_ROOT=$PWD bash tests/test-oracfit-roi.sh
- como comparar: fail=0; git status mostra só ENTREGÁVEIS

## ENTREGÁVEIS
- bin/oracfit-roi.py (≤ 130 linhas)
- bin/oracfit (só a linha do case e a linha de ajuda)
- tests/test-oracfit-roi.sh (≤ 120 linhas)

## VERIFICAÇÃO
- ORACFIT_ROOT=$PWD bash tests/test-oracfit-roi.sh
- ORACFIT_ROOT=$PWD bash tests/test-verificar.sh

## Oráculo
- comando: test -f tests/test-oracfit-roi.sh && test -f bin/oracfit-roi.py && ORACFIT_ROOT=$PWD bash tests/test-oracfit-roi.sh && ORACFIT_ROOT=$PWD bash tests/test-verificar.sh && test $(wc -l < bin/oracfit-roi.py) -le 130
