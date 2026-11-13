# Telemetria — Oracfit

## O que é coletado

Apenas agregados de execução:

- `run_id`, `mode` (flash, frontier), `result` (ok, fail, softfail)
- `flash_work_s`, `frontier_wait_s` (duração em segundos)
- `oracle_exit`, `attempt`, `classify`

## O que NÃO é coletado

- Código fonte, secrets, variáveis de ambiente, caminhos absolutos
- Corpo completo do spec, raw `log_tail` ou payloads intermediários

## Arquivo de uso

O escritor `bin/emit-usage-feedback.sh` grava uma linha por dispatch em:

```
.dispatch/usage/usage.jsonl
```

O diretório padrão é o de uso do repositório. `ORACFIT_USAGE_DIR` redefine
esse diretório. Cada linha é um objeto JSON com os campos `ts`, `source`,
`task`, `result`, `mode`, `exit_code`, `workdir`, `spec`, `spec_sha256`,
`spec_bytes`, `oracle`, `host`, `user`, `uname`, `pwd`, `harness`,
`term_program`, `git_head`, `git_branch`, `git_dirty`, `logs`, `log_tail`,
`dispatch_env` e `extra`.

Registros em markdown também podem aparecer em `incidents/uso/` (diretório
`ORACFIT_USO_DIR` se definida).

### Slot `extra`

`extra` é sempre um objeto JSON. Se o `--extra-json` parseia como objeto,
esse objeto vai no slot como está. Se o texto não parseia, ou parseia mas
não é objeto, o slot vira `{"raw": "<texto original>"}`. Texto cru nunca
entra no slot.

### Slots `mode` e `exit_code`

São um inteiro JSON ou `null`. Texto que não é inteiro vira `null` — a
linha continua parseando.

### Arquivo de rejeitadas

Antes do append, a linha montada é validada. O que não parseia **não**
entra em `usage.jsonl`: vai para `usage.jsonl.rejected` no mesmo
diretório, uma linha por rejeição, cada uma um objeto JSON com o motivo
e o texto original. O escritor avisa no stderr e continua — o incidente
em markdown ainda é gravado.

## Reparo da base

```
python3 bin/oracfit-usage-json.py repair <arquivo> [--in-place] [--out <arquivo>]
```

Lê linha a linha. Linha que já parseia como objeto sai byte a byte. Linha
da classe "dados extras" (chave sobrando depois do valor) é cortada no
fim do primeiro valor JSON completo de nível superior e revalidada. Linha
que não pode ser reparada vai para `<arquivo>.unrecoverable` e aparece no
relatório. Nenhuma linha some em silêncio: reparadas + irrecuperáveis =
as que não parseavam.

Saída padrão: `<arquivo>.repaired`. `--out` define o caminho. `--in-place`
grava no próprio arquivo depois de copiar o original para `<arquivo>.bak`.
Rodar o reparo sobre a saída já reparada não muda nada.

O relatório no stdout conta: total, já parseavam, reparadas, irrecuperáveis.

## Desativação

| Variável | Efeito |
|---|---|
| `ORACFIT_TELEMETRY=0` | Desliga toda coleta |
| `DISPATCH_USAGE_FEEDBACK=0` | Desliga o escritor de uso |
| `ORACFIT_USAGE_DIR` | Diretório de `usage.jsonl` e `usage.jsonl.rejected` |
| `ORACFIT_USO_DIR` | Diretório dos incidentes de uso em markdown |
| `LOG_DIR` | Diretório de logs do dispatch |

## Envio remoto (opcional)

Se a env var `ORACFIT_TELEMETRY_URL` estiver definida, os registros são
enviados via POST para a URL fornecida. Falhas de rede são ignoradas
(fail-open). Nenhuma URL remota é hardcoded. Durante desenvolvimento do
harness, apenas o arquivo local é escrito por padrão.

---

Oracfit — Carlos Felipe
