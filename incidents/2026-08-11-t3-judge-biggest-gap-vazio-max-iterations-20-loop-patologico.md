---
id: 2026-08-11-t3-judge-biggest-gap-vazio-max-iterations-20-loop-patologico
titulo: T3-JUDGE rejeita 5x+ com biggest_gap vazio → loop patológico até max_iterations 20 (safety_ceiling do oracfit ignorado)
data: 2026-08-11
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): biggest_gap obrigatorio no required_fields dos 4 juizes (tasks.yaml) + cascata _extract_biggest_gap (regra 45) + gap stagnation guard (consecutive_stuck>=2, test_gap_stagnation.py) + max_iterations 20 para 6 (teto CrewAI proximo do safety_ceiling do oracfit)
status: promovido
interage_com: "2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-run-finished"
interage_com: "specs/content-factory-verdict-gate.md"
interage_com: "specs/content-factory-unknown-verdict.md"
---

# T3-JUDGE em loop patológico — biggest_gap vazio, max_iterations 20, oracfit cego

## Contexto

Piloto content_factory e2e (nicho `<host-local>-ser5-max-radeon-680m-igpu`, run_id
`72CE562A-5C2C-4CF9-804E-0C4259FB7490`) despachado para validar o roteamento
v3 após a morte da rota NVIDIA `deepseek/deepseek-v4-flash` (HTTP 410 Gone,
EOL 2026-08-07) e a troca da tier cheap para `deepseek-v4-flash-free`.

O run foi **morto manualmente** após 1h19 de CPU, preso no loop interno do
CrewAI na task T3-DESIGN/T3-JUDGE sem caminho de convergência. Este incident
registra a causa raiz para que ela vire bloqueador da v3 oficial.

## Sintoma (o que apareceu no log)

Pipeline BMAD progressão observada no `mech-1.log`:

```
T1 (research)        ✅ passou em 1 tentativa         [10:22-10:24]
T2 (SEO strategy)    ✅ passou após 4 loops saudáveis [10:25-10:40]
                     (cada REVISIONS_REQUIRED tinha feedback concreto;
                      T2-ARCHITECT incorporou e终于 APPROVED em 90s)
T3 (UX design)       🔁 PRESO, iteração 5/20          [11:15-11:39, morto]
```

Na hora do kill: mech-1.log em **3.6 MB / 41 595 linhas** (maioria é YAML de
artifact reescrito a cada iteração). 5 feedback_loop_triggered do T3-JUDGE,
todos com a mesma assinatura patológica.

## Causa raiz

`biggest_gap: ""` (string vazia) em **todas as 5** iterações do T3-JUDGE.
Telemetria literal, última iteração antes do kill:

```json
{"event_type": "feedback_loop_triggered",
 "task_id": "T3-JUDGE",
 "duration_ms": 117353,
 "metadata": {"iteration": 5, "max_iterations": 20,
              "until_approved": true, "target_task": "T3-DESIGN",
              "decision": "revisions_required",
              "biggest_gap": ""}}
```

Consequência: o feedback injetado de volta no T3-DESIGN é **vazio/genérico**.
O redesign acontece no escuro → o juiz rejeita pelos mesmos motivos (ou por
motivos novos que não consegue articular em uma frase) → loop sem saída.

O juiz escreve no corpo do artifact frases como *"ainda não pode ser aprovado
porque faltam critérios explícitos"* e *"Faltam fallbacks para falha de
carregamento de preço em runtime"* — ou seja, **ele sabe** o gap. Mas o
campo estruturado `issues:` sai literalmente como `[]` e o `biggest_gap`
metadata fica vazio. Falha de extração, não de julgamento.

## Por que rodou até 20 iterações (e não parou no `safety_ceiling: 4`)

O `content_factory.yaml` declara:

```yaml
gauntlet:
  safety_ceiling: 4
run_attempt_budget: 4
```

Mas o teto do oracfit é uma camada **acima** do loop interno do CrewAI. O
CrewAI tem o próprio `max_iterations: 20` (visível na telemetria), que é o teto
que realmente governa o loop DESIGN↔JUDGE. São dois tetos independentes:

- `safety_ceiling: 4` (oracfit) → conta **tentativas de estágio** (stage run),
  não iterações internas do CrewAI.
- `max_iterations: 20` (CrewAI) → conta **loops dentro de uma única execução
  de task**, invisível ao oracfit.

Resultado: o oracfit via **1 stage run em andamento** e considerava dentro do
budget. Enquanto isso, o CrewAI queimava iterações cegas.

