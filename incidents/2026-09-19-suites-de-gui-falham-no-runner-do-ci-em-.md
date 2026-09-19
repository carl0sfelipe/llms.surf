---
id: 2026-09-19-suites-de-gui-falham-no-runner-do-ci-em-
titulo: suites de GUI falham no runner do CI em curl seguinte a request verde
data: 2026-09-19
recorrivel: sim
regra: nao — mecanismo aplicado em tests/lib-gui-http.sh (retry + prontidão na página sob teste + log do servidor no FAIL); regra 16 já cobre falha recorrente → mecanismo
status: aberto
interage_com: reforça 16 (falha recorrente vira mecanismo, não prosa); reforça o incidente 2026-08-12-autarca (verde 2× não prova; oráculo aqui é 5× consecutivo); HT1 de 2026-08-22 (CI roda TODAS as suítes — não se marca GUI como opcional)
---

# suites de GUI falham no runner do CI em curl seguinte a request verde

## Sintoma

Job `suites` de `.github/workflows/check-saude.yml` vermelho em 5 heads
diferentes na mesma hora, sempre uma suíte de GUI, sempre uma única
asserção, sempre logo depois de outra request ao MESMO servidor ter
passado:

- `integrate/p1-to-main` @ aa2e23b, run 35469293241 (push):
  `tests/test-gui.sh` — `FAIL: rótulo ausente no hitl.html`, 38 PASS antes.
- `cursor/d-inc3-zcode-config-3a81` @ 00fd2ba, run 35469392426 (push):
  `tests/test-gui-todo.sh` — `FAIL: gui.css não servido`; `/todo.html` e
  `/api/gui/home` passaram nas duas linhas anteriores.
- `cursor/t18-shadow-3a81` @ c374613, run 35469575029 (pull_request):
  `test-gui.sh` — mesmo `hitl.html`.
- `cursor/t19-policy-version-3a81` @ 8d1acb8, run 35469655002
  (pull_request): `test-gui-todo.sh` — mesmo `gui.css`.
- `cursor/t20-kernel-test-mode-3a81` @ 8cbae42, run 35469954265 (push):
  `tests/test-corte-review.sh` — `FAIL: T9b página` (`/corte.html`);
  `/api/gui/corte` passou na linha anterior.

Em TODOS os cinco, o job `suites` do evento irmão (push × pull_request)
do mesmo SHA passou. `check-saude` e `kernel gates` verdes nos dois
eventos. Em `main`, 6 dos 8 últimos pushes de `check-saude.yml` também
tinham `suites` vermelho (gh run list --branch main, 2026-09-19).

## Causa

Não determinada.

Evidência do que NÃO é:

- Não é conteúdo: `panel/hitl.html:210` contém o rótulo; `panel/gui.css`
  contém `bg-default`; `panel/corte.html` contém o título. Os mesmos
  arquivos passam no evento irmão.
- Não é prontidão do servidor: em cada falha a request imediatamente
  anterior ao mesmo processo respondeu 200 (log do job, 10–20 ms antes).
- Não reproduz localmente: neste VM, 18 execuções das três suítes no
  estado ANTERIOR ao conserto (6 rodadas × 3) saíram 0/18 vermelhas.
- Servidor é `ThreadingHTTPServer` + `SimpleHTTPRequestHandler`
  (`bin/oracfit-panel-server.py:1399`); nenhum `pkill`/`kill -- -grupo`
  nos testes que possa matar o processo de fora (rg em tests/ bin/
  adapters/: só `bin/dispatch.sh`, `bin/critic-guard.sh`,
  `adapters/opencode/runner.sh`, todos sobre o próprio grupo).

Hipóteses NÃO confirmadas (ficam como hipóteses): esgotamento momentâneo
de socket/thread no runner compartilhado; `test-corte-review.sh` usava
porta FIXA 8797 (as outras usam `--port 0`), sujeita a colisão com
servidor deixado vivo por outra suíte no mesmo runner. O `curl -sf`
engolia rc e código HTTP, então o log do job não tinha o dado que
decidiria entre elas — esse é o buraco que o conserto fecha primeiro.

Observação após o conserto: em 20 execuções locais, 19 verdes e 1
`test-corte-review.sh` com exit 2 na primeira rodada, sem linha FAIL e
sem saída capturada pelo laço; 11 rodadas seguintes verdes. Registrado,
não explicado.

## Correção aplicada

- `tests/lib-gui-http.sh` (novo): `gui_get` tenta 5× com recuo de 0,3 s e
  `--max-time 5`; na falha final imprime `curl rc` e código HTTP no
  stderr. `gui_wait_port` lê a porta efêmera do log e sonda a PÁGINA sob
  teste, não só `home.html`. `gui_dump_log` despeja o log do servidor.
- `tests/test-gui.sh`, `tests/test-gui-todo.sh`, `tests/test-corte-review.sh`:
  toda leitura de asserção via `gui_get`; `not()` despeja o log do
  servidor em qualquer FAIL; prontidão via `gui_wait_port`.
- `tests/test-corte-review.sh`: porta 8797 fixa → `--port 0 --bind
  127.0.0.1`, como as outras suítes.
- Oráculo do conserto: 5 execuções consecutivas das três suítes com exit
  0 (`for i in 1..5; bash tests/test-{corte-review,gui,gui-todo}.sh`) —
  cinco, não duas, pelo incidente do autarca. Resultado neste VM: 15/15.
- Não feito, de propósito: marcar suítes de GUI como opcionais no
  workflow (HT1 2026-08-22 proíbe a cegueira); "corrigir" o servidor sem
  causa medida.

## Pode acontecer de novo?

Sim, enquanto a causa no runner não for determinada — por isso o
mecanismo é dupla: resiste (retry) E coleta evidência (rc, HTTP, log do
servidor no FAIL). A próxima ocorrência vermelha no CI traz o dado que
faltou aqui; aí este incidente ganha causa e, se for do servidor, o
conserto muda de lugar (`bin/oracfit-panel-server.py`). Decisão
registrada em `kernel/test-specs/DECISIONS-next-steps-2026-09-19.md`
§D-NEXT-2 e §D-SHIP (flake consertado antes da tag v4.1.0).
