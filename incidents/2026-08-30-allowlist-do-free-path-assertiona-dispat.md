---
id: 2026-08-30-allowlist-do-free-path-assertiona-dispat
titulo: allowlist do free path assertiona dispatch pago explicito e marca run legitimo como violado
data: 2026-08-30
recorrivel: sim
regra: 54
status: promovido
---

# allowlist do free path assertiona dispatch pago explicito e marca run legitimo como violado

## Sintoma

Dispatch `webnext-01` (dogfooding 2026-08-30, modelo pago explícito
`cheaperinference/gpt-5.6-luna`, escolhido a dedo pelo dono) terminou verde —
runner_exit 0, oráculo 0 — mas o fechamento gravou no ledger
`allowlist_status: "violado"` e o log do run recebeu
`⛔ allowlist violada: provider_efetivo=cheaperinference`. Run legítimo,
decisão explícita do dono, carimbado como violação de política.

## Causa

Escopo da asserção maior que o escopo da política. `bin/ledger-finalize.sh`
(comentário do próprio código: "tier:* SEMPRE passa por ela; dispatch direto
sem cadeia não tem arquivo e fica fora do escopo da allowlist") assertiona o
`provider_efetivo` contra `data/free-provider-allowlist.json` sempre que o
arquivo `.efetivo` existe — mas `bin/dispatch.sh` aponta `DISPATCH_EFETIVO_FILE`
para TODO dispatch e `bin/run-with-fallback.sh` (RUNNER_ENTRY default) escreve
o arquivo também para modelo pago explícito. Resultado: não existe caminho de
dispatch pago que escape da asserção de um dial que só governa o CAMINHO FREE
(E5-M6/R4). Evidência: ledger.jsonl entrada webnext-01 (allowlist_status
violado) + código citado.

## Correção aplicada

Nenhuma ainda (registro primeiro). Correção proposta: `ledger-finalize.sh`
só assertiona quando o run veio da cadeia free — sinal disponível: o
`.efetivo` passar a carregar um terceiro campo `origem` (tier:free/cheap vs
model-id explícito), gravado pelo `run-with-fallback.sh`; runs de id explícito
gravam `allowlist_status: fora-do-escopo`. Alternativa: dial do dono ganhar
campo `paid_ok` — pior, empurra decisão de política para arquivo de dados.

## Pode acontecer de novo?

Sim — TODO dispatch pago pelo caminho canônico `bin/dispatch.sh` será
marcado violado até a correção. Não promover a regra do SKILL.md ainda
(policy de texto não resolve bug de escopo): a proteção certa é o mecanismo
proposto acima (classe da regra 32: regra sem mecanismo é dívida).
