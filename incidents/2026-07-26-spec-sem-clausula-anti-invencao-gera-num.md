---
id: 2026-07-26-spec-sem-clausula-anti-invencao-gera-num
titulo: spec sem clausula anti-invencao gera numero inventado no output
data: 2026-07-26
recorrivel: sim
regra: 35
status: promovido
interage_com: 26
---

# spec sem clausula anti-invencao gera numero inventado no output

## Sintoma

Sessão de 14 despachos (`deepseek-v4-flash-free`, runner opencode) produzindo
documentação de produto — README, dois ADRs, plano, pesquisa, PRD e épicos.
Todos os 14 terminaram com `exit_status: ok`, formato correto e instrução
explícita obedecida.

Ainda assim, **todo refinamento teve pelo menos um número inventado para
corrigir**. Amostra do que a verificação encontrou:

| Inventado | Onde | O que a spec pedia |
|---|---|---|
| limiar de 5.000 anúncios | ADR 0001, gatilho de revisão | nada — campo em aberto |
| "abaixo de 60%" | PRD, contra-métrica | "não invente alvo numérico" |
| "menos de 2 GB de RAM" | ADR 0001, escolha de PaaS | nada |
| "amostra de 100 compradores" | PRD, índice de premissas | nada |
| prazos "2-3 meses" por fase | PLANO, roadmap | nada |
| "contratar consultoria de SEO" | PRD, validação de premissa | nada |
| ToS de Flickr e PostImage | ADR 0001, alternativas | só o Imgur foi verificado |

## Causa

O modelo **nunca desobedeceu instrução explícita, nunca quebrou formato e nunca
inventou estrutura**. Toda invenção ocorreu em campo que a spec deixou em
silêncio.

Evidência: as duas specs que produziram documento sem nenhum refinamento
(`pesquisa-ia` e `hermes-doc`) foram as únicas que listaram, item a item, os
dados verificados e disseram explicitamente "não acrescente número nenhum além
destes". As demais não tinham essa cláusula.

Ou seja, a causa não é qualidade do modelo — é **lacuna de spec**. Campo vazio
dentro de uma estrutura pedida é convite a preencher, e qualquer redator, modelo
ou humano, preenche.

Corolário registrado por honestidade: **um dos defeitos foi do orquestrador, não
do executor.** Na spec `epicos-p2` o orquestrador colocou o Épico 11 inteiro na
Onda 1, mas a story 11.3 depende dos Épicos 6 e 7, que vêm depois. O modelo
executou fielmente a ordem errada. O laço de verificação pegou assim mesmo — o
que mostra que ele protege contra erro de qualquer lado, não só do modelo free.

## Correção aplicada

Mecanismo criado em `bin/check-spec.sh` (exigência da regra 32: regra sem código
é dívida). Ele reprova spec sem cláusula anti-invenção, sem bloco de dados
verificados, ou cuja linha `VERIFICACAO:` só faz `ls`.

Rodado contra as specs desta sessão, reprovou **as duas** — inclusive
`pesquisa-ia.md`, que produziu documento sem refinamento. Motivo: a verificação
dela era `ls docs/PESQUISA-ia-conversao.md`, que não prova nada sobre o
conteúdo. O documento saiu bom apesar da verificação fraca, não por causa dela.

Limite honesto do mecanismo, registrado no cabeçalho do script: ele detecta
**ausência** de defesa, não defesa **fraca**. A spec `docs-plano-e-adr.md`
passava no check da cláusula com "nao invente numeros de mercado, prazos em
meses, nem nomes de concorrentes" — e ainda assim gerou limiar de 5.000 anúncios
e "2 GB de RAM", porque a cláusula era estreita. Conferir escopo de prosa
continua sendo trabalho do orquestrador.

Além do código, a correção de processo:

1. Toda spec de despacho declara, em bloco próprio, os dados verificados que
   podem ser usados — e proíbe explicitamente qualquer número, prazo, preço,
   nome de produto ou citação de fonte que não esteja ali.
2. Campo que o orquestrador não decidiu é marcado `[A DEFINIR]` na spec, em vez
   de ficar em branco. Branco é preenchido; marcado, não.
3. O comando de verificação da spec testa a **propriedade semântica**, não a
   existência do arquivo. `ls doc.md` não prova nada; `grep -c "FR-"` prova
   mais; o script que conferiu cobertura 47/47 dos FRs foi o que de fato validou.

## Pode acontecer de novo?

Sim, e vai acontecer em todo despacho de documento com estrutura pedida e campo
não decidido. Não depende do modelo: é propriedade da tarefa. Vale igual para
modelo pago e para o próprio orquestrador — ver o corolário acima.

**Relação com a regra 26** (ausência só se provada): a 26 cobre o agente
afirmando que algo não existe sem provar. Esta cobre o inverso — afirmar que
algo existe (um número, um limiar, um ToS) sem ter recebido a evidência. Mesmo
eixo, direções opostas; nenhuma supera a outra.

## Dados da sessão

```
14 despachos registrados · 869s de modelo · 43.021 tokens de output
35.758 tokens de reasoning · US$ 0,00 · 0 falhas
média de 0,8 refinamento por documento · 2 documentos sem refinamento
```

Fonte: `ledger/ledger.jsonl`, tarefas `plano-adr`, `refinar-adr`,
`refinar-plano`, `refinar-readme`, `pesquisa-ia`, `hermes-doc`, `adr-0002`,
`refinar-adr2`, `prd-p1`, `prd-p2`, `refinar-prd`, `epicos-p1`, `epicos-p2`,
`refinar-epicos`.
