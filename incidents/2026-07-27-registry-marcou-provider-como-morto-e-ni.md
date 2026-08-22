---
id: 2026-07-27-registry-marcou-provider-como-morto-e-ni
titulo: Registry marcou provider como morto e ninguem revalidou depois da correcao
data: 2026-07-27
recorrivel: sim
regra: nao — virou codigo (classe C)
status: fechado
interage_com: |
  Reforca a regra 25 (dry-run antes de gravar em store) — a 25 protege a ESCRITA,
  este protege a LEITURA de dado ja gravado. Reforca a antiga regra 20, hoje em
  bin/audit-registry-ids.sh: aquela cobre id que nunca existiu, esta cobre id que
  existia, foi marcado morto, e ressuscitou.
  Nao supera nenhuma. Risco da combinacao: o dry-run da 25 da a sensacao de que o
  dado gravado esta certo para sempre — foi exatamente o que aconteceu aqui.
---

# Registry marcou provider como morto e ninguem revalidou depois da correcao

## Sintoma

Onze entradas do `model-registry.json` estavam marcadas com `id_status` dizendo
que o provider NVIDIA tinha "auth quebrada" e que testar seria "desperdicio de
tempo e cota". Duas delas em texto explicito:

```
PULADO-POR-NVIDIA-401 (regra 4, 2026-07-25) — ... provider nvidia tem auth
quebrada (todos os testes nvidia neste registry falharam Unauthorized 401).
Testar seria desperdicio de tempo e cota — cli_hints NAO adicionado.
```

Ao mesmo tempo, o `RUNBOOK-dispatch.md:104` afirmava o contrario: "O provider
NVIDIA funciona, mas so dentro do vault". Dois documentos do mesmo repositorio,
sobre o mesmo provider, em desacordo — e ninguem tinha reconciliado.

## Causa

A marcacao foi feita em 2026-07-25. A credencial NVIDIA foi corrigida **depois**
disso: o usuario gerou chave nova e a colocou no vault. Nada no framework
reexamina `id_status` quando a causa da falha e removida.

Evidencia — bateria de 2026-07-27, os 11 ids remedidos por
`agent-vault run --vault default -- opencode run --model <candidato>`:

| Resultado | Quantos |
|---|---|
| OK | 7 |
| 410 Gone (modelo aposentado) | 3 |
| sem permissao na conta | 1 |
| **401 Unauthorized** | **0** |

Nenhum 401. A afirmacao "auth quebrada" era verdadeira em 25/07 e falsa em 27/07,
mas o registry continuou afirmando.

Prova de que o vault e a causa da diferenca, e nao outra coisa:

```
bash bin/smoke-test.sh nemotron-3-nano-30b-a3b                    -> OK (5s)
DISPATCH_NO_VAULT=1 bash bin/smoke-test.sh nemotron-3-nano-30b-a3b -> 401 (3s)
```

## Correção aplicada

**Mecanismo, nao regra.** O erro nao foi de disciplina — foi de arquitetura: o
dado exigia que alguem lembrasse de revalidar.

1. `adapters/opencode/runner.sh:86-94` — todo modelo com prefixo `nvidia/` passa
   automaticamente por `agent-vault run`. Antes, funcionava so para quem lembrava
   de invocar o vault na mao; agora o wrapper resolve, porque e o unico lugar que
   sabe qual provider o modelo usa. `DISPATCH_NO_VAULT=1` desliga, para teste.
2. `bin/check-saude.sh` — nova checagem de `id_status` vencido: acusa toda entrada
   que afirma falha de provider (401, auth, sem saldo, quota) com data anterior a
   14 dias. Afirmacao sobre estado de provider apodrece; afirmacao sobre modelo
   aposentado (410) nao.
3. `model-registry.json` — 11 entradas atualizadas com evidencia datada; 7 ganharam
   `cli_hints.opencode` e voltaram a ser despachaveis.

## Pode acontecer de novo?

Sim, e vai — toda vez que uma credencial for trocada, uma cota resetar ou um
provider voltar do ar. Por isso virou codigo e nao regra: uma regra dizendo
"revalide o registry de vez em quando" depende de alguem lembrar, e a medicao de
`incidents/2026-07-25-31-regras-em-dois-dias-e-a-maioria-depen.md` mostrou que
toda violacao registrada foi de regra sem mecanismo.

A licao que generaliza: **`id_status` que afirma estado de PROVIDER tem prazo de
validade; `id_status` que afirma propriedade do MODELO nao tem.** "401" envelhece
em dias. "410 Gone" nao envelhece.
