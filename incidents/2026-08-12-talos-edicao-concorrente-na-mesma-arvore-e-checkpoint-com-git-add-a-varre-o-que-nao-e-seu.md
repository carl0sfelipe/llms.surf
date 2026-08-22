---
id: 2026-08-12-talos-edicao-concorrente-na-mesma-arvore-e-checkpoint-com-git-add-a-varre-o-que-nao-e-seu
titulo: Agente paralelo reescreveu o README no working tree no MEIO da volta 3 do TALOS e o checkpoint com `git add -A` o commitou junto — detecção só aconteceu porque a colisão foi no MESMO arquivo que eu editava (2ª varredura real da classe árvore-compartilhada, 2ª codificação de add -A em yaml de god mode no dia)
data: 2026-08-12
recorrivel: sim
regra: nao — regra candidata convergente (isolamento de árvore, = ouroboros 5 / hefesto 4) com forma endurecida: pathspec POSITIVO derivado do plano da volta
status: aberto
interage_com: "2026-08-12-talos-god-mode-5-voltas-verdes-mas-mode-validate-falha-no-proprio-yaml-e-todo-portao-era-protocolo"
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-08-12-hefesto-god-mode-6-stories-verdes-critic-fresco-pegou-os-2-blockers-e-checkpoint-manuscrito-duplicou"
---

# Edição concorrente na mesma árvore + checkpoint `git add -A` — a varredura só não foi silenciosa por sorte

## Sintoma

Volta 3 do TALOS (~21:55, sincronização de docs): no meio da volta, o
`README.md` do `~/now.services2.0` foi REESCRITO no working tree por um
processo paralelo, não commitado, externo à sessão (havia outra sessão de
agente ativa na máquina — o texto novo citava artefatos que EU tinha criado
nesta sessão, `talos-oraculo.sh` e o FR-14 completo, ou seja: o paralelo
leu meus commits). Registro durável: `docs/diario-talos.md` linhas 82-92
(commit `eea292c`).

A detecção foi ACIDENTE, não detector: meus `StrReplace` no README falharam
porque o texto-alvo já não existia. Se o paralelo tivesse tocado QUALQUER
outro arquivo, o checkpoint da volta — `git add -A && git commit`, conforme
codificado na **linha 92 do `~/oracfit/core/modes/talos.yaml`** — o teria
commitado em silêncio com a minha autoria. Foi o que de fato aconteceu com o
README, só que às claras: auditei o conteúdo contra o checklist da volta
(números conferidos um a um, PRD como fonte, stack fiel aos ADRs), APROVEI e
adotei com atribuição explícita no diário. Medição: dentro de `eea292c`, o
README tem 77 inserções / 114 remoções (`git show eea292c --stat`:
README 191 linhas alteradas; total do commit 131+/114−, sendo 32+ do
epics.md e 22+ do diário).

## Por que é um incident PRÓPRIO

Classe de COORDENAÇÃO multi-agente em árvore compartilhada — nem ambiente,
nem contrato do modo. E é recorrência dupla, com agravamento:

1. **2ª varredura REAL da classe em um dia:** o ouroboros (sintoma 3) varreu
   arquivos de um subagent web no commit `af029f7` de lá — "commits com
   autoria mentirosa". Aqui a varredura levou trabalho de OUTRA SESSÃO
   inteira. A diferença: lá ninguém auditou antes do commit; aqui a
   auditoria aconteceu — mas só porque a colisão foi no mesmo arquivo e meus
   edits quebraram. O mecanismo de detecção foi "sorte de colisão".
2. **2ª codificação de `git add -A` em yaml de god mode no mesmo dia:** o
   hefesto (sintoma 4) tem `add -A` na linha 86 do yaml dele, sem dano por
   árvore de agente único; o talos tem na linha 92, com o dano acima. Nos
   dois casos o anti-padrão foi promovido a SPEC do modo — e o postmortem do
   ouroboros, que documenta exatamente isso, estava commitado no repo do
   oracfit desde 21:55:14 (`c6768a3`), 4 minutos ANTES do meu checkpoint da
   volta 3 (21:59:37) executar o `add -A`. Conhecimento em incidents/ não
   alcança run em andamento.
3. **Agentes se leem via git, mas não se coordenam via árvore:** o paralelo
   escreveu um README já em dia com os MEUS commits de 10 minutos antes —
   leitura cruzada funciona; o que não existe é qualquer sinal de "há outro
   escritor nesta árvore" (lockfile, manifest, worktree).

## Mitigação aplicada na hora (protocolo)

Em vez de brigar pelo arquivo: auditoria do conteúdo contra o checklist da
volta, adoção com atribuição registrada no diário, minhas edições
redundantes descartadas. O oráculo rodou mesmo sendo volta de docs e
confirmou que o paralelo não quebrou nada (diário linhas 93-94). Nada disso
era exigido por mecanismo — outro executor teria commitado sem ler.

## Regra candidata para a v4 (CONVERGENTE, forma endurecida)

Converge com a regra 5 do ouroboros (isolamento de árvore por agente /
proibição de `add -A` multi-agente) e a regra 4 do hefesto (lint de
`add -A` no `mode validate`). Forma endurecida com evidência daqui:

**Pathspec POSITIVO derivado do plano da volta.** O plano da volta (escrito
antes do build) lista os paths que o build pode tocar; o `ring close`
commita SOMENTE esses paths e FALHA se `git status --porcelain` acusar dirty
paths fora da lista — forçando a decisão explícita que aqui foi voluntária:
adotar com atribuição (path entra na lista com bloco `DECLARACAO:` no
checkpoint) ou deixar fora do commit. Cobre o caso que a simples proibição
de `add -A` não cobre: o executor listar paths à mão e AINDA ASSIM varrer
mudança alheia num path legítimo do plano. Custo: comparação de duas listas,
~20 linhas no runner do anel.

## Evidência

- Registro da adoção auditada: `~/now.services2.0/docs/diario-talos.md`
  linhas 82-92 (commit `eea292c`).
- Medição da varredura: `git show eea292c --stat` (README.md 191 linhas;
  77+/114− derivado do total 131+/114− menos epics 32+ e diário 22+).
- Anti-padrão em spec: `~/oracfit/core/modes/talos.yaml` linha 92
  (`rg -n "git add -A" core/modes/talos.yaml`).
- Linha do tempo da não-propagação: `git log --format='%h %ci' -1 c6768a3`
  (postmortem do ouroboros, 21:55:14) vs `eea292c` (21:59:37).
- StrReplace falhando por texto-alvo inexistente: transcript da sessão
  (`~/.cursor/projects/Users-mini-now-services2-0/agent-transcripts/4b504622-…`).
- Irmãos: incident do ouroboros (sintoma 3, commit `af029f7` de lá) e do
  hefesto (sintoma 4, yaml linha 86).
