---
id: 2026-07-27-ls-la-em-symlink-reportou-tamanho-do-lin
titulo: ls -la em symlink reportou tamanho do link e virou arquivo corrompido
data: 2026-07-27
recorrivel: sim
regra: nao — virou codigo (classe C)
status: fechado
interage_com: |
  Mesma familia do incidente 2026-07-27-registry-marcou-provider-como-morto-e-ni:
  afirmacao errada gravada num store vira decisao errada depois. La a causa foi
  dado que envelheceu; aqui foi medicao mal lida na origem.
  Reforca a regra 26 (ausencia so se provada) estendendo para atributo de arquivo:
  tamanho tambem so se prova seguindo o link.
  Reforca a regra 25 (dry-run) pelo lado da leitura, nao da escrita.
---

# ls -la em symlink reportou tamanho do link e virou arquivo corrompido

## Sintoma

Tres documentos do repositorio afirmavam que o modelo local `qwen35-9b` era
inutilizavel:

- `model-registry.json`: "qwen35-9b-uncensored-Q4_K_M.gguf tem 104 bytes (GGUF
  truncado, so metadados) e NAO e utilizavel"
- `RUNBOOK-dispatch.md`: "GGUF truncado, 104 bytes, sem tensores"
- `ESTADO-2026-07-27.md`: "`qwen35-9b` é GGUF truncado de 104 bytes"

O modelo foi excluido de toda decisao de roteamento por causa disso.

## Causa

O caminho e um **symlink**. `ls -la` reporta o tamanho do proprio link — que e o
numero de caracteres do caminho alvo — e nao o tamanho do arquivo apontado.

```
$ ls -la <home-do-dono>/Models/qwen35-9b-uncensored-Q4_K_M.gguf
lrwxr-xr-x  1 mini  staff  104 Jul 16 00:47 ... -> <home-do-dono>/.ollama/models/blobs/sha256-2ca636d9e81d...
```

Os "104 bytes" sao o comprimento da string
`<home-do-dono>/.ollama/models/blobs/sha256-2ca636d9e81d3d23ca9b60c234fe185d30ec082eeba69ce770fdb0c76559a4f5`.

O arquivo real esta integro:

```
$ ls -laL <home-do-dono>/Models/qwen35-9b-uncensored-Q4_K_M.gguf
5627044224 bytes

$ head -c 4 <home-do-dono>/Models/qwen35-9b-uncensored-Q4_K_M.gguf | xxd
00000000: 4747 5546     GGUF
```

5,6 GB e magic `GGUF` correto. Nunca esteve truncado.

O `l` inicial de `lrwxr-xr-x` ja dizia que era link. A informacao estava na tela e
passou batido porque o numero 104 confirmou a hipotese que ja existia ("download
interrompido"). Confirmacao e mais barata que verificacao, e por isso e mais
perigosa.

## Correção aplicada

**Mecanismo, nao regra.**

1. `bin/check-gguf.sh` — valida GGUF por **magic bytes e tamanho seguindo o link**
   (`ls -laL`, `head -c 4`), nunca por `ls -la`. Recusa arquivo com menos de 1 MB
   ou cujo cabecalho nao seja `GGUF`.
2. `model-registry.json`, `RUNBOOK-dispatch.md` e `ESTADO-2026-07-27.md` corrigidos,
   com a causa registrada em vez de apagada.

## Pode acontecer de novo?

Sim. Todo modelo local instalado por ollama, huggingface-cli ou gerenciador de
pacotes vira symlink — e o caminho normal, nao a excecao. Qualquer checagem futura
de "o arquivo baixou inteiro?" cai na mesma armadilha.

A licao que generaliza: **atributo de arquivo obtido sem seguir o link nao e do
arquivo.** Vale para tamanho, data e tipo. `ls -laL`, `stat -L`, `du -L`,
`file -L` — a flag existe justamente porque o default mente sobre o alvo.
