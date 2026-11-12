---
id: 2026-11-12-model-ref-com-comentario-inline-quebra-a
titulo: model_ref com comentario inline quebra a cadeia do tier
data: 2026-11-12
recorrivel: sim
regra: mecanismo aplicado
status: fechado
---

# model_ref com comentario inline quebra a cadeia do tier

## Sintoma

Um modo customizado criado por `oracfit mode init my_break` (scaffold novo)
não despachava. O run terminava em:

```
✖ cadeia do tier:cheap     # tier:cheap | tier:mid | tier:expensive | tier:vision vazia — nada despachado
ERROR: no model for tier:cheap     # tier:cheap | tier:mid | tier:expensive | tier:vision
```

E o log de eventos carregava o valor inteiro, comentário incluído:

```json
"model_id": "tier:cheap     # tier:cheap | tier:mid | tier:expensive | tier:vision"
```

## Causa

Duas leituras diferentes do mesmo YAML, uma certa e outra não.

`bin/dispatch-mode.sh` lia o ref por texto:

```bash
model_ref="$(grep -E '^\s*model_ref:' "$mode_yaml" | head -1 | sed 's/.*model_ref:[[:space:]]*//' | tr -d '"' || true)"
```

O `sed` tira a chave e o espaço, mas **não tira o comentário inline**: o valor
vinha `tier:cheap     # tier:cheap | tier:mid | ...` e chegava inteiro ao
resolver de tier, que não reconhecia nenhum tier chamado
`tier:cheap     # tier:cheap | ...` — logo, cadeia vazia.

`bin/dispatch-stages.sh` (rotas multi-stage, como `tow`/`unlock_plan`) lê pelo
loader (`lib-oracfit-mode-loader.py dump`), que usa PyYAML — e o PyYAML
descarta o comentário. Por isso o bug só aparecia em modo de stage único:
o scaffold novo tem uma stage, os modos embutidos de multi-stage não.

Agravante: o parser de fallback do próprio loader (`_load_yaml`, usado quando
PyYAML não está instalado) tinha o mesmo defeito — separava `key: value` sem
nunca remover o `# ...` final.

## Correção aplicada

- `bin/dispatch-mode.sh`: o ref passa a ser lido pelo loader YAML, não por
  `grep|sed` — uma única forma de ler o arquivo, e a que o resto do runtime usa.
- `bin/lib-oracfit-mode-loader.py`: `_load_yaml` agora remove comentário inline
  de escalar (`_strip_inline_comment`), com a mesma regra do YAML (o `#` só abre
  comentário quando precedido de espaço e fora de aspas).
- `tests/test-mode-tooling.sh`: seção nova cobre o caminho do StrangER —
  `mode init` → `validate` → `lint` → `run` verde com o scaffold.

## Pode acontecer de novo?

Sim, na mesma forma: qualquer valor escalar lido por texto dentro de um YAML
(commentado) volta poluído. O mecanismo aplicado é o caminho de leitura
(canônico, pelo loader) mais o parser de fallback corrigido — e o teste que
falha se o scaffold voltar a não despachar. Mas a **lição** é mais larga que
este arquivo: regra 32 — toda linha que declara um mecanismo precisa do
mecanismo que executa a mesma leitura. Enquanto um `grep` e um parser lerem o
mesmo YAML, o próximo YAML comentado quebra um dos dois.
