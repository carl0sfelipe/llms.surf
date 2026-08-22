---
id: 2026-08-22-gui-todo-vermelho-desde-o-nascimento
titulo: /api/gui/todo nasceu quebrado (referência fantasma base.project_name) e a suíte ficou vermelha invisível por ficar fora da bateria
data: 2026-08-22
recorrivel: sim
regra: mecanismo aplicado — referência trocada pela convenção inline + achado vira evidência da sessão #9 (HT1)
status: fechado
---

# /api/gui/todo nasceu quebrado — vermelho invisível fora da bateria

## Sintoma

Sessão #9 (2026-08-22) correu as 28 suítes inteiras pela primeira vez:
`tests/test-gui-todo.sh` 11 PASS / 3 FAIL — T2 (payload), T4b (endpoint sem
ring), T5 (frota). Todo call de payload de `/api/gui/todo` devolvia HTTP 500:
`{"ok": false, "error": "module 'oracfit_panel_server' has no attribute 'project_name'"}`.

## Causa (dupla)

1. **Referência fantasma**: `bin/oracfit-todo-server.py` chamava
   `base.project_name(target)` desde o commit que criou a feature (b5f5462) —
   mas `project_name` NUNCA existiu no panel-server (git log -S vazio). A
   lógica equivalente vive INLINE em `central_ring_groups` (strip de `wt-`).
   O endpoint nasceu 500 e nunca funcionou.
2. **Cobertura cega**: a suíte não está na bateria `check-saude.sh` (que roda
   só 4 das 28) nem no CI — vermelho de nascer ficou invisível por semanas.
   Atribuição verificada por checkout do commit anterior: não era regressão
   recente, era estado permanente.

## Correção aplicada (2026-08-22)

`todo_payload` usa a MESMA convenção inline do panel-server
(`name[3:] if name.startswith("wt-") else name`), com comentário apontando
para este incidente. Suíte: 14 PASS / 0 FAIL. Código:
bin/oracfit-todo-server.py (todo_payload). Teste: tests/test-gui-todo.sh
(14/0 pela primeira vez desde b5f5462).

## A lição que fica em aberto (não é deste incidente fechar)

O item 2 da causa é estrutural: 24 de 28 suítes fora do CI. A resposta
mecânica (rodar tudo no CI, ~4 min medidos) é hipótese HT1 da sessão #9 no
ledger do MASTER-PROMPT — decisão de política de CI é do owner. Enquanto
isso, o achado também expôs `tests/test-oracle-freshness.sh` como flaky
(BSD/GNU date+stat com fallback, mtime de 1s) — precisa estabilizar antes
de qualquer CI-total, senão o vermelho vira ruído.
