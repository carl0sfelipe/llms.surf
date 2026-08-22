---
id: 2026-08-11-t2-safety-ceiling-piloto-<host-local>-v3-2
titulo: Piloto <host-local> v3#2 — extrator nested-gap OK; T2-JUDGE esgota max_iterations 6 (truncation) e escala humano
data: 2026-08-11
recorrivel: sim (juiz reclama de T2-seo-strategy.md truncado em loop)
regra: evidencia-extrator-nested + teto-6
status: aberto-conteudo
interage_com: "2026-08-11-t2-judge-contract-error-piloto-<host-local>-v3-adr0005"
interage_com: "docs/architecture/ADR-0005-iteracao-sem-gap-e-falha-de-contrato.md"
---

# Piloto <host-local> v3#2 — extrator OK, T2 não converge

## Contexto

Após Caminho B do piloto `FB804AA5` (JudgeContractError por gap aninhado),
corrigimos `_extract_biggest_gap` (BFS nested + `descricao` + marker
indent-only + sentinels vazios). Suite **379 passed**, oráculo ADR-0005 rc=0.
Re-despacho sem `--resume`.

## Resultado

| Campo | Valor |
|---|---|
| `run_id` | `A743CE7F-AEB8-4B15-AF62-5188C0F8FC8E` |
| `status` | `fail` |
| tempo | **~29.2 min** (`duration_s=1752`) |
| desfecho | `Safety ceiling (6) exceeded for T2-JUDGE` → human escalation |
| `JudgeContractError` | **nenhum** |
| canário `biggest_gap: ""` | **limpo** |
| `run_finished` | sim |

## O que o extrator provou

T2-JUDGE fez **6 iterações** com `biggest_gap` articulado (string real, não
`str(dict)` vazio). Ex.: *"O arquivo T2-seo-strategy.md está truncado na
entrada da auditoria..."*. Contrato NOT-NULL + extrator nested = OK.

Comparativo com v3#1 (`FB804AA5`):

| | v3#1 | v3#2 |
|---|---|---|
| falha | JudgeContractError (extração) | Safety ceiling 6 (conteúdo) |
| iterações T2 com gap | 1 depois crash | 6 completas |
| tempo | ~54 min | ~29 min |

## Por que não chegou em T3/Caminho A

O juiz insiste que `T2-seo-strategy.md` chega **truncado** na auditoria.
Architect reescreve e marca APPROVED; juiz reabre pelo mesmo motivo.
Loop saudável (gap presente) mas **não-convergente** até o teto 6 →
escalation. Isso é produto/contexto (tamanho do artifact no prompt do juiz),
não regressão do ADR-0005.

Nota: o run começou já em T2-JUDGE (~14:10:16), sugerindo reuso de artefatos
T1 do nicho `cf-<host-local>-radeon680m-v3` — investigar checkpoint/skip depois.

## Efeitos colaterais (ainda abertos)

- `lib-oracfit-gauntlet.sh:399` — `parameter null or not set` no fail path
- metric `attempt: 4` vs `oracle_result attempt: 1`

## Evidência

`incidents/evidence/2026-08-11-t2-safety-ceiling-piloto-v3-2/`

## Veredito

Extrator nested-gap **validado em produção**. ADR-0005 teto-6 **funcionou**.
Caminho A ainda bloqueado por não-convergência T2 (truncation no contexto do
juiz). Próximo trabalho: reduzir/chunkar artifact no prompt do T2-JUDGE ou
alinhar critério do juiz ao que o architect realmente emite — **sem** afrouxar
o contrato NOT-NULL.
