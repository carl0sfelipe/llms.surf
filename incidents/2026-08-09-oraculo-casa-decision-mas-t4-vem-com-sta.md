---
id: 2026-08-09-oraculo-casa-decision-mas-t4-vem-com-sta
titulo: oraculo-casa-decision-mas-t4-vem-com-status-verdict-ou-approval_gate
data: 2026-08-09
recorrivel: sim
regra: 44
status: promovido
---

# oraculo-casa-decision-mas-t4-vem-com-status-verdict-ou-approval_gate

## Sintoma

O oráculo do mode `content_factory` casa o campo `decision:.*APPROVED` no
`T4-content-validation.yaml`, mas o agente T4-JUDGE está gravando o verdict em
OUTROS nomes de campo. Resultado: o oráculo reprova (ou aprova) pelo motivo
errado — o verdict real do juiz não é o que o gate lê. Confirmado em 3 formatos
divergentes coexistindo nos 12 T4s em disco.

## Causa

QUATRO contratos divergentes para o mesmo campo de verdict, sem nenhum que
prevaleça. Evidência (verificada em 2026-08-09):

1. **Oráculo** (spec template) casa `decision:`:
   `specs/_template-content-factory-niche.md` linha 168:
   `grep -qE "decision:[[:space:]]*['\"]?APPROVED" .../T4-content-validation.yaml`

2. **`tasks.yaml` define `verdict:`** como required_field do T4-JUDGE:
   `config/tasks.yaml` (4 tasks judge): `verdict: "APPROVED | CONDITIONAL | REJECTED"`

3. **T4s reais divergem** — 3 formatos nos 12 arquivos:
   - `status:` → 1 (ex.: `artifacts/<host-local>-ser-6800u-vale-a-pena/T4-content-validation.yaml`,
     gerado em 2026-08-09 21:16, run 6AB7A6CB — o run que acabou de terminar)
   - `decision:` → 5 (ex.: veneno `nintendo-switch-2`, 2026-08-02)
   - `approval_gate:` (com sub-campo `decision:`) → 2
   - nenhum T4 usa `verdict:` no top level

4. **O agente T4-JUDGE não segue nenhum contrato fixo** — o CrewAI gera YAML
   livre conforme o prompt do agente, e o `expected_output.verdict` do tasks.yaml
   não é enforceado em código (não há schema validation na escrita).

Consequência prática: dos 12 T4s, só os 5 com `decision:` passariam no oráculo
atual. Os 7 restantes (status/approval_gate/verdict) falhariam no gate mesmo com
verdict APPROVED — ou, inversamente, um T4 com `status: APPROVED` e
`decision: REJECTED` (se ambos coexistissem) seria aprovado pelo oráculo lendo
apenas `decision:`.

O próprio agente do run <host-local> percebeu a divergência (evento de thinking às
00:22 no painel): *"T4-JUDGE approved, but the persisted validation artifact..."*.

## Causa — camada extra descoberta ao desbloquear o post (2026-08-09 ~21:50)

Investigando o porquê do post do <host-local> não estar no blog, descobri que o bug
tem **três camadas empilhadas**, não duas:

5. **Truncamento vem do LLM, não do `_persist_artifact`.** O "Final Answer" do
   T4-JUDGE no log (linha 6621 de `content-factory-<host-local>-resume2.log`) JÁ nasce
   truncado:
   ```
   - "Aplicado: seção 'Mini PC até R$ 3.500' com alternativas linkadas ao    cat
   ```
   O DeepSeek **parou de gerar no meio de "catalogadas"** (provável `max_tokens`
   atingido ou stop prematuro). O `_persist_artifact` gravou fielmente o que
   recebeu (825 bytes, cortado mid-word). Não é bug do writer — é bug do output
   do modelo.

6. **Parser do CrewAI dá FALSO APPROVED sobre o YAML truncado.** Apesar do
   arquivo estar quebrado (cortado em `"cat"`), o `_parse_judge_decision` extraiu
   `DecisionStatus.APPROVED` e o checkpoint registrou `decision: APPROVED`
   (log linha 6654). Ou seja: o **sistema reporta sucesso sobre artefato inválido**.
   Mesma família das regras 24 (captura mentiu) e 31 (exit 0 sem fazer nada):
   falso sucesso. Sem validar que o YAML está íntegro, nada detecta o problema.

7. **`export-to-blog.py` NÃO lê o verdict** — só lê o `T4-content-bundle`.
   Então tecnicamente o post PODERIA ter sido exportado apesar do verdict
   quebrado. O que travou foi o **oráculo do oracfit** reprovar o run inteiro
   (por `status:` vs `decision:`), e o agente nunca chegou no passo de export.
   O post ficou preso no pipeline por horas, não por problema no conteúdo.

**Implicação pro mecanismo:** A/B/C (decidir campo canônico) só resolve a camada
2 (formato divergente). As camadas 5 e 6 (truncamento LLM + falso sucesso do
parser) precisam de **validação de integridade**: o `_persist_artifact` (ou um
validator pós-parse) deve rejeitar YAML truncado, e o `_parse_judge_decision`
NÃO deve reportar APPROVED sobre conteúdo cortado. Sem isso, qualquer uma das
três camadas recria o falso sucesso.

## Correção aplicada

NENHUMA ainda (incidente aberto). Candidatos a mecanismo (a decidir):

- **(A) Normalizar na escrita:** o `_persist_artifact` do `bmad_crew.py` (ou um
  schema validator) força o T4 a um campo canônico (ex.: sempre `decision:`),
  rejeitando/sanitizando formatos divergentes. O oráculo continua casando
  `decision:`.
- **(B) Tolerar na leitura:** o comando do oráculo casa QUALQUER um dos 4 nomes
  (`status|decision|verdict|approval_gate.*decision`) com APPROVED. Frágil —
  aprova por substring, não por contrato.
- **(C) Enforcear o `expected_output.verdict` do tasks.yaml:** schema validation
  real (jsonschema/pydantic) na saída do T4-JUDGE antes de persistir. Mais
  robusto, mais trabalho.

A escolha depende de qual contrato é o "oficial" — `tasks.yaml.verdict` (documentado)
ou `decision:` (o que o oráculo já casa). A divergência nasce de não ter sido
decidido.

## Pode acontecer de novo?

**SIM** — já aconteceu em pelo menos 7 de 12 T4s (58%). A raiz é a ausência de
um contrato enforced: enquanto o CrewAI gerar YAML livre e o oráculo casar um
nome fixo, qualquer novo agente/prompt produce um formato diferente. Sem
mecanismo, recai. **Este incidente DEVE virar regra/mecanismo.**

Candidata a regra (promover após escolher A/B/C):

> O verdict do T4-JUDGE tem UM campo canônico, enforced na escrita E casado
> pelo oráculo. Os quatro nomes atuais (status/decision/verdict/approval_gate)
> são a evidência do bug: sem contrato enforced, cada prompt de agente inventa
> o seu. O `expected_output.verdict` do tasks.yaml é a fonte da verdade; código
> valida na escrita, oráculo casa o mesmo campo.

Interage com: regra 16 (todo problema recorrente vira mecanismo), regra 32
(regra declara seu mecanismo — esta só se cumpre com schema enforcement real,
não com texto). Supera a suposição implícita de que "o agente segue o
expected_output" — ele não segue, porque nada o obriga.
