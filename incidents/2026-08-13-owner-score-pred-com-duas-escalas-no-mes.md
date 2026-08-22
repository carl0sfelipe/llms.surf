---
id: 2026-08-13-owner-score-pred-com-duas-escalas-no-mes
titulo: owner_score_pred com duas escalas misturadas no ledger da noite (0–5 × 0–10)
data: 2026-08-13
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): core/critic-profiles/ananke-critic.md (escala canônica 0–10 pinada em uma linha) + bin/check-verdict.py (WARN em pred ≤ 5.0 sem escala declarada — nunca erro)
status: corrigido — working tree, aguardando commit
interage_com: "2026-08-13-run-id-de-ring-colide-entre-alvos-no-mes.md (mesma noite; lá o ledger misturou ALVOS sob um run id, aqui misturou ESCALAS sob um campo — as duas contaminações degradam a mesma calibração)"
---

# owner_score_pred com duas escalas misturadas no ledger da noite

## Sintoma

O ledger central da noite de 2026-08-13 tem `owner_score_pred` em DUAS
escalas incompatíveis, medidas assim:

```
$ rg -o '"owner_score_pred[^,}]*' ledger/ledger.jsonl | sort | uniq -c
  26 "owner_score_pred": 4.6   ┐
   8 "owner_score_pred": 4.5   │ critics prevendo em 0–5
   5 "owner_score_pred": 4.8   │ (44 eventos, faixa 4.5–4.8)
   5 "owner_score_pred": 4.7   ┘
   5 "owner_score_pred": 9     ┐
   5 "owner_score_pred": 8     │ critics prevendo em 0–10
   4 "owner_score_pred": 7.5   │ (17 eventos, faixa 7.5–9.0)
   3 "owner_score_pred": 8.0   ┘
```

Calibração compara maçã com laranja: `ring score --real` usa |delta| > 2
para rebaixar juiz a triagem, mas um 4.6 pode significar "9.2 de 10" ou
"4.6 de 10" dependendo da escala que o critic assumiu — indistinguível a
posteriori, porque o veredito não carrega a escala.

## Causa

O perfil do critic (`core/critic-profiles/ananke-critic.md`) dizia "escala
do state, default 0–5, mínimo 4.5" e o exemplo do contrato trazia
`"owner_score_pred": 4.2` — enquanto a leitura natural de "nota do dono" é
0–10. Sem declaração inequívoca, cada critic assumiu uma escala. Nenhum
gate apontava o conflito: `bin/check-verdict.py` só valida piso
(`--min-score`), sem noção de escala — 4.6 e 9.0 passam igual.

## Correção aplicada

Aplicada ATOMICAMENTE (`.new` + `mv`; sessões vivas leem do disco). Sem
commit (decisão de dono).

- `core/critic-profiles/ananke-critic.md` — escala canônica pinada em UMA
  linha: `owner_score_pred` é SEMPRE escala 0–10 (10 = nota máxima do
  dono); nunca 0–5. Exemplo do contrato corrigido (4.2 → 8.4) para não
  contradizer a linha.
- `bin/check-verdict.py` — WARN em stderr (exit code INTACTO) quando o
  veredito não declara escala (campo `score_scale`) e o valor é ≤ 5.0:
  `pred <=5.0: confirme escala 0-10 (perfil ananke) — vereditos antigos
  podem estar em 0-5`. Vereditos existentes NÃO quebram — só sinalizam.
  Range 0–10 já era aceito (não há validação de teto, só piso).
- Suítes: `tests/test-check-verdict.sh` 13 PASS, 0 FAIL;
  `tests/test-ananke-mode.sh` 7 PASS, 0 FAIL — nenhum assert precisou de
  ajuste (WARN não muda rc de nenhum caso).

Os 61 eventos já gravados NÃO foram tocados (ledger central é apêndice):
a faixa 4.5–4.8 fica marcada como escala antiga por este incidente.

## Pode acontecer de novo?

Critic prever em 0–5 por hábito, sim — mas agora o perfil declara a escala
sem ambiguidade e todo pred ≤ 5.0 sem `score_scale` grita WARN no check.
Residual declarado: o `min_score` default do ring init (4.5 em
`bin/oracfit-ring.sh`) foi calibrado quando 0–5 circulava; na escala 0–10
é piso frouxo — runs novos devem passar `--min-score` coerente (p.ex.
9.0). Não alterado aqui: mudaria comportamento de gate (decisão de dono).
