---
id: 2026-08-11-t2-judge-contract-error-piloto-<host-local>-v3-adr0005
titulo: Piloto <host-local> v3 — ADR-0005 validado (Caminho B): T2-JUDGE JudgeContractError após contract-retry, fail contável em ~54min
data: 2026-08-11
recorrivel: sim (prompt do juiz ainda pode omitir biggest_gap extraível)
regra: evidencia-de-ADR-0005
status: fechado-como-prova-adr0005
interage_com: "docs/architecture/ADR-0005-iteracao-sem-gap-e-falha-de-contrato.md"
interage_com: "incidents/2026-08-11-t3-judge-biggest-gap-vazio-max-iterations-20-loop-patologico.md"
---

# Piloto <host-local> v3 — ADR-0005 prova prática (Caminho B)

## Contexto

Re-rodada do piloto `cf-<host-local>-radeon680m-v3` (spec
`specs/niche-<host-local>-ser5-max-radeon-680m-igpu.md`) para validar o ADR-0005
após o incidente patológico de ontem (`72CE562A…`, 1h19, T3-JUDGE com
`biggest_gap: ""`, morto manualmente).

Pré-checks verdes antes do despacho:

- content-factory suite: **373 passed**
- oráculo ADR-0005: **rc=0**
- portas 3010/9000/8888: 200/404/200
- `DISPATCH_RUNNER` → `adapters/opencode/runner.sh`

## Resultado

| Campo | Valor |
|---|---|
| `run_id` | `FB804AA5-51C1-4D95-8814-1E66D8D93F3F` |
| `status` | `fail` |
| tempo total | **~53.7 min** (`duration_s=3222.403`) |
| ponto de falha | **T2-JUDGE** (não T3 — o bug de extração apareceu antes) |
| erro | `JudgeContractError: T2-JUDGE reemitiu sem biggest_gap após contract-retry — contrato NOT-NULL violado` |
| canário telemetria | **OK** — zero `feedback_loop_triggered` com `"biggest_gap": ""` |
| `run_finished` | sim, em `.dispatch/logs/events.jsonl` |

## Por que isto é sucesso do ADR-0005

Ontem: juiz rejeita sem gap articulado → loop interno até `max_iterations: 20`
→ oracfit cego → 1h19 → kill manual.

Hoje: juiz (T2) rejeita com gap **não-extraível** pelo contrato → contract-retry
1x → ainda sem gap → `JudgeContractError` → stage `run` exit=1 →
`status: fail` contável em **minutos/dezenas de minutos**, não loop cego.

Comparativo:

| | Ontem (`72CE562A`) | Hoje (`FB804AA5`) |
|---|---|---|
| trigger | T3-JUDGE `biggest_gap: ""` | T2-JUDGE sem biggest_gap extraível pós-retry |
| teto interno | `max_iterations: 20` | `max_iterations: 6` (visível na telemetria T1/T2) |
| telemetria vazia | 5× `biggest_gap: ""` | 0× (canário limpo) |
| desfecho | kill manual 1h19 | fail automático ~54 min |
| `run_finished` | `abnormal_exit` (após kill) | `abnormal_exit` (trap após JudgeContractError) |

## Timeline (mech-1.log)

```
13:01:16  stage run começa (T1-HUNT)
13:10–13:41  T1 feedback loop: 6 iterações COM biggest_gap articulado → APPROVED
13:41–13:45  T2-ARCHITECT APPROVED → T2-JUDGE REVISIONS_REQUIRED (gap articulado, iter 1)
13:45–13:50  T2-ARCHITECT retry → APPROVED
13:50–13:54  T2-JUDGE 2ª passagem → contract-retry → JudgeContractError
13:54:55  crew aborta; dispatch log: status: fail
13:54:56  events: oracle_result exit=1; run_finished status=fail duration_s=3222
```

## Nuance importante (trabalho futuro, NÃO do ADR-0005)

O YAML final do T2-JUDGE **contém** um bloco `biggest_gap:` bem escrito no
corpo do artifact. O contrato NOT-NULL falhou na **extração** para o campo
estruturado usado por `_check_feedback_trigger` / `_judge_contract_retry`.

Isso é o mesmo padrão do incidente T3 de ontem (“o juiz sabe o gap, mas o
campo estruturado sai vazio”). ADR-0005 fez o trabalho certo: converteu em
falha contável. Consertar o prompt/parser do juiz para popular o campo
extraível é escopo separado.

## Efeitos colaterais observados (fora do escopo desta prova)

1. `lib-oracfit-gauntlet.sh: line 399: 2: parameter null or not set` no log
   do despacho após o fail do stage — ruído no caminho de fail do gauntlet.
2. Metric event com `"attempt": "4"` enquanto `oracle_result` diz
   `"attempt": "1"` — inconsistência de contagem a investigar depois.
3. Primeira tentativa de despacho (`9BD1A64D`) morreu porque o shell do
   agent matou o process group ao sair do smoke; re-despacho com
   `subprocess.Popen(..., start_new_session=True)` (macOS sem `setsid`).

## Evidência

- `incidents/evidence/2026-08-11-t2-judge-contract-error-piloto-v3/dispatch.log`
- `incidents/evidence/2026-08-11-t2-judge-contract-error-piloto-v3/mech-1.log.gz`
- `incidents/evidence/2026-08-11-t2-judge-contract-error-piloto-v3/judge-contract-error-snippet.log`
- run dir:
  `~/<repo-cliente>.live-imports/.dispatch/logs/inbox/FB804AA5-51C1-4D95-8814-1E66D8D93F3F.run.gauntlet/`

## Veredito

**ADR-0005 validado na prática (Caminho B).** Não publicar. Não rodar os
outros 9 nichos ainda — o prompt/extração de `biggest_gap` nos juízes ainda
precisa de trabalho separado antes do e2e verde (Caminho A).

## Follow-up (mesma sessão, pós-prova)

Causa raiz da falha do T2: `biggest_gap` aninhado sob `parecer_seo_afiliado`
(dict com `descricao`); extrator top-level-only + marker na 1ª linha vazia
→ `''` → JudgeContractError mesmo com gap no YAML.

Fix em working tree (não commitado):
- `apps/content-factory/src/bmad_crew.py` — BFS nested + `descricao` + marker
  indent-only + rejeição de sentinels vazios (`""`/`{}`/`[]`/`null`) +
  visited-set anti-ciclo; status-only dict não conta como gap.
- `tests/test_judge_gap_regression.py` — casos do piloto + empty-gap.

Próximo: re-rodar piloto <host-local> v3 para tentar Caminho A.
