# Relay Status — Template

> Copiar para `_bmad-output/relay-status.md` no repo do projeto.
> Atualizar ao final de cada rodada de dispatches.

# Relay Status — {{DATA}}

## Última sessão
- **Modelo:** {{quem fez o trabalho}}
- **Commits:** {{hash_inicial}}..{{hash_final}}
- **Status:** DONE | BLOCKED | PARTIAL
- **Bloqueio (se houver):** {{descrição}}

## Fila (próximas tasks)
- [ ] {{task 1}}
- [ ] {{task 2}}

## Rate limit status (atualizado {{HORA}})
| Modelo | Status | Último erro |
|--------|--------|-------------|
| deepseek-v4-flash | OK | — |
| laguna-m.1:free | OK / RATE_LIMITED | {{hora}} |
| nemotron-nano:free | OK / INDISPONÍVEL | {{hora}} |
| sonnet (claude -p) | OK | — |

## Decisões pendentes (dono)
- {{decisão 1}}
- {{decisão 2}}

## Lições desta sessão
- {{lição 1}}
- {{lição 2}}
