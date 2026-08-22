# Suíte de verificação — como adicionar tarefa

Suíte em `core/verify-suite.json`, consumida por `bin/verify-models.sh`.

## Por que este formato

Duas restrições de projeto, nesta ordem:

1. **Checagem determinística — zero LLM-as-judge.** Se medir exigisse um modelo julgando outro, a medição herdaria a incerteza (e o custo, e o rate limit) do juiz. Todo `check` aqui é decidido por comparação mecânica.
2. **Extensível por modelo leve.** Adicionar tarefa é **acrescentar um objeto JSON** — nunca editar código. Um modelo free consegue estender a suíte lendo só este documento.

## Anatomia de uma tarefa

```json
{
  "id": "slug-curto",
  "tipo": "instruction | reasoning | code | bulk | refinement | long_context",
  "prompt": "o que é enviado ao modelo",
  "check": { "tipo": "<ver tabela>", "...": "parâmetros do check" },
  "por_que": "qual capacidade real do framework esta tarefa mede"
}
```

`por_que` é obrigatório. Tarefa que não mede capacidade usada pelo framework é ruído — a revisão adversarial de 2026-07-25 mostrou uma suíte inteira medindo o que ninguém usava.

## Tipos de check

| `check.tipo` | Parâmetros | Passa quando |
|---|---|---|
| `exato` | `esperado` | resposta normalizada é idêntica |
| `contem_todos` | `termos: []` | todos os termos aparecem (case-insensitive) |
| `nao_contem` | `termos: []` | nenhum termo aparece |
| `regex` | `padrao` | a regex casa em qualquer parte |
| `min_linhas` | `n` | resposta tem ao menos `n` linhas não vazias |
| `json_igual` | `esperado` | resposta parseia como JSON **semanticamente igual** (ignora espaço, ordem de chave e quebra de linha) |
| `combinado` | `checks: []` | **todos** os sub-checks passam |

`json_igual` existe por causa de um falso negativo real: um modelo devolveu JSON válido em três linhas e foi reprovado por `exato`, contaminando o resultado com erro de formatação em vez de capacidade.

## Regras ao escrever tarefa

- **Enunciado sem ambiguidade.** Se dois modelos corretos podem responder diferente e só um passa, o defeito é da tarefa.
- **Resposta curta quando possível**, mas se a capacidade medida for volume (`bulk`), use `min_linhas` + `contem_todos` em vez de tentar `exato`.
- **Nunca dependa de data, aleatoriedade ou estado externo** — a suíte precisa ser reproduzível.
- **Prefira `contem_todos` a `regex`** quando der: erro de regex vira falso negativo silencioso.
- **`nao_contem` é para detectar preguiça**: placeholder (`TODO`, `...`, `lorem`), recusa, ou eco do enunciado.

## O que a suíte deve cobrir

Derivado do que o framework realmente pede ao modelo (`SKILL.md`):

| Capacidade | Por que importa | `tipo` |
|---|---|---|
| Aderência literal a instrução | specs exigem caminhos e mensagens de commit exatas | `instruction` |
| Raciocínio curto | classificação e decisão simples | `reasoning` |
| Código | tarefa padrão do dev júnior | `code` |
| **Bulk output** | papel principal do modelo free (regra 1: >20 linhas vai para free) | `bulk` |
| **Refinamento DELETE/REESCREVA/ADICIONE** | operação mais recorrente do fluxo (ver `fluxos/dispatch/step-04-verify.md`) | `refinement` |
| Contexto longo | specs grandes, arquivos inteiros no prompt | `long_context` |

Antes desta revisão a suíte cobria apenas as três primeiras — media o modelo em tarefas que o framework quase não usa, e declarava `suite_accuracy: 1.0`.

## Adicionar uma tarefa (receita para modelo leve)

1. Abra `core/verify-suite.json`
2. Copie o objeto mais parecido dentro de `tasks`
3. Troque `id`, `prompt`, `check` e `por_que`
4. Valide: `python3 -c "import json;json.load(open('core/verify-suite.json'))"`
5. Rode em dry-run contra um modelo que já funciona:
   `source adapters/opencode/env.sh && bin/verify-models.sh deepseek-v4-flash-free`
6. Se a tarefa reprovar um modelo que você sabe ser capaz, **a tarefa está errada** — conserte o enunciado ou o check, não o modelo

Nunca rode com `--write` antes do dry-run passar (regra 25).
