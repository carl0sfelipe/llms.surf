---
status: corrigido
---
# Runner claude-code sai 0 com toda escrita negada — 5 tentativas queimadas sem um arquivo

`oracfit run normal` com `adapters/claude-code` e `DISPATCH_MODEL_REF=claude-sonnet-5` (spec
`/opt/inference/dispatch/tr-1-3-catalogo-plano.md`, run `ba849e5b`, 2026-10-02). Sem
`DISPATCH_ALLOWED_TOOLS` nem `DISPATCH_UNSAFE`, o `claude -p` não pode escrever: cada Write/Edit
foi negado em silêncio, o CLI respondeu texto e saiu 0. O gauntlet viu `runner_exit 0` +
oráculo vermelho 5 vezes (~5 min de Sonnet) e fechou `fail` — com o gap "test_trocador não
existe", que parece erro do modelo e não da configuração.

## Correção (feita no uso)
Redespacho com allowlist estreita: `DISPATCH_ALLOWED_TOOLS="Read,Write,Edit,Glob,Grep,Bash(python3:*),…"`.

## Correção (feita, branch feat/check-delegacao)
- `adapters/claude-code/resultado.py` lê o JSON do `claude -p`; `runner.sh` sai **3** quando houve Write/Edit negado
  (Bash negado sozinho não derruba) e grava custo/tokens em `$ORACFIT_COST_FILE`.
- `bin/dispatch-mode.sh` para as tentativas em exit 3 (evento `runner_usage_error`) e soma o custo real no ledger
  (`estimated_cost`, `executor_in_tok`, `executor_out_tok`). Prova: `tests/test-claude-code-cost.sh` (11/11), com o
  caso deste incidente: fail em **1** tentativa, não 5.

## Melhoria proposta (lado do serviço)
1. `runner.sh` (claude-code): spec com seção `ENTREGÁVEIS` e sem `DISPATCH_ALLOWED_TOOLS`/`DISPATCH_UNSAFE`
   → exit 3 antes de chamar o modelo ("este run não pode escrever; defina DISPATCH_ALLOWED_TOOLS").
2. Com `--output-format json`, ler `permission_denials` do resultado: não-vazio → exit 3 com a lista,
   em vez de 0. Uma tentativa queimada, não cinco.
3. `oracfit acao add` com o comando pronto quando isso acontecer (o dono vê no painel).
