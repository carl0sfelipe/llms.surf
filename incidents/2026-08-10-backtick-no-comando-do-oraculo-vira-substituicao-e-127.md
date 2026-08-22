---
id: 2026-08-10-backtick-no-comando-do-oraculo-vira-substituicao-e-127
titulo: backtick-no-comando-do-oraculo-vira-substituicao-e-127
data: 2026-08-10
recorrivel: sim
regra: 46
status: promovido
---

# backtick no `- comando:` do oráculo vira substituição (e exit 127 fantasma)

## Sintoma

Overnight tripcstory-mvp1: todo dispatch morria com rc=127 depois de ~7min
(duração exata do oráculo), sem mensagem. Ao mesmo tempo o gate RED do
preflight (`check-oracle.py`) dizia "fails-correctly" — ou seja, o oráculo
"falhava" pelo motivo errado e liberava o dispatch mesmo quebrado.

## Causa

O template/autor escreve a linha do oráculo com markdown:

```
- comando: `cd repo && bash tools/check.sh && bash tools/vqa-oracle.sh`
```

Os dois pontos de consumo fazem `eval` dessa linha:
- `lib-oracfit-gauntlet.sh::oracfit_gauntlet_run_oracle_capture`: `( cd wd && eval "$cmd" )`
- `check-oracle.py::run_oracle`: `bash -c <cmd>`

Com backticks, bash trata o comando inteiro como **substituição de comando**:
executa o pipeline, captura o stdout e tenta executar ESSE stdout como comando
→ `{"ok":true...}: command not found` → exit 127. O oráculo real até roda
(dentro da substituição), mas o resultado é descartado e o 127 domina.

Pior: no preflight, 127 ≠ 0 → `check-oracle.py` classifica "failing for right
reason" e libera o dispatch. O gate RED foi satisfeito por um erro de parsing,
não pela falha real do oráculo. Silencioso nos dois sentidos.

## Correção (aplicada)

Specs tripcstory: removidos os backticks da linha `- comando:` (texto cru).
Verificado: `check-oracle.py` passou a executar o oráculo de verdade
(exit 1 honesto do vqa-oracle, 4m22s).

## Prevenção

1. `check-spec.sh` deve reprovar linha `- comando:` que contenha crase
   (mesma família da regra 2 — "o que o grep casa não é o que o shell roda").
   [A DEFINIR: implementar grep de crase no bloco Oráculo]
2. `check-oracle.py`: exit 127 merece classificação própria
   ("command-not-found / parsing"), não cair no bucket "fails-correctly" —
   127 quase nunca é "falta trabalho".
3. Template `fluxos/_comum/artefato-template.md`: exemplo do `- comando:` sem
   backticks, com nota "texto cru — crase vira substituição no eval".

## Evidência

- rc=127 em 3 ciclos com duração ~7min (=tempo do oráculo), nenhuma msg
- `lib-oracfit-gauntlet.sh:134` extrai a linha crua; `:141` dá `eval "$cmd"`
- após remover crases: evento `oracle_result` some, gauntlet captura o log real
