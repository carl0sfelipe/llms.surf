---
id: 2026-08-09-content-factory-morte-silenciosa-sem-watchdog
titulo: content_factory <host-local> morreu em ~4s e ficou ~8min “rodando” sem verificação
data: 2026-08-09
recorrivel: sim
regra: 42
status: promovido
repo: <repo-cliente>.live-imports (CF) + Cursor agent shell (macOS)
---

# content_factory <host-local> — morte silenciosa sem watchdog

## Sintoma

Pedido do humano: rodar content-factory do nicho <host-local> **sem timeout**.

1. **18:52:42** — launch via Cursor Shell: `nohup uv run python main.py … --clean --max-feedback 20 &` (PID 2763).
2. **18:52:46** — último log: `Executing task: T1-HUNT` + `LiteLLM completion() model=deepseek-v4-flash`. Arquivo parou em **14866 bytes**.
3. **~19:00** — humano pergunta `status`. PID 2763 **já morto**. Sem Traceback, sem `Killed`, sem footer de exit no log.
4. **19:01** — “restart robusto” com `setsid` → **falha imediata**: `(eval):8: command not found: setsid` (macOS não tem `setsid` no PATH). Log novo = 36 bytes só com o erro. Processo nunca subiu.

Estado: **nenhum** `main.py` / <host-local> vivo; artefato só `research-context.json` (pré-pesquisa SearXNG). Zero T1–T4.

## Causa raiz (dois erros empilhados)

### A — Processo órfão frágil / sessão do agent

O `nohup … &` foi lançado **dentro** do Shell tool do Cursor (`block_until_ms: 15000`). Ao terminar o comando foreground, a sessão do harness encerra. Em macOS/Cursor, isso frequentemente **mata a árvore** (SIGHUP/SIGTERM no process group) mesmo com `nohup`, se o job não foi `disown`/daemonizado fora do grupo da sessão.

Evidência:
- Viveu **~4s** de trabalho útil (18:52:42 → 18:52:46).
- Morte **sem** linha de erro no log (corte no meio do LiteLLM).
- Mesma classe de incidente Oracfit: `2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi` / travamento silencioso — **silêncio ≠ progresso**.

Não há evidência de OOM no log da app; a hipótese mais parcimoniosa é **reaper da sessão do agent**, não falha do DeepSeek.

### B — Restart sem verificação de 1 segundo

`setsid` foi usado sem `which setsid` / `command -v setsid`. Em Darwin isso **não existe** como binário de userland padrão → restart “robusto” foi um no-op barulhento.

## Tempo perdido (ocioso evitável)

| Intervalo | Duração | O que aconteceu | Evitável com |
|---|---|---|---|
| 18:52:46 → ~19:00 | **~8 min** | Agente/humano acharam que o pipeline rodava; DeepSeek/T1–T4 **não** rodavam | Heartbeat: `ps -p $PID` + `stat` mtime do log a cada 30–60s; ou `tail -f` em background monitor |
| 19:01 restart setsid | **~1–2 min** + 1 turno LLM | “Fix” que não lança nada | `command -v setsid` **antes** de usar (custo <1s) |
| Trabalho útil real da 1ª run | **~4 s** | Só SearXNG + start T1-HUNT | — |
| Run matinal anterior (contexto) | **90 min** TIMEOUT Oracfit 5400s | Outro incidente (teto externo); não confundir com esta morte | Já documentado na sessão |

**Ociosidade atribuível a falta de verificação simples nesta morte:** ~**8–10 minutos** de relógio em que se podia ter detectado “PID morto / log parado” com comandos triviais.

Custo adicional: turno do agente respondendo “status” + investigação + este incidente (em vez de pipeline avançando).

## Verificações simples que teriam evitado o ocioso

Checklist mínimo pós-`nohup` (copiar):

```bash
# 1) detach real no macOS (sem setsid)
nohup env … uv run python -u main.py … >>"$LOG" 2>&1 &
PID=$!
disown $PID 2>/dev/null || true
echo $PID > /tmp/bmad-<host-local>/run.pid

# 2) smoke 15–30s — NÃO declarar "rodando" antes
sleep 15
kill -0 "$PID" 2>/dev/null || { echo "MORREU cedo"; tail -50 "$LOG"; exit 1; }
# log tem que CRESCER
SIZE1=$(wc -c <"$LOG")
sleep 10
SIZE2=$(wc -c <"$LOG")
[ "$SIZE2" -gt "$SIZE1" ] || echo "WARN: log parado — possível hang/morte"

# 3) never use setsid on macOS without check
command -v setsid >/dev/null || echo "use nohup+disown / launchd"
```

Monitor durante a run (a cada 5–10 min, ou loop):

```bash
PID=$(cat /tmp/bmad-<host-local>/run.pid)
kill -0 "$PID" || echo "DEAD"
stat -f '%Sm %z' /tmp/bmad-<host-local>/run-latest.log
grep -E 'Executing task:|decision:' /tmp/bmad-<host-local>/run-latest.log | tail -3
```

## Correção / follow-up

