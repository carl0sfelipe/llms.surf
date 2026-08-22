---
id: 2026-08-10-veredito-sem-degrau-intermediario-faz-ju
titulo: veredito sem degrau intermediario faz juiz aprovar com CRITICAL aberto
data: 2026-08-10
recorrivel: sim
regra: nao — mecanismo aplicado (classe C) no content-factory: severity gate (_output_has_critical_severity + _judge_integrity_guard), vocabulario com degrau nos 4 juizes (tasks.yaml), parser por fronteira de palavra, gate hard falha fechado em None (_check_gate_pass); testes test_verdict_gate_rules.py + test_verdict_integrity.py
status: promovido
---

# veredito sem degrau intermediario faz juiz aprovar com CRITICAL aberto

## Sintoma

Pipeline `content-factory`, nicho `<host-local>-ser5-max-radeon-680m-igpu`, tarefa `T2-JUDGE`.

O juiz emitiu:

```
verdict: PASS_WITH_NOTES
confidence_score: 0.68
issues: 7   # 2 CRITICAL, 3 WARNING, 2 INFO
```

Os dois CRITICAL eram reais e bloqueantes de qualidade:

1. `keyword-strategy` — calendário com ~9 posts sobre o mesmo produto (Review, Specs, Custo-Benefício, 3 comparativos, 3 casos de uso). Google consolidaria em 1–2 rankings, enterrando as variações.
2. `kpi-realism` — metas de ≥80% indexação em 30 dias, ≥10.000 impressões em 90 dias e ≥15 keywords em top 10 em 180 dias, para site novo em nicho competido.

`PASS_WITH_NOTES` conta como aprovação. O gate `hard` do T2 passa e o pipeline segue para `T3-DESIGN` **carregando os dois CRITICAL abertos**. Nenhum log de aviso, nenhuma escalação: da perspectiva do harness, o gate passou limpo.

Detectado por revisão humana ("mas se teve essas notes, não tem que refinar o artefato e voltar pro T2 antes de ir pro T3?"), não pelo harness.

## Causa

Três defeitos independentes que se somam. Nenhum deles sozinho produz o falso-passe.

### 1. O vocabulário de veredito do T2-JUDGE não tem degrau intermediário

`apps/content-factory/config/tasks.yaml`, `T2-JUDGE`:

```yaml
expected_output:
  required_fields:
    verdict: PASS | PASS_WITH_NOTES | FAIL
feedback_loop:
  trigger_condition: verdict == 'REJECTED' or verdict == 'REVISIONS_REQUIRED'
  target_task: T2-ARCHITECT
  until_approved: true
  max_iterations: 20
```

O vocabulário oferecido ao juiz (`PASS | PASS_WITH_NOTES | FAIL`) e o gatilho declarado (`REJECTED`, `REVISIONS_REQUIRED`) **não têm um único termo em comum**. O `trigger_condition` do T2 é texto morto: nenhum veredito bem-formado do T2-JUDGE pode satisfazê-lo.

Levantamento nos quatro juízes — o T2 é o único com interseção vazia:

```
$ python3 -c "compara expected_output.verdict x feedback_loop.trigger_condition"

TASK         VOCABULARIO DECLARADO                        GATILHO DO LOOP                     INTERSECAO
T1-JUDGE     APPROVED | CONDITIONAL | REJECTED            REJECTED or CONDITIONAL             ['CONDITIONAL', 'REJECTED']
T2-JUDGE     PASS | PASS_WITH_NOTES | FAIL                REJECTED or REVISIONS_REQUIRED      VAZIA
T3-JUDGE     APPROVED | APPROVED_WITH_REVISIONS | REJECTED REJECTED or APPROVED_WITH_REVISIONS ['APPROVED_WITH_REVISIONS', 'REJECTED']
T4-JUDGE     APPROVED | REVISIONS_REQUIRED | REJECTED     INSUFFICIENT or verdict...          ['REJECTED', 'REVISIONS_REQUIRED']
```

Na prática o loop do T2 ainda é alcançável, mas só por `FAIL`, porque `_check_feedback_trigger` tem uma tupla fixa no código que ignora o `trigger_condition` (`src/bmad_crew.py:951`):

```python
if decision in (
    DecisionStatus.REJECTED,
    DecisionStatus.REVISIONS_REQUIRED,
    DecisionStatus.CONDITIONAL,
    DecisionStatus.FAIL,
):
    return True
```

