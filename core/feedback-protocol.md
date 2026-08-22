# Protocolo de Feedback — incidente vira regra

Módulo do `dispatch` que fecha o ciclo entre **erro que aconteceu** e **regra que impede repetição**.

## Princípio

> Um problema que pode acontecer de novo **sempre** vira regra do framework.

Lição solta em doc não protege ninguém: quem lê depois já errou. Regra em `SKILL.md` é lida por todo agente **antes** de agir, em qualquer CLI. Por isso o caminho incidente → regra é obrigatório, não opcional — e auditável por comando.

## Quem usa

Qualquer pessoa ou agente que use o `dispatch`. O canal é o mesmo para humano e para modelo: `bin/incident.sh`. Não depende de lembrar de editar `SKILL.md` na mão.

## Ciclo

```
1. Aconteceu algo ruim        → bin/incident.sh new "<título>"
2. Preencher a evidência      → editar incidents/<id>.md (sintoma, causa, correção)
3. Pode acontecer de novo?    → campo `recorrivel: sim|nao`
4. Se sim: virar regra        → bin/incident.sh promote <id> "<texto da regra>"
5. Auditoria contínua         → bin/incident.sh audit  (exit 1 se houver dívida)
```

## Uso automático (incidents/2026-07-30-feedback-de-uso-forcado-por-humano.md)

Enquanto `DISPATCH_USAGE_FEEDBACK≠0` (default), **todo** modo de dispatch
(`escalate`, `batch`, `dispatch` simples) chama `bin/emit-usage-feedback.sh`
ao terminar e grava telemetria + `incidents/uso/<id>.md` — **sem** o humano
pedir. Isso alimenta o passo 1 com evidência; promoção (passos 3–4) continua
julgamento humano. Opt-out: `export DISPATCH_USAGE_FEEDBACK=0`.

O passo 5 é o que dá dente ao princípio: incidente marcado `recorrivel: sim` sem regra promovida é **dívida aberta**, e `audit` falha com exit 1. Serve em CI, em hook, ou antes de fechar uma sessão.

## Campos do incidente

| Campo | Valores | Papel |
|---|---|---|
| `id` | `<data>-<slug>` | nome do arquivo, imutável |
| `titulo` | texto | uma linha |
| `data` | `YYYY-MM-DD` | quando ocorreu |
| `recorrivel` | `sim` \| `nao` \| `?` | **critério de promoção** |
| `regra` | números das regras no `SKILL.md`, ou `pendente` | rastro incidente ↔ regra |
| `status` | `aberto` \| `promovido` \| `descartado` | ciclo de vida |

Corpo livre, mas com três seções esperadas: **Sintoma**, **Causa (com evidência)**, **Correção aplicada**.

## Regra sobre a causa

Causa exige **evidência**, não plausibilidade. A explicação confortável costuma estar errada — no incidente fundador, "modelo free é lento" caiu com uma única query no banco de sessões. Se a evidência não existir, escreva `causa: não determinada` em vez de inventar mecanismo: incidente honesto ainda gera regra útil.

Ao descrever mais de um evento, **nunca conflatar**: cada travamento tem sua própria causa. Misturar dois vira desculpa e destrói a confiança de quem depende do relato.

## Relação com `lessons/`

`lessons/` guarda narrativa longa (contexto, timeline, aprendizado). `incidents/` guarda o registro acionável e auditável, e aponta para a lesson quando ela existir. Um não substitui o outro.

**Continuidade entre fases / harness:** lição canônica
`lessons/2026-07-30-context-boundaries-bmad-oracfit-loops.md`. Handoffs de gate
ficam em artefato (`START-*-HERE.md`, context-dump), não no transcript do chat.
Troca Cursor↔opencode↔Claude: `bin/dispatch-context-dump.sh` +
`specs/context-dump-template.md`.

## Comandos

```bash
bin/incident.sh new "dispatch travou sem output"     # cria a partir do template
bin/incident.sh list                                  # tabela: id, recorrivel, regra, status
bin/incident.sh promote <id> "NUNCA rodar X sem Y."   # vira regra numerada no SKILL.md
bin/incident.sh audit                                 # exit 1 se houver recorrível sem regra
```
