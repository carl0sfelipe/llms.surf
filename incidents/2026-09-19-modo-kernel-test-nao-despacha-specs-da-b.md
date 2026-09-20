---
id: 2026-09-19-modo-kernel-test-nao-despacha-specs-da-b
titulo: modo kernel_test não despacha: specs da bateria reprovam no gate check-spec
data: 2026-09-19
recorrivel: sim
regra: pendente
status: aberto
interage_com: "kernel/test-specs/DECISIONS-next-steps-2026-09-19.md D-NEXT-4 (E5 exige a primeira rodada real de kernel_test; o modo era a precondição mergeada)"
interage_com: "incidents/2026-07-26-spec-sem-clausula-anti-invencao-gera-num.md (o gate que reprova é o mecanismo deste incidente)"
interage_com: "kernel/test-specs/T11-T20-second-wave.md T20 (modo kernel_test, 'closes p1-inc-1... unlocks E5 measurement')"
---

# modo kernel_test não despacha: specs da bateria reprovam no gate check-spec

## Sintoma

E5 (D-NEXT-4) manda rodar `oracfit run kernel_test <spec> p1-<ID>`. A
primeira chamada (T01, 2026-09-19, branch `zcode/shadow-on` @ `388f11d`)
morre no preflight, antes de qualquer modelo:

```
$ source adapters/opencode/env.sh && export ORACFIT_ROOT=$PWD && \
    KERNEL_TEST_ID=T01 bin/oracfit run kernel_test \
    kernel/test-specs/T01-build-reproducibility.md p1-T01
❌ spec sem defesa contra invenção — ver incidents/2026-07-26-spec-sem-clausula-anti-invencao-gera-num.md: .../kernel/test-specs/T01-build-reproducibility.md
   - falta cláusula anti-invenção (ex.: 'Nao invente numero, prazo ou fonte alem dos listados')
   - falta bloco de dados verificados (o que o modelo PODE usar)
   - falta linha VERIFICACAO: ou seção de verificação com comando que prove a propriedade pedida
   - falta seção ## Oráculo (comando + exit esperado que prova o resultado, não so que o modelo rodou)
   - falta cláusula anti-fantasma (ex.: 'NUNCA use declare const como workaround — importe de verdade')
ERROR: preflight failed at check-spec
RUN_EXIT=1
```

Varredura das specs da bateria (`bash bin/check-spec.sh` em cada uma,
2026-09-19): **15/15 reprovam com as mesmas 5 faltas** — T01–T10 e
T13–T17. Nenhuma linha nova em `.dispatch/ledger/mode.jsonl` (última
linha continua sendo a de 2026-09-07, task `first-proof`).

## Causa

Dois artefatos mergeados sem passarem um pelo contrato do outro:

- `core/modes/kernel_test.yaml` (T20, merge 388f11d) despacha o estágio 1
  com `input: kernel/test-specs` — as specs da bateria P1.
- `bin/lib-oracfit-preflight.sh` gate (1) aplica `bin/check-spec.sh`
  incondicionalmente à spec de qualquer estágio de modelo.
- As specs da bateria (`kernel/test-specs/T01..T17`) foram escritas noutro
  estilo — inglês, steps com oráculo por passo, juiz mecânico
  `kernel/test-specs/oracle.sh` (avalia `reports/<ID>.md` + `cargo test`)
  — e não contêm nenhuma das 5 defesas textuais que o check-spec exige.

O modo foi validado pelo oráculo do próprio YAML
(`bin/lib-oracfit-mode-loader.py validate`), não por um run real de
despacho; o gate de spec só dispara no `oracfit run`. E5 era
exatamente o primeiro consumidor — e o primeiro a bater no muro.

Família da regra 38 (sensor que olha o arquivo errado / contrato não
casado entre camadas) e da 44 (schema sem enforcement entre componentes
que se referem entre si).

## Correção aplicada

Adicionadas as 5 defesas exigidas pelo check-spec às specs T01–T10
(branch `zcode/e5-spec-defesas`, PR na sequência): bloco de dados
verificados, cláusula anti-invenção, linha VERIFICACAO, seção ##
Oráculo com `- comando: bash kernel/test-specs/oracle.sh <ID>` (texto
cru, sem crase — regra 46) e cláusula anti-fantasma. T13–T17 (segunda
onda) ficam PARA O PRÓXIMO CONSUMIDOR — não fazem parte de E5.

## Pode acontecer de novo?

Sim. Nada no repo obriga uma spec nova do kernel (ou de qualquer modo
futuro com `input:` de diretório) a passar pelo check-spec antes do
merge — o gate só executa no `oracfit run`, quando o dono já esperava
medição. Candidata a regra: spec que entra em modo de despacho precisa
passar `bin/check-spec.sh` no próprio PR (CI), não na primeira tentativa
de uso. Promover quando o dono confirmar a redação:

  bin/incident.sh promote 2026-09-19-modo-kernel-test-nao-despacha-specs-da-b "<texto da regra>"