Interseção real do T2 com essa tupla: `{FAIL}` — só a opção nuclear, que significa "estratégia inviável". Um juiz diante de "problema crítico **porém corrigível**" não tem para onde ir: `FAIL` é forte demais e mentiria sobre a gravidade, e sobra `PASS_WITH_NOTES`, que aprova. Ele escolhe aprovar.

T1, T3 e T4 têm o degrau do meio (`CONDITIONAL`, `APPROVED_WITH_REVISIONS`, `REVISIONS_REQUIRED`). O T2 não tem.

### 2. A severidade dos issues nunca é lida

O campo `severity: CRITICAL | WARNING | INFO` é exigido no `expected_output` de todos os juízes, mas não existe consumidor:

```
$ grep -rn "CRITICAL\|severity" src/ lib/ main.py
(nenhuma saída)
```

O gate decide apenas pelo enum do veredito. `2 CRITICAL` e `0 CRITICAL` são indistinguíveis para o harness. A severidade é decorativa — sensor cego por construção.

### 3. O parser promove o veredito por casamento de substring

`src/bmad_crew.py:788` (`_parse_judge_decision`) testa `approved_signals` com `sig in s`, sem fronteira de palavra, e a lista contém `'VERDICT: PASS'` (linha 814):

```python
approved_signals = ['APPROVED', 'APPROVE', ..., 'VERDICT: PASS', 'VERDICT: APPROVE', 'APROVADO']
if any(sig in s for sig in approved_signals):
    return DecisionStatus.APPROVED
```

`VERDICT: PASS` é substring de `VERDICT: PASS_WITH_NOTES`. O artefato dizia `PASS_WITH_NOTES` e foi lido como `APPROVED` — um degrau acima. O ramo `PASS_WITH_NOTES` da linha 824 é inalcançável para qualquer YAML que escreva `verdict: PASS_WITH_NOTES` no formato canônico.

Verificado no artefato real:

```
1 REVISIONS : -
2 REJECTED  : -
3 APPROVED  : ['VERDICT: PASS']   <- casa aqui, retorna APPROVED
4 CONDITION : ['CONDICIONAL']     <- nunca alcançado
5 PWN       : True                <- nunca alcançado
```

Ironia: a linha 827 do mesmo arquivo já documenta exatamente essa classe de bug (`'PASS' colide com 'PASSO'`) e corrige com `\b` para os tokens curtos — mas as entradas compostas de `approved_signals` ficaram de fora do conserto.

### Por que isso não apareceu antes

O gauntlet do T2 **rodou** nesta execução (loops 3, 4 e 5), o que dá aparência de mecanismo saudável. Mas todas as voltas vieram do override de integridade da Regra 44, não de mérito:

```
17:28:41 WARNING BMADCrew | INTEGRITY CHECK override: T2-JUDGE era approved mas o
                            output está truncado (fence não fechado) → REVISIONS_REQUIRED
17:28:41 INFO    BMADCrew | Gauntlet loop 5/20: T2-JUDGE -> T2-ARCHITECT
```

O `_judge_integrity_guard` é o **único** emissor de `REVISIONS_REQUIRED` no caminho do T2. O loop do T2 nunca reprovou por conteúdo — só por truncamento. Isso mascarou o defeito: parecia que o gauntlet estava funcionando.

## Correção aplicada

**Round 1 — despachado via oracfit (`deepseek_direct_flash`, task `cf-verdict-gate`), oráculo verde, verificado de forma independente.**

Oráculo escrito ANTES do dispatch e mantido fora do repo (`probe/oracle-verdict-gate/`), materializado só na verificação, com sha256 conferido a cada run. O `check-oracle` do preflight confirmou que ele reprovava pelo motivo certo antes do modelo tocar em qualquer coisa. O modelo não leu o arquivo de teste — os eventos mostram apenas `ls` no diretório, execução do `run-oracle.sh` e leitura do `BASELINE-FAILURES.txt`.

Mudanças reais, extraídas dos `oldString`/`newString` dos eventos (o `git diff` sozinho engana: `config/tasks.yaml` já tinha alterações não-commitadas de antes, com `gate_type` e `feedback_loop`, que não são do modelo):

