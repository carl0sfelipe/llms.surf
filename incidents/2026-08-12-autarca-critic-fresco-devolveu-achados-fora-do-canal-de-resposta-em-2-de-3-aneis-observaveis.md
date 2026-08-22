---
id: 2026-08-12-autarca-critic-fresco-devolveu-achados-fora-do-canal-de-resposta-em-2-de-3-aneis-observaveis
titulo: Critic fresco do AUTARCA (subagent cavecrew-reviewer) devolveu os achados fora do canal de resposta em 2 de 3 anéis observáveis — a lista linha-a-linha veio no campo de resumo visível-ao-usuário e a resposta oficial dizia "achados acima"; cada ocorrência custou um resume manual do executor
data: 2026-08-12
recorrivel: sim
regra: nao — regra candidata: validador mecânico de FORMATO na saída do critic (extensão da regra 2 do pythia, que valida campos semânticos)
status: aberto
interage_com: "2026-08-12-autarca-god-mode-7-aneis-esgotou-o-backlog-mas-o-hardening-dos-incidents-da-manha-degradou-na-propria-sessao-que-o-escreveu"
interage_com: "2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco"
---

# Critic devolve achados no canal errado — o contrato de saída é só prompt

## Sintoma

Nos 3 anéis com vereditos observáveis no transcript pós-sumário
(A-5/A-6/A-7 do AUTARCA, subagents `f63ff322`, `c3a21195`, `2ebe95bc`),
o prompt do critic exigia "responda APENAS com uma linha por achado no
formato `path:line: emoji severidade: problema. fix.` (...) sem prosa
adicional". Resultado por anel:

- **A-5 (`f63ff322`)**: a resposta não trouxe a lista; o executor teve de
  RESUMIR o subagent pedindo "reenvie AGORA todos os achados no formato
  (...)" para obter as linhas (transcript).
- **A-6 (`c3a21195`)**: a resposta oficial foi literalmente "Revisão
  concluída — achados acima." — a lista completa tinha ido para o campo
  de resumo visível-ao-usuário do subagent, não para a resposta. Mais um
  resume para reemitir no canal certo (transcript).
- **A-7 (`2ebe95bc`)**: formato correto de primeira.

2 de 3 = taxa de falha de 66% do contrato de saída no trecho observável.
Custo por ocorrência: 1 turno extra de subagent + latência; risco real:
se o subagent não fosse retomável (expirado, sessão morta), o veredito
estruturado se perderia — e é ele que o fechamento do anel consome.

## Classe

Falha de CONTRATO, não de julgamento: o conteúdo dos vereditos foi bom
(os achados do A-5 e A-6 incluem os melhores da cadeia — vazamento da
sala cash, "mesmo ato" não-atômico). O que falhou é que o formato
exigido vive só no prompt: nenhum código valida que a resposta contém
linhas parseáveis antes do executor aceitá-la. É a face "canal/formato"
do mesmo problema que o pythia resolveu para campos semânticos (score
fora de range, enum inválido) com o validador do `rank import` — aquele
valida O QUE o juiz disse; ninguém valida ONDE e EM QUE FORMA o critic
respondeu.

## Regra candidata

**Validador de formato na saída do critic, falha-fechado com retry
automático**: o fechamento de anel só aceita veredito cuja resposta
oficial contenha ≥1 linha casando `^\S+:\d+: (🔴|🟡|🔵|❓)` + as linhas
`totals:`, `biggest_gap:` (não-vazio, já coberto pela cláusula existente)
e `nota_prevista_dono:`. Reprovou → re-prompt automático do MESMO
subagent (1 retry; 2ª falha conta no teto do anel). Implementável como
função de 15 linhas no runner de host-mode (regra 1 do ouroboros/pythia);
teria convertido os 2 resumes manuais em retries mecânicos e tornado a
falha contável no ledger.

## Evidência

- Transcript com os 3 vereditos e os 2 resumes:
  `~/.cursor/projects/Users-mini-poker-club-os/agent-transcripts/
  e336d9b1-cd63-46be-bba1-7c5fb1e9b904/` (ids `f63ff322`, `c3a21195`,
  `2ebe95bc`; a resposta "Revisão concluída — achados acima." é literal).
- Conteúdo final dos vereditos (pós-resume) refletido em
  `~/poker-club-os/CHECKPOINTS.md`, blocos A-5/A-6/A-7, e no ledger
  (campo `critic` das 3 linhas de fechamento).
- A-1..A-4: vereditos registrados em CHECKPOINTS.md; o transcript desses
  anéis foi sumarizado e NÃO afirmo taxa de falha neles (por isso o
  título diz "2 de 3 observáveis").
