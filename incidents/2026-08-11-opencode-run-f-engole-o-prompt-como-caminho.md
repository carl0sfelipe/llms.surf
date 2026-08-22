---
id: 2026-08-11-opencode-run-f-engole-o-prompt-como-caminho
titulo: opencode run -f e array variadico — se -f vier antes do prompt, o prompt vira caminho de arquivo
data: 2026-08-11
recorrivel: sim
regra: 11.2
status: aberto
interage_com: "2026-08-10-runner-opencode-positiona-comecando-com-hifen-vira-flag (mesma classe: parsing posicional do opencode run)"
---

# `opencode run -f` engole o prompt como caminho

## Sintoma

Smoke de visão da Fase 0 (`opencode/gemini-3.6-flash`):

```
opencode run -m opencode/gemini-3.6-flash -f imagem.png "descreva..."
→ Error: File not found: descreva...
```

O prompt posicional pós-`-f` foi consumido pelo array variádico de arquivos.

## Causa

`-f, --file` é `[array]` no yargs do CLI: consome TODOS os argumentos até a
próxima flag, inclusive o positional da mensagem.

## Fix

Ordem: **prompt posicional primeiro, `-f <arq>` por último**:

```
opencode run -m opencode/gemini-3.6-flash "descreva..." -f imagem.png   # OK (12.6s)
```

Ou `--` explícito antes do prompt se a ordem precisar ser invertida.

## Proteção

- `model-registry.json` (entrada gemini-3.6-flash, id_status) tem a armadilha
  registrada.
- `core/modes/content_factory.yaml:61` (vision_gate) já usa a ordem correta.
- Quem escrever nova chamada de vision com arquivo: prompt ANTES de `-f`.

## Evidência

2026-08-11: falha reproduzida exatamente como no Sintoma; mesma chamada com
arquivo no fim respondeu descrição correta em 12.6s.
