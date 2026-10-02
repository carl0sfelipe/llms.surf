EXECUTE A ESPEC ABAIXO por completo (o cabeçalho YAML e as seções são contrato, não comentário).

---
id: "check-delegacao-1-verificacao"
schema: 1
status: ready
owner: "claude-opus (orquestrador)"
modelo: "grok-4.6-xhigh-fast"
tentativas: 3
bloqueio: false
evidencia: "docs/proposta-check-delegacao.md"
---

# check-delegacao — vale a pena delegar esta spec a este executor?

REGRAS DE OURO (violar qualquer uma = reprovação imediata):
- Workdir: a raiz deste repositório (worktree feat/check-delegacao). Escreva SÓ os arquivos de ENTREGÁVEIS.
- NUNCA git commit, push, reset, checkout, switch, stash, rebase; nada de rm -rf.
- Python stdlib only. Nenhum pip install. Nenhuma chamada de rede, nenhum modelo.
- Nao invente numero, preço, campo, regra ou fonte alem dos listados nesta espec. Valor nao decidido = [A DEFINIR].
- NUNCA use declare const, stub vazio ou `pass` como workaround para passar teste — implemente de verdade.
- Não edite core/precos.json, docs/proposta-check-delegacao.md, tests/fixtures/, model-registry.json.

## Dados verificados (copie SEM ALTERAR)
- Proposta (leia inteira, §2 é o contrato): docs/proposta-check-delegacao.md
- Preços: core/precos.json — `modelos.<id>.in/out` em USD por milhão de tokens; `null` = desconhecido.
  Orquestrador padrão: `claude-opus-5-5`. Placa `qwen-3.8-27b` tem preço 0. `grok-4.6-xhigh-fast` tem null.
- Ledger (opcional): `<workdir>/.dispatch/ledger/mode.jsonl`, uma linha JSON por run com `model_id`, `attempt`, `status`.
- Fixtures (3 specs reais de 2026-10-02): tests/fixtures/delegacao/tr-1-3-catalogo-plano.md (ENTREGÁVEIS com
  ≤ 90 e ≤ 70 linhas), tr-6-7-demanda-politica.md (≤ 60 e ≤ 90 nos ENTREGÁVEIS; os mesmos números também aparecem
  em "Objetivo" e NÃO podem ser contados duas vezes), tel-1-telemetria-backup.md (ENTREGÁVEIS sem orçamento).
- Padrão de teste shell: tests/test-verificar.sh (mktemp, contadores ok/not, exit 1 se falhar).

## Objetivo

`bin/check-delegacao.py <spec> --executor <model_id> [--orquestrador claude-opus-5-5] [--precos core/precos.json]
[--workdir DIR] [--paralelo] [--proteger-contexto] [--json]`

Constantes no topo do arquivo: `TOK_POR_CHAR = 0.25`, `TOK_POR_LINHA = 12`, `VOLTAS = 6`, `FATOR_SAIDA = 1.3`,
`TENTATIVAS_PADRAO = 1.5`, `RAZAO_MAX = 0.5`, `MARGEM = 0.7`.

Medidas:
1. `spec_tok = ceil(len(texto_da_spec) * TOK_POR_CHAR)`.
2. `saida_tok = soma dos N de "≤ N linhas" (aceite também "<= N linhas" e "<= N lines") SÓ dentro da seção cujo título
   contém "ENTREGÁVEIS" (do título até o próximo título "## ") × TOK_POR_LINHA`. Nenhum orçamento → exit 3 com
   `check-delegacao: declare o orçamento de linhas nos ENTREGÁVEIS (ex.: "arquivo.py (≤ 80 linhas)")`.
3. `contexto_tok` = soma de bytes × TOK_POR_CHAR dos caminhos citados entre crases na seção "Dados verificados" que
   existem como arquivo relativo a --workdir (padrão: cwd). Caminho inexistente é ignorado.
4. `tentativas` = média de `attempt` das linhas do ledger com `model_id == executor`, se houver ≥ 3; senão TENTATIVAS_PADRAO.
5. Preços do executor e do orquestrador; qualquer `in`/`out` null ou modelo ausente → exit 4 com
   `check-delegacao: preço desconhecido para <id> — preencha core/precos.json`.

Custos (USD; P em USD por milhão → divida por 1e6):
```
delegar = spec_tok·P_orq_out + saida_tok·P_orq_in + tentativas·(contexto_tok·VOLTAS·P_ex_in + saida_tok·FATOR_SAIDA·P_ex_out)
direto  = saida_tok·FATOR_SAIDA·P_orq_out + tentativas·contexto_tok·VOLTAS·P_orq_in
```