## Relação com incidents/specs existentes

- **`2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-run-finished.md`**:
  mesmo padrão (critic sem teto trava o stage loop). Aquele incident levou ao
  `with-timeout.sh` no `oracfit_gauntlet_run_critic`. **Mas o timeout cobre só
  o critic do gauntlet oracfit, não o JUDGE interno do CrewAI.** Buraco
  permanece aberto para loops dentro do CrewAI.
- **`specs/content-factory-verdict-gate.md`** (em andamento): descreve o bug
  do `PASS_WITH_NOTES` casando como `APPROVED` por substring. Este incident
  aqui é **diferente**: o vocabulário do T3 é `APPROVED | REVISIONS_REQUIRED
  | REJECTED` (o correto, mesmo do T4), e ainda assim o `biggest_gap` sai
  vazio. Sugere que a extração do gap é uma superfície de bug separada do
  parser de verdict.
- **`specs/content-factory-unknown-verdict.md`** (em andamento): descreve
  `None` atravessando gate hard. Relacionado, mas não é o caso aqui (aqui o
  verdict é reconhecido como REVISIONS_REQUIRED; o problema é o gap, não o
  verdict).

## Regra candidata (a vira se confirmar)

> **Toda task JUDGE do CrewAI precisa de um contrato de output estruturado
> que inclua `biggest_gap` não-vazio quando `decision != APPROVED`. Sem gap,
> o loop não pode rejeitar — ou o gate falha fechado e o oracfit assume como
> falha de estágio (conta no `safety_ceiling`).**

E, separadamente:

> **`max_iterations` do CrewAI DEVE ser <= `safety_ceiling` do oracfit, ou o
> oracfit precisa enxergar as iterações internas do CrewAI como attempts de
> estágio.** Hoje são duas contabilidades que não conversam.

## Evidência preservada

- `mech-1.log` final: copiado para `/tmp/incident-t3-evidence/mech-1-final.log`
  (3.6 MB, 41 595 linhas). Recomenda-se movê-lo para
  `incidents/evidence/2026-08-11-t3-loop/` antes de limpar `/tmp`.
- `dispatch.log`: `/tmp/incident-t3-evidence/dispatch.log`.
- Run dir original: `~/<repo-cliente>.live-imports/.dispatch/logs/inbox/72CE562A-5C2C-4CF9-804E-0C4259FB7490.run.gauntlet/`
  (preservado, dispatcher morto mas logs intactos).
- Artifacts T1+T2 produzidos (pós-kill, não foram consumidos pelo oracfit):
  `~/<repo-cliente>.live-imports/apps/content-factory/artifacts/<host-local>-ser5-max-radeon-680m-igpu/`
  — `T1-market-opportunities.yaml`, `T1-roi-evaluation.yaml`,
  `T2-seo-strategy.md`, `T2-seo-validation.yaml`. Nenhum T3/T4 produzido.

## O que este incident PROVA pra v3

1. **`safety_ceiling: 4` do oracfit não protege contra loops internos do
   CrewAI.** Dívida de integração crítica — o oracfit está cego pra o que
   acontece dentro de uma execução de task.
2. **Prompt do T3-JUDGE não força extração de `biggest_gap`.** Sem isso, o
   mecanismo de `inject_feedback` do gauntlet oracfit (desenhado pra injetar
   o gap de volta no builder) não tem material pra trabalhar — injeta vazio.
3. **O loop patológico inflaciona o mech-N.log** (3.6 MB em 1h19), tornando
   diagnóstico pós-mortem mais caro.
4. **O T1 e T2 funcionaram** com o mesmo orquestrador — T2 inclusive com 4
   iterações saudáveis (cada uma com feedback concreto). Ou seja, o bug é
   específico do prompt/config do T3-JUDGE, não do pipeline inteiro.

## Próximo passo (fora deste incident)

Verificar `config/tasks.yaml` do content-factory: o `required_fields` do
T3-JUDGE força `biggest_gap` quando `decision != APPROVED`? Se não, é aqui que
entra a correção — e ela deve ser validada por um teste análogo ao
`test_verdict_integrity.py` (regra 44). Esta correção é escopo da v3 oficial,
não do experimento travelview.

## Pode acontecer de novo?

Sim — até corrigido o prompt do T3, qualquer nicho que chegue no T3 com um
design que o juiz rejeita vai cair neste loop. O piloto <host-local> travou; os
outros 9 posts do `docs/handoffs/START-10-POSTS-HERE.md` trancariam igual. **Bloqueador
para declarar o content_factory v3 funcional end-to-end.**
