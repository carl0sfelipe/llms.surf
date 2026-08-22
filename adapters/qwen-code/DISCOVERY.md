# DISCOVERY — qwen-code
Data: 2026-07-24T22:03:30Z

## CLI AUSENTE neste host

Comando: command -v qwen
```
(sem saída — binário não encontrado no PATH)
```
Comando: qwen --help
```
(eval):28: command not found: qwen
zsh: command not found: qwen
```

**Consequência (PRD seção 7, Passo 0):** adapter marcado **experimental**.
Nenhuma flag pode ser documentada — não há `--help` real para citar (regra 11.1).
O acesso a modelos Qwen hoje se dá via opencode (`cli_hints.opencode` no model-registry.json),
não via CLI `qwen` própria. Ver PRD seção 4.4: qwen code é orquestrador, executor delega ao opencode.
