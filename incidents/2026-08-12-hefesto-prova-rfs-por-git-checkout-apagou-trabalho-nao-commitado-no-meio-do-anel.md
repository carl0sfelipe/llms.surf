---
id: 2026-08-12-hefesto-prova-rfs-por-git-checkout-apagou-trabalho-nao-commitado-no-meio-do-anel
titulo: Prova de detecção R-FS executada via `git checkout <arquivo>` apagou mudanças não commitadas no meio do anel CP-1 do HEFESTO — o instrumento de prova era destrutivo por construção e a correção adotada (sabotagem por edição pontual) é protocolo, não guarda
data: 2026-08-12
recorrivel: sim
regra: nao — regra candidata "prova R-FS como primitiva não-destrutiva" (regra 6 do postmortem principal do hefesto)
status: aberto
interage_com: "2026-08-12-hefesto-god-mode-6-stories-verdes-critic-fresco-pegou-os-2-blockers-e-checkpoint-manuscrito-duplicou"
---

# Prova R-FS destrutiva — git checkout no meio do anel

## Sintoma

Anel CP-1 do HEFESTO (story EPIC-01-S01, datetimes UTC aware): a regra R-FS
do repo exige ver cada detector novo FALHAR antes de fechar a story. Para
provar o guard test de timezone vermelho, o executor reverteu a coluna
`start_time` usando `git checkout` do arquivo — que restaurou o
`app/db/models.py` INTEIRO da versão antiga e apagou TODAS as mudanças não
commitadas do anel em andamento (a story ainda não tinha checkpoint). O
trabalho foi reaplicado e re-verificado (oráculo verde de novo) dentro do
mesmo anel.

Registro contemporâneo: bloco "Incidente de processo" do CP-1 em
`~/poker-freeroll-radar/CHECKPOINTS.md` (commit `3d43312`), escrito para o
dono na hora, com a lição: "prova de detecção agora reverte por edição
pontual, nunca por checkout de arquivo com trabalho não commitado".

## Por que é um incident PRÓPRIO e não uma linha do postmortem principal

O postmortem principal trata da arquitetura de proteção do modo. Este trata
de uma classe específica: **o instrumento de prova era destrutivo por
construção**. A prova R-FS pede "deixe o detector vermelho e mostre" — e o
caminho mais curto para "reverter uma mudança" num repo git é `checkout`,
que não distingue "mudança que estou provando" de "todo o resto do trabalho
não commitado no mesmo arquivo". Em god mode, o estado não-commitado do anel
corrente é exatamente o produto da sessão — a prova de detecção, feita do
jeito ingênuo, come o próprio anel.

Três agravantes:

1. **Nenhuma guarda mecânica existia ou existe**: nada impede o próximo
   executor (ou o mesmo, sob pressão de teto) de usar checkout de novo. A
   correção virou frase em CHECKPOINTS.md — protocolo.
2. **A perda foi silenciosa no momento do comando**: `git checkout <path>`
   retorna 0 e não lista o que descartou. O executor só percebeu porque o
   oráculo quebrou de um jeito inesperado logo depois.
3. **O dano foi limitado por sorte de escopo**: só `models.py` foi
   revertido e as mudanças eram reconstruíveis do contexto da conversa. Uma
   prova que revertesse um diretório (ou `checkout .`) teria comido o anel
   inteiro sem reconstrução barata.

## Mitigação aplicada na hora

Mudanças reaplicadas por edição, oráculo re-executado até verde, e as 6
provas R-FS seguintes (CP-2..CP-6, incluindo as duas do CP-6) feitas por
**edição pontual reversível** (sabotagem de 1 linha → teste vermelho →
restauração da mesma linha → suíte inteira verde) — todas registradas nos
blocos "Prova de detecção" de CHECKPOINTS.md, as do CP-6 com terminal na
sessão. Zero reincidência DEPOIS da lição — mas por disciplina, não por
guarda.

## Regra candidata para a v4

**Prova R-FS como primitiva não-destrutiva do core** (= regra candidata 6
do postmortem principal): `oracfit sabotage <alvo> --patch <sabotagem>`
que (1) recusa rodar se `git status` mostra trabalho não commitado no alvo
sem `--stash-first`, (2) aplica a sabotagem como patch reversível, (3) roda
o teste apontado esperando exit != 0, (4) reverte o patch e re-roda a suíte
esperando verde, (5) imprime o par vermelho/verde como evidência do anel.
Custo: script de ~30 linhas. Cobre os 3 agravantes: nunca checkout, falha
alto se houver estado em risco, e a evidência da prova sai mecânica em vez
de manuscrita.

## Evidência

- Registro contemporâneo do incidente e da lição:
  `~/poker-freeroll-radar/CHECKPOINTS.md`, bloco "Incidente de processo" do
  CP-1 (commit `3d43312`).
- Transcript da sessão (evento da reversão e reaplicação):
  `~/.cursor/projects/Users-mini-poker-freeroll-radar/agent-transcripts/a03c8107-3dc3-4466-8983-fb228bf8c375/`.
- Provas R-FS subsequentes pelo método corrigido: blocos "Prova de
  detecção" dos CP-2..CP-6 no mesmo CHECKPOINTS.md; as duas do CP-6
  (insert desligado ⇒ 0≠50 com 302 verde; `link.id` pós-rollback ⇒ detector
  FAILED) nos terminais da sessão.
