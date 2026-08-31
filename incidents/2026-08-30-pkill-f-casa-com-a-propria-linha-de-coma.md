---
id: 2026-08-30-pkill-f-casa-com-a-propria-linha-de-coma
titulo: pkill -f casa com a propria linha de comando do autor e mata o shell chamador
data: 2026-08-30
recorrivel: sim
regra: pendente
status: aberto
---

# pkill -f casa com a propria linha de comando do autor e mata o shell chamador

## Sintoma

Durante o dogfooding webnext (2026-08-30), um comando de limpeza
`pkill -9 -f 'opencode run'` terminou matando o PRÓPRIO shell que o invocou:
a saída do comando morreu no meio (só a primeira linha do ps apareceu) e o
resto da cadeia (sleep, retry, echo) nunca rodou.

## Causa

`pkill -f` casa o padrão contra a linha de comando COMPLETA de TODOS os
processos — incluindo o `bash -c '<cadeia inteira>'` que estava executando a
limpeza, cuja linha de comando contém a string literal `opencode run` (ela
mesma parte do comando de kill). O padrão foi escrito pensando nos processos
ALVO (os runs do opencode), mas o casamento é sobre bytes em qualquer
contexto — família do "casamento sem noção de intenção". Evidência: saída
truncada após a 1ª linha + a sequência seguiu normalmente ao matar por PID
explícito (kill -9 <pid>) na tentativa seguinte.

## Correção aplicada

Nenhuma no código (uso pontual). Mitigação operacional: nunca `pkill -f` com
padrão que aparece na própria cadeia — matar por PID explícito vindo de
`pgrep` inspecionado, ou usar padrão que a própria cadeia não contém.

## Pode acontecer de novo?

Sim — todo script de limpeza por padrão carrega a semente. Família grande já
documentada: backtick no comando do oráculo (2026-08-10, regra 46), oráculo
casa decision mas T4 vem com status (2026-08-09, regra 44), glob tsx casa
teste (2026-08-13), pipe escapado nunca casa (2026-07-29), heurística casa
boilerplate (2026-08-12). Promover a regra só se repetir fora de contexto
pontual; a proteção estrutural (pid explícito) já existe e é julgamento de
uso — classe da regra 32: sem mecanismo que imponha, é dívida declarada.
