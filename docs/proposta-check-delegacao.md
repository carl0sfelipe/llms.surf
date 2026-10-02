# Proposta — `check-delegacao`: vale a pena delegar esta tarefa? (2026-10-02)

> Origem: pergunta do dono depois de 3 despachos ao Sonnet no `inference-paraguai` —
> "o Sonnet entrega quase mais rápido do que o tempo que você gasta montando e corrigindo specs".
> Status: proposta, nada implementado.

## 1. O que os 3 despachos de hoje mostram (medido)

| Run | Spec que o orquestrador escreveu | Entregue pelo executor (código + testes) | Executor | Tentativas |
|---|---|---|---|---|
| `6916e35a` TR-1+TR-3 | 7,1 KB | ~13 KB (398 linhas inseridas) | 80 s | 1 |
| `0d0581d7` TR-6+TR-7 | 7,2 KB | ~11 KB (5 KB código + 159 linhas de teste) | 129 s | 1 |
| `e36e4daa` TEL-1 | 7,0 KB | ~12 KB (391 inserções em 18 arquivos) | 88 s | 1 |

Fontes: `wc -c /opt/inference/dispatch/*.md`, `git show --stat`, `.dispatch/ledger/mode.jsonl`.

- **Razão spec ÷ entrega ≈ 0,55–0,65.** O orquestrador (o modelo mais caro) escreveu mais da metade do volume
  que teria escrito fazendo direto, e ainda **leu tudo de volta** na revisão — que não é opcional: foi a revisão,
  não o oráculo, que achou o `umask` faltando no backup e o teste que fixava estado transitório.
- **Todas passaram na 1ª tentativa** → o ganho clássico da delegação (o laço de tentativa/erro rodar no contexto
  barato) **não aconteceu**.
- O executor também gasta: lê o contexto, roda testes. Com o orquestrador tendo escrito 60% da saída, a soma
  provavelmente ficou **igual ou pior** do que fazer direto — mas ninguém sabe, porque:
- **O ledger não mede custo**: `estimated_cost` é fixo em `"0"` (`bin/dispatch-mode.sh:556`); o registro não tem
  preço; o runner claude-code recebe `total_cost_usd`/`usage` no JSON do `claude -p` e descarta.

**Conclusão:** delegar ao Sonnet tarefa pequena, bem especificada e que passa de primeira é custo, não economia.
Delegar continua certo quando: (a) o executor é ~grátis (placa local); (b) a saída é grande perto da spec;
(c) a tarefa vai iterar muito (o laço queima tokens do executor, não do orquestrador); (d) o orquestrador tem
outra coisa para fazer em paralelo; (e) o contexto do orquestrador precisa ser protegido (sessão longa).

## 2. A verificação — `bin/check-delegacao.py <spec> --executor <model_id>`

Roda **antes** de escrever a spec completa (sobre um rascunho de 5 linhas) e de novo antes do dispatch.

### Entradas (todas medidas, nada chutado)
- `spec_tok` = caracteres da spec ÷ 4.
- `saida_tok` = soma dos orçamentos de linhas dos ENTREGÁVEIS (`≤ N linhas`) × tokens/linha (calibrado do ledger;
  começa em 12) — sem orçamento declarado → a verificação recusa ("declare o tamanho").
- `contexto_tok` = tamanho dos arquivos citados em "Dados verificados".
- preços: campos novos `preco_in`/`preco_out` (USD/Mtok) e `cota_peso` (fração da cota de assinatura por Mtok)
  no `model-registry.json`; placa/local = 0.
- `tentativas_esperadas` = média do ledger para (executor, classe da tarefa); sem histórico = 1,5.

### Fórmula
```
delegar = spec_tok·P_orq_out + saida_tok·P_orq_in (revisão)
        + tentativas·(contexto_tok·VOLTAS·P_ex_in + saida_tok·1,3·P_ex_out)
direto  = saida_tok·1,3·P_orq_out + tentativas·contexto_tok·VOLTAS·P_orq_in
```
(VOLTAS = idas e vindas de ferramenta por tentativa, calibrado do ledger; começa em 6.)

### Veredito
| Condição | Saída |
|---|---|
| executor com preço 0 (placa) | `DELEGAR` |
| `spec_tok / saida_tok > 0,5` e executor pago | `DIRETO` (exit 10 — aviso, não erro) |
| `delegar ≤ 0,7 · direto` | `DELEGAR` |
| `--paralelo` ou `--proteger-contexto` declarados | `DELEGAR` com o motivo no ledger |
| senão | `DIRETO` |

A saída imprime as duas contas e o motivo numa linha — o dono vê por que.

## 3. Modo direto que continua visível — `oracfit verificar <spec> <task>`

`DIRETO` não pode significar "sumiu do painel" (regra do dono: tudo pelo llms.surf, incidente de 2026-09-29).
`oracfit verificar` não chama modelo: confirma o oráculo **vermelho antes**, espera o orquestrador implementar,
roda o oráculo, grava no ledger com `runner: orquestrador` e aparece no painel como qualquer run. Mesmo gate,
mesma prova, sem pagar a ida e volta.

## 4. ROI medido depois — fechar o ciclo

1. `adapters/claude-code/runner.sh`: ler `total_cost_usd` e `usage` do JSON e passar ao ledger
   (`executor_cost_usd`, `executor_in_tok`, `executor_out_tok`). Hoje: descartado.
2. Ledger ganha `spec_tok`, `saida_real_tok` (diff do git), `veredito_check` e `motivo`.
3. `oracfit roi [--semana]`: por executor e classe — custo delegado real vs. direto estimado, % de 1ª tentativa,
   e recalibra `tokens/linha`, `VOLTAS` e `tentativas_esperadas`. A verificação aprende com os próprios runs.
4. Gate de honestidade: um `DELEGAR` cujo ROI real saiu < 1 três vezes seguidas na mesma classe vira incidente
   ("a regra de delegação está errada para esta classe").

## 5. Ordem de construção

| # | Peça | Tamanho | Quem (pela própria regra) |
|---|---|---|---|
| 1 | runner grava `total_cost_usd`/`usage` no ledger | ~15 linhas | **direto** (pequeno, spec > código) |
| 2 | campos de preço/cota no registro (claude-sonnet-5, opus, placa = 0) | dados | direto |
| 3 | `bin/check-delegacao.py` + testes com os 3 runs de hoje como casos | ~150 linhas | placa (grátis) ou direto |
| 4 | `oracfit verificar` | ~60 linhas | direto |
| 5 | `oracfit roi` | ~120 linhas | placa |

Caso de teste obrigatório: os 3 runs desta tabela devem sair `DIRETO` para executor `claude-sonnet-5` e
`DELEGAR` para a placa.
