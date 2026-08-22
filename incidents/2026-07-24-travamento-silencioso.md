---
id: 2026-07-24-travamento-silencioso
titulo: Travamento silencioso — 52min perdidos e resgate manual do humano
data: 2026-07-24
recorrivel: sim
regra: 12,13,14,15,16
status: promovido
---

# Travamento silencioso — 52min perdidos e resgate manual do humano

## Sintoma

Dois eventos distintos no mesmo dia. **Não conflatar:** cada um tem causa própria.

**Evento A — dispatch pendurado.** Dispatch de um fix de ~10 linhas para `opencode/deepseek-v4-flash-free` ficou 52 minutos vivo. Arquivo de output: 0 bytes. Nenhum commit.

**Evento B — comando do agente pendurado.** Um comando único juntando validação local + smoke test de rede + `git commit` ficou parado. O humano perguntou "vai demorar?"; a pergunta **não destravou**. Ele teve que interromper manualmente para o trabalho seguir.

## Causa

**Evento A — evidência direta.** O prompt não existia no banco de sessões:

```bash
sqlite3 ~/.local/share/opencode/opencode.db \
  "SELECT COUNT(*) FROM message WHERE data LIKE '%BUG CONFIRMADO%'"
# 0
```

Zero. A sessão nunca foi criada — travou **antes** de falar com o modelo. Correlação temporal: outro agente (Hermes) esteve ativo das 18:06 às 18:58; às 18:59, o mesmo comando respondeu em 2–6s. Agravante: `opencode.db` com 944 MB, 80% na tabela `event` (`message.updated.1` sozinho = 593 MB).

A hipótese confortável — "modelo free é lento" — caiu com **uma** query. Diagnóstico por plausibilidade estava errado.

**Evento B — não determinada.** O retorno do harness registra a chamada como rejeitada; o humano relata que ficou parado até interromper. Não há evidência suficiente para afirmar o mecanismo. O que é fato: o comando não tinha teto, não emitia sinal de vida, e a mensagem do humano não o alcançou.

**Erro de conduta associado:** o Evento B foi explicado usando a causa de um teste posterior (um `sleep 35` deliberado). Conflatar dois eventos vira desculpa e destrói a confiança de quem depende do relato.

## Correção aplicada

| Camada | Mecanismo | Onde |
|---|---|---|
| Antes | gate recusa despachar com outro agente ativo | `bin/pre-dispatch-check.sh` (gate 0) |
| Durante | watchdog mata dispatch sem output novo | `bin/dispatch.sh` (`DISPATCH_SILENT_LIMIT`, default 300s) |
| Teto absoluto | `DISPATCH_TIMEOUT`, default 1800s | `bin/dispatch.sh` |
| Qualquer comando | teto explícito, exit 124 | `bin/with-timeout.sh` (macOS não tem `timeout(1)` nem `gtimeout`) |

Modelo lento **não** é morto: escreve no log, o contador de silêncio zera. Só morre silêncio real.

Narrativa longa: `lessons/2026-07-24-dispatch-travado.md`.

## Pode acontecer de novo?

**Sim** — enquanto houver comando sem teto, agente concorrente, ou relato que confunde eventos. Por isso virou as regras **12, 13, 14, 15** do `SKILL.md` (teto obrigatório; nunca juntar validação+rede+commit; anunciar duração >10s; silêncio ≠ progresso) e a regra **16**, que criou este próprio módulo de feedback.

Regra de ouro derivada: **se o humano precisou perguntar "travou?", o sistema já falhou.**