| Ação | Status |
|---|---|
| Documentar incidente (este arquivo) | feito |
| Relançar CF com `nohup`+`disown`+smoke 30s + PID file | pendente (humano pediu investigacao primeiro) |
| Wrapper `bin/run-content-factory-detached.sh` (macOS-safe) | recomendado |
| Agente: **nunca** dizer “aviso quando terminar” sem watchdog que de fato checa | regra de conduta |

## Pode acontecer de novo?

**Sim** — qualquer `nohup &` dentro do Shell tool do Cursor sem `disown`/daemon + sem heartbeat de log/PID.

**Trigger de repetição:** se você lançou um job longo no agent e só olhou o log **quando o humano perguntou status**, o sistema já falhou (mesma regra de ouro do incidente 2026-07-24: *se o humano precisou perguntar "travou?", o sistema já falhou*).

## Relação com incidentes Oracfit

- `incidents/2026-07-24-travamento-silencioso.md` — silêncio ≠ progresso; humano resgata
- `incidents/2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi.md` — árvore de processos / kill incompleto
- `incidents/2026-07-25-grupo-nao-basta-neto-com-set-m-escapa.md` — detach em macOS é especial

## Recorrência — 2026-08-09, mesmo dia (3ª manifestação)

O pid **4533** (`opencode run` headless, nicho <host-local> SER 6800U) ficou **2h13min**
"rodando" após o trabalho real ter terminado. Evidência (verificada em 2026-08-09 ~21:25):

- **18:49** — run `AA3CE24A` start (mtime dos artefatos de inbox).
- **21:16** — T4 do <host-local> gravado (`status: APPROVED`) pelo processo python do CF.
  O `main.py` do CF **encerrou** pouco depois (nenhum filho `main.py` na árvore do 4533).
- **~21:25** — diagnostiquei o 4533: `ps` mostra estado `S` (sleeping), 1.4% CPU, RSS 130MB.
  O subshell que o monitorava (pid 84768, `sleep 300; ps -p 77586`) **já tinha terminado** —
  quem esperava o run desistiu/encerrou, mas o wrapper `opencode run` (4533) continuou vivo.
- Nenhum `main.py`/crewai ativo como filho do 4533. Só h2-daemon + ai-usage-hub MCP.
- **Conclusão**: órfão. ~2h de relógio em que o processo parecia "rodando" mas não fazia
  trabalho útil. Detectei SÓ porque o humano mandou verificar (regra de ouro violada de novo).

**Escalada da severidade**: a 1ª manifestação foram ~8min de ociosidade; esta foram
**~2h13min**. Sem mecanismo, o intervalo cresce — ninguém fecha o processo órfão.

**Por que o `regra: shell-detach, which-before-use, heartbeat-log` (em prosa) não conteve**:
são três marcadores soltos, não uma regra enforced. Nada obriga o dispatch a checar
`kill -0 $PID` + mtime do log periodicamente. O `dispatch.sh` TEM watchdog (`DISPATCH_SILENT_LIMIT`),
mas o pid 4533 era um `opencode run` invocado **fora** de `dispatch.sh` (sem watchdog)
— então o mecanismo existente não cobriu. O buraco é: processos despachados por caminhos
que NÃO passam pelo `dispatch.sh` não têm watchdog nenhum.

Candidata a regra (promover — decidir mecanismo entre: wrapper obrigatório para qualquer
job longo / heartbeat no inbox por PID / checker periódico):

> Qualquer processo de job longo (opencode run, main.py do CF, nohup&) DEVE ser
> monitorado por heartbeat que confirme `kill -0 $PID` E mtime crescente do log a cada
> N segundos. O watchdog do `dispatch.sh` só cobre o que passa por ele; jobs lançados
> por outros caminhos (opencode direto, scripts ad-hoc) ficam órfãos. Sem heartbeat,
> processo morto parece vivo por horas. Mecanismo: nenhum hoje para jobs fora do dispatch.sh.

Interage com: regra 12 (teto de tempo — mas teto não detecta órfão que não consome),
regra 14 (anunciar duração — não ajuda se o processo mente sobre seu próprio estado),
regra 32 (regra sem mecanismo é dívida — esta é dívida até existir heartbeat para jobs
fora do dispatch).

interage_com: 12 (REFORÇA: teto mata processo que trava, mas não detecta órfão que
'roda' sem consumir — 42 estende a proteção para o caso que 12 não cobre), 14
(RESTRINGE: anunciar duração esperada é necessário mas insuficiente — o humano só sabe
que passou do tempo, não que o processo morreu cedo), 32 (INSTANCIA: esta regra declara
explicitamente SEM MECANISMO para jobs fora do dispatch.sh — dívida assumida, não regra
vazia), 1 (NÃO CONFLITA: orquestrador despacha, não escreve bulk; mas o orquestrador que
lança main.py/opencode direto sem watchdog viola 42 mesmo respeitando 1), 36 (NÃO
CONFLITA: publicação é outro domínio, mas ambos compartilham 'nada obriga' como raiz).
Sobreposição de termo alertada pelo `incident.sh promote`: 36/terminar, 1+23+39/trabalho,
14/travou, 12/wrapper — sobreposição NÃO é conflito. O que pode quebrar: se um futuro
wrapper obrigatório (mecanismo de 42) for barulhento — heartbeat a cada Ns gravando no
inbox pode poluir o ledger; mitigar com arquivo .heartbeat separado, não no events.jsonl.
