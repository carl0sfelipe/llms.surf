---
id: 2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi
titulo: Timeout matava só o filho; neto sobrevivia segurando o pipe
data: 2026-07-24
recorrivel: sim
regra: 17
status: promovido
---

# Timeout matava só o filho; neto sobrevivia segurando o pipe

## Sintoma

`bin/verify-models.sh` ficou **7min16s** preso numa tarefa que 60 segundos antes havia respondido em **2,4s** — apesar de a chamada estar embrulhada em `bin/with-timeout.sh 300`. O teto de 300s simplesmente não disparou.

## Causa

Evidência (`ps -o pid,etime,command` durante o travamento):

```
65500   07:16 bash bin/verify-models.sh deepseek-v4-flash-free --write --needle 20000
65771   07:09 opencode run --model opencode/deepseek-v4-flash-free Se todo A é B...
```

`with-timeout.sh` fazia `kill "KILL", $pid` — matando apenas o **filho direto**, que é `adapters/opencode/runner.sh`. Mas `runner.sh` é um wrapper: quem faz o trabalho é o **neto** (`opencode run`). O neto sobrevivia e continuava segurando o pipe de stdout, então o `$( )` do chamador permanecia bloqueado. Matar o filho não liberava nada.

Teto que não alcança neto não é teto — dá **falsa sensação de proteção**, pior que não ter teto nenhum, porque a vigilância humana relaxa.

Causa secundária, **sem relação** com a primeira: o modelo free variou de 2,4s para >7min na mesma pergunta. Variância de free tier é esperada; o defeito aqui é a proteção não ter cortado.

## Correção aplicada

`bin/with-timeout.sh`: o filho passa a ser líder do próprio grupo (`setpgrp(0,0)`) e o alarme mata o **grupo inteiro** (`kill "KILL", -$pid`), pegando filho e netos.

Teste de regressão (wrapper que spawna neto `sleep 120`, teto de 4s):

```
exit=124  duracao=4s
✅ neto morto junto com o grupo
```

Antes do fix, o mesmo teste deixava o `sleep 120` vivo.

## Pode acontecer de novo?

**Sim.** Todo runner do framework é wrapper (`adapters/<cli>/runner.sh` chama o CLI real), então qualquer teto ingênuo repete o bug. Vale também para o watchdog de `bin/dispatch.sh`, que mata `$PID` — o mesmo padrão de neto se aplica ali.