- `src/bmad_crew.py`: novo `_output_has_critical_severity` — parseia o YAML de verdade, percorre `severity` aninhado em qualquer profundidade, e só cai em heurística textual (mirando o campo, não a palavra) se o parse falhar. Ligado ao `_judge_integrity_guard`, que foi reestruturado com precedência explícita: não-aprovação retorna cedo, truncamento (Regra 44) primeiro, severidade depois.
- `src/bmad_crew.py`: `PASS_WITH_NOTES` testado ANTES do ramo de aprovação, e sinais compostos de `approved_signals` passando a casar por fronteira de palavra.
- `config/tasks.yaml`: vocabulário de T2-JUDGE (`PASS | PASS_WITH_NOTES | FAIL`) e T3-JUDGE (`APPROVED | APPROVED_WITH_REVISIONS | REJECTED`) unificados em `APPROVED | REVISIONS_REQUIRED | REJECTED`, igual ao T4; `trigger_condition` do T3 corrigido de `APPROVED_WITH_REVISIONS` para `REVISIONS_REQUIRED`. T1 e T4 intocados.
- Novo `tests/test_verdict_gate_rules.py` (13 testes) escrito pelo próprio modelo.

Medição independente: suíte com 8 falhas contra 9 no baseline, **zero novas**, uma pré-existente corrigida de brinde. Sondagem manual das bordas do parser confirmou `PASS_WITH_NOTES` preservado, `APROVADO` ainda funcionando, e prosa (`"o passo 3"`, `"não há risco critical"`) sem falso-positivo.

**Round 2 — o defeito 4 acima, despachado em seguida.** Oráculo `test_unknown_verdict_gate.py`, calibrado em 5 falhas / 11 passes antes do dispatch.

O que já tinha sido feito à mão, antes de qualquer dispatch:

- Gauntlet do T2 executado à mão, com juiz instruído por rubrica corrigida (vocabulário incluindo `REVISIONS_REQUIRED` e regra dura: *"se listar qualquer issue CRITICAL, o veredito não pode ser APPROVED nem PASS_WITH_NOTES"*).
- `T2-ARCHITECT` iteração 2 reescrita com os 6 fixes injetados: calendário de ~9 para 5 posts sobre o produto, review canônica declarada em `/blog/mini-pc/<host-local>-ser5-max-review/` com Specs+Benchmarks+Custo-Benefício como H2 internos, KPIs revisados para baixo com nota de recalibração via GSC, anexo de disclosure de afiliado, via de implementação de JSON-LD declarada, roadmap de escala meses 4–12 com gatilho numérico.
- `T2-JUDGE` iteração 2: `APPROVED`, confiança 0.85, **0 CRITICAL, 0 WARNING**, 2 INFO. Ambos os CRITICAL anteriores verificados como `RESOLVIDO` com citação do trecho novo.
- Iteração 1 preservada para diff em `artifacts/<host-local>-ser5-max-radeon-680m-igpu/.gauntlet-history/`.

Os LLMs desta rodada foram Haiku via Claude Code, não o `deepseek-v4-flash` do adapter opencode — a cota do free tier tinha esgotado às 17:32 (`Invalid response from LLM call - None or empty.`). Registrado à parte.

Correções pendentes, em ordem de impacto:

1. `config/tasks.yaml`, `T2-JUDGE`: trocar o vocabulário para `APPROVED | REVISIONS_REQUIRED | REJECTED` (alinhado ao T4, que já funciona), ou manter `PASS/FAIL` e acrescentar `REVISIONS_REQUIRED` como degrau do meio. O `trigger_condition` precisa citar termos que o juiz possa realmente emitir.
2. `src/bmad_crew.py:814`: tirar `'VERDICT: PASS'` de `approved_signals`, ou aplicar fronteira de palavra também nas entradas compostas. Testar com `verdict: PASS_WITH_NOTES` — hoje o ramo da linha 824 é inalcançável.
3. `src/bmad_crew.py`: fazer o gate ler `severity`. Um `CRITICAL` aberto no YAML do juiz deve rebaixar aprovação para `REVISIONS_REQUIRED`, no mesmo ponto e no mesmo espírito do `_judge_integrity_guard` (que já rebaixa por truncamento). Sem isso, o campo continua decorativo e a defesa depende do juiz ser disciplinado sozinho.

## Pode acontecer de novo?

**Sim, e em qualquer juiz — não é específico do T2.**

