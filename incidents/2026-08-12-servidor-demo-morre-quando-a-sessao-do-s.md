---
id: 2026-08-12-servidor-demo-morre-quando-a-sessao-do-s
titulo: servidor demo morre quando a sessao do shell do orquestrador fecha — nohup+disown nao protege, smoke de 4s vira falso vivo
data: 2026-08-12
recorrivel: sim
regra: 49
interage_com: reforça 42 (job fora do watchdog), 14 (humano nunca adivinha se travou); família 24/31/44 (sinal de sucesso mentiu)
status: promovido
---

# servidor demo morre quando a sessao do shell do orquestrador fecha — nohup+disown nao protege, smoke de 4s vira falso vivo

## Sintoma

Servidor realtime do poker-club-os (`npm run dev:realtime`, porta 8090)
morreu DUAS vezes em silêncio na mesma sessão (2026-08-12, orquestrador =
Cursor agent), sempre DEPOIS de smoke test verde e de o link ser entregue
ao humano como vivo:

1. **Instância A** (~06:16): lançada com subshell `( ... & )` dentro de uma
   chamada de shell do Cursor. Smoke no T+4s: `tv.html: 200`. Minutos
   depois, subagente de browser recebeu connection refused; verificação:
   `curl /health` → sem resposta; `lsof -ti :8090` → porta livre.
2. **Instância B** (06:23): relançada com `nohup npm run dev:realtime
   > /tmp/clubos-realtime.log 2>&1 & disown`. Smoke verde
   (`{"ok":true}`, `tv.html: 200`); URL entregue ao humano ("aberto no seu
   navegador"). Às 06:27: `curl -m 2 /health` → exit 7 (connection
   refused), porta livre.

Evidência da morte silenciosa: `/tmp/clubos-realtime.log` (163 bytes,
mtime 06:23) termina em `TV page: http://localhost:8090/tv.html` — startup
normal, ZERO stack trace ou mensagem de erro. Morte por sinal externo, não
crash do processo.

3. **Instância C** (06:28): lançada como tarefa de background GERENCIADA
   pelo harness do Cursor (terminal persistente em `terminals/386185.txt`,
   pid 37331) — viva e servindo (`status: running`, tv.html 200) minutos
   depois. É o contraexemplo que isola a causa.

## Causa

O harness de shell do Cursor limpa a árvore de processos da chamada quando
a sessão daquela chamada termina. Filho disparado com `&`/subshell ou com
`nohup + disown` dentro de uma chamada pontual é morto nessa limpeza —
`nohup` protege de SIGHUP de terminal, não de kill de process group do
harness. Prova por eliminação: mesmíssimo comando, três formas de lançar;
as duas formas "dentro da chamada" morreram sem log, a forma gerenciada
(terminal de background persistente) sobreviveu.

Agravante: o smoke test no T+4s passou nas três — smoke pontual prova que
o processo NASCEU, não que sobrevive ao fim da chamada. O sinal de sucesso
mentiu duas vezes para o humano (mesma família do falso-verde das regras
24/31/44, e 4ª manifestação da classe da regra 42 — agora invertida:
em vez de zumbi que parece vivo, vivo que vira defunto ao fim da sessão).

## Correção aplicada

Instância C: serviço relançado como tarefa de background gerenciada do
harness (terminal persistente, monitorável em
`~/.cursor/projects/<proj>/terminals/`), verificada viva após >1 min
(`ps` pid 37331 + `/health` ok + `/api/clock` avançando). Nenhum código
do oracfit mudou — a correção é de PROCEDIMENTO do orquestrador Cursor.

## Pode acontecer de novo?

Sim — todo orquestrador rodando no Cursor que lançar processo de longa
duração (dev server, painel, watcher) com `&`/`nohup` dentro de uma chamada
pontual de shell vai repetir: smoke verde, handoff ao humano, processo
morto na limpeza seguinte. Regra candidata:

> PROCESSO DE LONGA DURAÇÃO LANÇADO PELO ORQUESTRADOR CURSOR usa o
> mecanismo de background GERENCIADO do harness (terminal persistente),
> NUNCA `&`/`nohup` dentro de chamada pontual — nohup+disown não sobrevive
> à limpeza da sessão. Smoke em T+segundos prova nascimento, não vida:
> antes de entregar URL ao humano, verificar vida com o processo já fora
> da chamada que o criou (curl numa chamada POSTERIOR). Complementa a 42
> (lá: job órfão fora do watchdog; aqui: filho morto pela limpeza da
> sessão) — em ambos, kill -0 + mtime/resposta em chamada posterior é a
> única prova de vida.

Promover com:
  bin/incident.sh promote 2026-08-12-servidor-demo-morre-quando-a-sessao-do-s "<texto da regra>"
