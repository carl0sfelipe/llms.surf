# Telemetria — Oracfit

## O que é coletado

Apenas agregados de execução:

- `run_id`, `mode` (flash, frontier), `result` (ok, fail, softfail)
- `flash_work_s`, `frontier_wait_s` (duração em segundos)
- `oracle_exit`, `attempt`, `classify`

## O que NÃO é coletado

- Código fonte, secrets, variáveis de ambiente, caminhos absolutos
- Corpo completo do spec, raw `log_tail` ou payloads intermediários

## Arquivo local

```
<workdir>/.dispatch/usage/usage.jsonl
```

Registros legados também podem aparecer em `incidents/uso/` via `emit-usage-feedback`.

## Desativação

| Variável | Efeito |
|---|---|
| `ORACFIT_TELEMETRY=0` | Desliga toda coleta |
| `DISPATCH_USAGE_FEEDBACK=0` | Desliga envio remoto legado |

## Envio remoto (opcional)

Se a env var `ORACFIT_TELEMETRY_URL` estiver definida, os registros são
enviados via POST para a URL fornecida. Falhas de rede são ignoradas
(fail-open). Nenhuma URL remota é hardcoded. Durante desenvolvimento do
harness, apenas o arquivo local é escrito por padrão.

---

Oracfit — Carlos Felipe