# Adaptador cursor ao vivo: stream-json vira eventos no painel

## Objetivo
Hoje `adapters/cursor/runner.sh` chama `cursor-agent --output-format json` e só entrega no fim:
o dono vê "rodando" sem saber o que o Cursor está fazendo nem se o contexto cresce. Com
`--output-format stream-json`, cada leitura/edição/pensamento vira evento em `events.jsonl`
e aparece no feed `tool_call`/`thinking` do "Run ao vivo" (`panel/index.html`).

## Arquivos
- `adapters/cursor/runner.sh` (alterar)
- `adapters/cursor/stream-events.py` (novo)
- `adapters/cursor/DISCOVERY.md` (anotar o formato stream-json verificado)

## Contrato
1. Com `DISPATCH_RUNNER_FORMAT_JSON` = 1 (default) o runner passa `--output-format stream-json`
   (em vez de `json`). Com 0, não passa `--output-format` (modo texto, como hoje).
2. A saída do cursor-agent passa por `python3 adapters/cursor/stream-events.py` linha a linha,
   SEM bufferizar: cada linha crua sai no stdout na hora (o log do run fica ao vivo).
3. Se `ORACFIT_RUN_ID` estiver setado, o parser acrescenta ao arquivo
   `${ORACFIT_EVENTS_FILE:-$ORACFIT_WORKDIR/.dispatch/logs/events.jsonl}` (cria o dir) linhas no
   formato de `bin/lib-oracfit-events.sh` (`{"v":1,"ts":ISO,"run_id":…,"type":…,…}`), com flush
   por linha:
   - `tool_call` para cada `{"type":"tool_call","subtype":"started"}`: `tool` = nome da chave
     `<x>ToolCall` sem o sufixo, minúsculo (readToolCall → `read`, editToolCall → `edit`);
     `preview` = `[<tool>] <args.path relativo ao ORACFIT_WORKDIR, ou args.command/pattern/query>`,
     no máximo 160 caracteres.
   - `thinking` para cada `{"type":"thinking","subtype":"completed"}`: `detail` = deltas
     acumulados desde o último completed, no máximo 200 caracteres. Sem deltas → não emite.
   - `metric` com `name=context_bytes` e `value=<bytes da stream até aqui>` a cada 10 tool_call.
   - `metric` com `name=cursor_usage`, `input_tokens`, `output_tokens`, `cache_read_tokens`,
     `duration_ms` quando chegar `{"type":"result"}` (campos de `usage`).
   Sem `ORACFIT_RUN_ID`: só repassa as linhas, não cria arquivo.
4. Linha que não é JSON é repassada ao stdout sem quebrar o parser.
5. Exit codes do contrato continuam (0 ok, 1 erro, 2 rate-limit, 3 uso/auth, 4 quota), avaliados
   sobre a saída completa, e o exit do cursor-agent não pode se perder no pipe (use PIPESTATUS).
6. BUG verificado: a linha `system/init` tem o campo `apiKeySource`, que casa com a regex de auth
   `api.?key` e faz o runner sair 3 num run bem-sucedido. A detecção de auth/429/quota olha só
   linhas que NÃO são JSON e o `result` de `{"type":"result","is_error":true}`.

## Dados verificados (o que você PODE usar)
Amostra real do `cursor-agent 2026 --output-format stream-json` (Grok 4.6) em
`tests/fixtures/cursor-stream-sample.jsonl`: tipos `system/init`, `user`, `thinking` (`delta` com
`text`, `completed`), `assistant`, `tool_call` (`started`/`completed`, com `tool_call.readToolCall`
ou `tool_call.editToolCall` e `args.path`), `result` (`usage.inputTokens`, `outputTokens`,
`cacheReadTokens`, `duration_ms`).

## Regras
- Nao invente flag do cursor-agent, tipo de evento ou campo alem dos listados nesta spec.
- NUNCA edite tests/test-cursor-stream.sh nem a fixture; NUNCA faça o runner detectar o teste (anti-fantasma).
- NUNCA use declare const (não se aplica: é bash/python) — e nenhum stub no lugar de chamar o cursor-agent.
- Python stdlib. Não altere outros adaptadores.

VERIFICACAO: bash tests/test-cursor-stream.sh | grep -q 'PASS test-cursor-stream'

## Barra
O dono (TDAH) acompanha pelo painel, de outro PC, o que o Cursor está fazendo e se o contexto cresce.

## Oráculo
- comando: bash tests/test-cursor-stream.sh
