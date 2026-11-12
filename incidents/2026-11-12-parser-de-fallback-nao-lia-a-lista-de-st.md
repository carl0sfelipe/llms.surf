---
id: 2026-11-12-parser-de-fallback-nao-lia-a-lista-de-st
titulo: parser de fallback nao lia a lista de stages de um modo
data: 2026-11-12
recorrivel: sim
regra: mecanismo aplicado
status: fechado
---

# parser de fallback nao lia a lista de stages de um modo

## Sintoma

Em uma máquina sem PyYAML, o loader de modos não enxergava a lista de stages:
`stages` voltava como texto colado, não como lista. Nenhum modo passava na
validação, e o próprio parser estourava:

```
>>> m._load_yaml(open('core/modes/unlock_plan.yaml').read())
AttributeError: 'dict' object has no attribute 'append'
```

Com PyYAML instalado, o mesmo arquivo era lido corretamente. O modo se
comportava de um jeito numa máquina e de outro em outra — o modo é o mesmo, a
máquina não.

## Causa

`bin/lib-oracfit-mode-loader.py` tem dois leitores para o mesmo YAML: o
PyYAML (quando instalado) e o parser mínimo `_load_yaml` (quando não). O
parser mínimo não sabia ler uma lista; ao encontrar `stages:` com valor vazio,
ele colava as linhas seguintes num texto só.

A mesma família do incidente de 2026-11-12 (ref com comentário inline): dois
leitores do mesmo arquivo YAML que discordam entre si. O primeiro incident
corrigiu um leitor; o segundo existia e ninguém tinha reparado, porque o
caminho sem PyYAML quase nunca é exercitado.

## Correção aplicada

- `bin/lib-oracfit-mode-loader.py`: `_load_yaml` reescrito como parser por
  indentação (mapeamentos aninhados, listas de mapeamentos, escalares,
  aspas, blocos `>` e `|`, comentário inline). Ele agora concorda com o PyYAML
  arquivo a arquivo.
- `bin/lib-oracfit-mode-loader.py`: o loader recusa uma stage com `model_ref`
  **e** `command` ao mesmo tempo — o runtime chamaria o modelo e jogaria o
  comando fora sem dizer nada.
- `tests/test-mode-loader.sh`: T1 compara a árvore do parser de fallback com a
  do PyYAML em **todos** os `core/modes/*.yaml` e `examples/*.yaml`; T2 exige
  que a lista de stages seja encontrada; T3 exige a recusa da stage dupla; T4
  exige que o comentário inline fique fora do valor.

## Pode acontecer de novo?

Sim, na mesma família: qualquer caminho de código que leia o mesmo arquivo por
dois leitores independentes precisa de um gate que compare os dois. O
mecanismo aplicado está em `tests/test-mode-loader.sh` — a comparação é
mecânica e roda na bateria. Um parser de fallback que não é comparado com o
leitor principal é um parser que vai divergir em silêncio.
