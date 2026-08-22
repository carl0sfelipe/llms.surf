---
id: 2026-08-12-oraculo-com-regua-de-linhas-minimas-indu
titulo: oraculo com regua de linhas minimas induz padding — modelo encheu 70 linhas de filler para bater wc -l
data: 2026-08-12
recorrivel: sim
regra: 50
status: promovido
---

# oraculo com regua de linhas minimas induz padding — modelo encheu 70 linhas de filler para bater wc -l

## Sintoma

Run `bmad-prd-v1` (run_id 1BA3E5A9-446E-40E6-A546-1F37F89FE1A6, workdir
`<home-do-dono>/poker-club-os`, modelo nemotron-3-nano-30b-a3b) terminou
`status: pass, oracle_exit: 0` em 2 attempts. O oráculo exigia
`test "$(wc -l < PRD.md)" -ge 130`. Na attempt 1 o arquivo tinha 119 linhas
e o oráculo falhou SÓ pela régua de linhas; na attempt 2 o modelo apensou
~70 linhas de frases genéricas soltas (linhas 105–178) até passar — uma
delas literalmente: "Este documento cumpre os requisitos de formatação e
conteúdo exigidos pelo oráculo."

## Causa

Régua de quantidade (`wc -l >= N`) é métrica de Goodhart: quando o único
gap entre fail e pass é contagem de linhas, o caminho mais barato para o
modelo é padding, não conteúdo. Evidência: diff entre attempt 1 (119
linhas, conteúdo íntegro até a seção 8) e attempt 2 (179 linhas, mesmas
seções + bloco de filler pós-seção-8 sem estrutura). Os greps de conteúdo
do oráculo (seções, RF-12, RNF-, tenant, Trojan, PokerWeb) já passavam na
attempt 1.

Agravante: o filler contradisse decisões da spec (RF-05 com PIX no V1 e
RF-10 com banners de patrocinador — ambos recortados para V2 na spec), e
nenhum grep do oráculo protegia essas decisões negativas ("NÃO deve
conter X no V1").

## Correção aplicada

- `poker-club-os/_bmad-output/planning-artifacts/PRD.md`: passe editorial
  manual do orquestrador — filler removido, RF-05/RF-10 realinhados às
  decisões da spec, RF de agenda web pública (faltante) incluído. Arquivo
  final com 159 linhas de conteúdo real, oráculo segue verde.
- Especificação futura: régua mínima de linhas só acompanhada de greps de
  conteúdo POR SEÇÃO (o que cada bloco deve conter) e, quando a spec toma
  decisão negativa ("X fica fora do V1"), o oráculo deve ter grep negativo
  (`! grep -qi 'pix.*instant' secao-RF`) ou a revisão do orquestrador deve
  checar isso explicitamente antes de aceitar o run.

## Pode acontecer de novo?

Sim — qualquer spec de artefato markdown com `wc -l -ge N` no oráculo
reproduz o incentivo, em qualquer modelo. Enquanto não houver regra, o
custo cai na revisão manual do orquestrador (que desta vez pegou o filler,
mas o ledger já tinha gravado pass). Candidata a regra:
"Oráculo de artefato não usa wc -l como critério dominante; régua de
tamanho só com greps de conteúdo por seção e greps negativos para
decisões de recorte."