O defeito de fundo é de desenho: **o gate confia num único enum produzido por LLM e ignora o corpo estruturado que ele mesmo exigiu.** Basta um vocabulário sem degrau intermediário — ou um juiz que escolha a palavra mais branda sob pressão de rubrica ambígua — para um artefato com problema crítico atravessar um gate `hard` sem deixar rastro. O T2 caiu porque o vocabulário dele é o único sem meio-termo, mas T1/T3/T4 protegem-se por acidente de configuração, não por mecanismo.

Agrava o risco: o pipeline é `until_approved: true` com teto 20. Um falso-passe não custa uma volta — ele **encerra** o loop e contamina todas as tarefas a jusante (T3, T4 e o site gerado) com uma premissa reprovada. É a mesma família da Regra 44 (`2026-08-09-oraculo-casa-decision`): naquele caso o falso sucesso veio de YAML truncado; aqui vem de YAML íntegro cujo enum não reflete o próprio conteúdo.

Regra candidata:

> Gate de juiz nunca decide só pelo enum do veredito. Se o juiz emitir issue de severidade crítica, aprovação é rebaixada automaticamente para revisão, independentemente do veredito declarado. E todo juiz precisa de degrau intermediário no vocabulário ("crítico porém corrigível"): sem ele, o juiz é forçado a escolher entre reprovar demais e aprovar de menos — e escolhe aprovar.

### 4. Veredito não reconhecido atravessa gate hard (descoberto na verificação do round 1)

`_parse_judge_decision` devolve `None` quando não reconhece o texto. `_check_gate_pass` só barra três estados:

```python
hard_block = [DecisionStatus.REJECTED, DecisionStatus.FAIL,
              DecisionStatus.REVISIONS_REQUIRED]
if gate_type == 'hard' and result.decision in hard_block:
    return False
return True          # <- None cai aqui
```

`None` não está na lista, então **passa**. Pior: `None` também não está na tupla de aprovações do `_judge_integrity_guard`, que retorna na primeira linha — o parecer escapa TAMBÉM do guard de truncamento (Regra 44) e do gate de severidade do round 1. Um juiz que responda fora do vocabulário aprova por omissão, sem log, sem escalação.

Latente desde sempre — `_check_gate_pass` não foi tocado por nenhuma correção. Mas o round 1 **alargou a superfície**: ao trocar `sig in s` por fronteira de palavra nos sinais compostos, dois textos que antes viravam `APPROVED` passaram a cair em `None`:

```
verdict: APPROVED_WITH_REVISIONS   antes -> APPROVED    agora -> None
verdict: PASSED                    antes -> APPROVED    agora -> None
```

Sem impacto imediato (nenhum artefato em disco usa essas formas, e o vocabulário do T3 deixou de emitir `APPROVED_WITH_REVISIONS`), mas é a mesma família do defeito original: **o que o gate não entende, ele aprova**.

Verificado que só juízes declaram `gate_type` — os quatro workers (T1-HUNT, T2-ARCHITECT, T3-DESIGN, T4-CONTENT) não têm, e saem de `_check_gate_pass` antes da checagem. Então barrar `None` em gate hard é seguro: não trava o pipeline nos workers, que rodam com `decision=None` o tempo todo.

Princípio para a correção: **gate hard falha fechado**.

## Achados relacionados (cada um pede incidente próprio)

- **Cache de juiz destrói artefato externo no resume.** `src/bmad_crew.py:1264` insere toda task em `context`, inclusive cache hit; `:645` então detecta `worker_executed=True` e `unlink()` no artefato do juiz. Rodar `main.py --resume` agora apagaria o `T2-seo-validation.yaml` produzido à mão e re-executaria o juiz no provider esgotado.
- **Loop overnight reinicia com fila vazia.** `tools/backlog.txt` do `~/tripstory-mvp1` zerou no ciclo c15 (17:42); o c16 subiu às 17:45 sem trabalho, e o harness contabilizou `success`. O loop não distingue "terminou o backlog" de "tem trabalho pendente" — 4 restarts sem stage completado.
- **Cota esgotada chega como resposta vazia, não como erro de cota.** `Invalid response from LLM call - None or empty.` no `deepseek-v4-flash` às 17:32:59. Antes disso, degradação silenciosa: outputs truncados em fence ímpar, que a Regra 44 converteu em `REVISIONS_REQUIRED` e viraram voltas inúteis de gauntlet queimando a cota restante. Parente de `2026-07-24-rate-limit-chega-como-timeout-nao-como-e`.