Veredito, nesta ordem (a primeira que decide, decide):
1. executor com `in == 0` e `out == 0` → `DELEGAR`, motivo "executor sem custo por token".
2. `--paralelo` → `DELEGAR`, motivo "orquestrador tem trabalho em paralelo"; `--proteger-contexto` → `DELEGAR`, motivo
   "proteger o contexto do orquestrador".
3. `spec_tok / saida_tok > RAZAO_MAX` → `DIRETO`, motivo "spec é X% da entrega".
4. `delegar <= MARGEM · direto` → `DELEGAR`, motivo "delegar custa X% de fazer direto".
5. senão `DIRETO`, motivo "delegar custa X% de fazer direto".

Saída padrão: UMA linha, ex.: `DIRETO — spec é 91% da entrega (1787 de 1920 tok); delegar ≈ US$0.0612 vs direto ≈ US$0.0499 (executor claude-sonnet-5)`.
`--json`: um objeto com `veredito, motivo, spec_tok, saida_tok, contexto_tok, tentativas, custo_delegar, custo_direto, executor, orquestrador`.
Exit: 0 = DELEGAR, 10 = DIRETO (aviso, não erro), 3 = uso/sem orçamento, 4 = preço desconhecido.

Também: registre o subcomando no `bin/oracfit` ao lado de `verificar`:
`check-delegacao) exec python3 "$SCRIPT_DIR/check-delegacao.py" "$@" ;;` e uma linha de ajuda no bloco de ajuda,
no mesmo estilo da linha de `oracfit verificar`.

## Testes — `tests/test-check-delegacao.sh`
Rode a partir de um diretório temporário vazio como --workdir (contexto 0, ledger ausente) e prove:
- tr-1-3 com `--executor claude-sonnet-5` → exit 10, linha começa com `DIRETO`; `--json` dá `saida_tok == 1920`
  e `spec_tok == ceil(len(arquivo)/4)` calculado no próprio teste.
- tr-6-7 com `--executor claude-sonnet-5` → exit 10, e `--json` dá `saida_tok == 1800` (não 3600).
- tr-1-3 e tr-6-7 com `--executor qwen-3.8-27b` → exit 0, `DELEGAR`.
- tel-1 → exit 3 e a mensagem cita "orçamento de linhas".
- `--executor grok-4.6-xhigh-fast` → exit 4 e cita core/precos.json.
- `--paralelo` com claude-sonnet-5 → exit 0 e motivo cita "paralelo".
- ledger com 3 linhas `model_id=claude-sonnet-5, attempt=3` no --workdir → `tentativas == 3` no `--json`.
- spec sintética curta (ENTREGÁVEIS com "≤ 400 linhas") SEM contexto, com claude-sonnet-5 → exit 10 `DIRETO` pela
  regra 5 (delegar ≈ 92% de direto: o executor pago só compensa quando há muito para ler/iterar).
- a mesma spec citando em "Dados verificados" um arquivo de 200000 bytes criado no --workdir (`contexto_tok == 50000`)
  → exit 0 `DELEGAR` pela regra 4 (o laço de leitura roda no preço do executor).
- `bin/oracfit check-delegacao ...` funciona igual ao script.

## Barra
- nome: tests/test-check-delegacao.sh verde; tests/test-verificar.sh e tests/test-claude-code-cost.sh continuam verdes
- como fetchar: ORACFIT_ROOT=$PWD bash tests/test-check-delegacao.sh
- como comparar: fail=0; git status mostra só ENTREGÁVEIS

## ENTREGÁVEIS
- bin/check-delegacao.py (≤ 160 linhas)
- bin/oracfit (só a linha do case e a linha de ajuda)
- tests/test-check-delegacao.sh (≤ 140 linhas)

## VERIFICAÇÃO
- ORACFIT_ROOT=$PWD bash tests/test-check-delegacao.sh
- ORACFIT_ROOT=$PWD bash tests/test-verificar.sh
- ORACFIT_ROOT=$PWD bash tests/test-claude-code-cost.sh

## Oráculo
- comando: test -f tests/test-check-delegacao.sh && test -f bin/check-delegacao.py && ORACFIT_ROOT=$PWD bash tests/test-check-delegacao.sh && ORACFIT_ROOT=$PWD bash tests/test-verificar.sh && ORACFIT_ROOT=$PWD bash tests/test-claude-code-cost.sh && test $(wc -l < bin/check-delegacao.py) -le 160
