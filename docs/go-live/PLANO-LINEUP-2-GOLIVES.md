# The Lineup — whitelist gamificada viral + plano dos 2 go-lives ($0 infra)

> Resposta do Fable à ESCALADA-3 (2026-08-30), integrada com a ESCALADA-2.
> Fontes: os 4 documentos da escalada, nada mais explorado (instrução
> econômica respeitada). Toda mecânica cita o pilar da pesquisa que a
> sustenta (§N = seção de pesquisa-gamificacao-whitelist.md).
> Números de pontos/tiers são DIALS DE POLÍTICA do dono — propostos aqui,
> girados por ele; nenhum é medição e nenhum vai à copy como fato.

## 0. A ligação estratégica que amarra as duas escaladas

O prêmio da fila é o produto (§5), e o produto (ESCALADA-2) é a seleção
de modelo por task alimentada por medição. Logo o epic meaning (§8, White
Hat CD1) da whitelist é VERDADEIRO por construção: **cada run assinada no
bestmodel melhora a predição de "qual modelo vence esta task" para todo
mundo** — contribuir não é ritual de fila, é construir o motor que o tier
premium vai servir. First Wave = os primeiros a surfar os modelos servidos
sob demanda quando o gate abrir (sem data, sem preço — gated, régua de
honestidade intacta).

## 1. Mecânica completa (Entregável 1)

### O loop (Hooked §8, com base White Hat)

    entrada (issue) → conquista imediata (endowed §4) → contribuição ou
    indicação → pontos → tier → status público opt-in → convite carrega
    o próximo trigger (investment §8; compromisso público §9)

### Porta de entrada e medidor — SEM backend, tudo auditável

- **Porta llms.surf**: abrir issue pelo template da waitlist (já existe
  como porta hoje). O template ganha 2 campos: `referred by: @handle`
  (opcional) e o checkbox A3 (ver §Copy). O issue público É o compromisso
  público de Cialdini (§9) — de graça, no GitHub.
- **Porta bestmodel.run**: a primeira run ASSINADA (Ed25519 — já existe
  por usuário) entra o handle na lista do bestmodel automaticamente.
  Duas listas separadas (decisão do dono); UM ledger de pontos que
  atravessa, chaveado por handle do GitHub.
- **Medidor ($0)**: GitHub Action agendada (cron ~6h) no llms.surf:
  1. lê as issues da waitlist (labels + corpo → referred-by);
  2. puxa o export por-contribuidor do bestmodel (arquivo JSON no repo
     dele, raw.githubusercontent — o RANK POR CONTRIBUIDOR que falta lá
     é o único build novo do lado bestmodel);
  3. aplica a tabela de pontos, escreve `data/lineup.json`, commita.
  A página do Pages renderiza SÓ desse JSON. Auditoria = git history do
  arquivo: qualquer um recomputa. Honestidade por mecanismo, não por
  promessa — posição só existe porque um comando a calcula (a régua).

### Tabela de pontos v0 (dial do dono — proposta)

| Ato (verificável) | Pontos | Por quê (pesquisa) |
|---|---|---|
| Entrar na fila (issue aberto) | 1 | endowed progress: ninguém entra do zero (§4) |
| Indicação convertida | 3 | canal de melhor unit economics (§2); converte só quando o indicado CONTRIBUI (anti-fraude §5 deste plano) |
| Run assinada (bestmodel) | 2 | crowdsourcing pontua a contribuição (§1) |
| Reprodução de run alheia | 3 | o ato de maior valor científico; badge Same Wave |
| Divergência/fake pego | 5 | protege o motor; raro e caro |
| Custom mode compartilhado (Discussion) | 2 | alimenta o produto llms.surf |

### Tiers FINITOS (nunca leaderboard global infinito — §6)

| Tier | Entra com | O que dá |
|---|---|---|
| **Paddling Out** | issue aberto (1 pt) | você JÁ está na água: página mostra "a 2 pts do Lineup" (goal gradient §4) |
| **In the Lineup** | 3 pts | handle na página (se opt-in A3), badge de entrada |
| **On the Peak** | 10 pts | prioridade de fila no seu produto; menção no hall opt-in |
| **First Wave** | 25 pts | primeiro acesso quando o gate de cloud abrir; elegível ao giveaway de free tokens (decisão do dono, gated) |

- **First Wave usa o N=25 que JÁ é política do dono (D6/D9)**: os
  primeiros 25 por pontos são a first wave — nenhum número inventado,
  o cap é o gate de venda existente.
- Superfície de ranking: (a) barra de progresso PESSOAL sempre ("2 pts
  até On the Peak"); (b) coorte da sua wave (finita, pequena); (c) hall
  dos top opt-in. Nada de tabela global infinita (§6: desmotiva a base).
- **Surpresas honestas (§7, RPE)**: drops de pontos-bônus anunciados
  DEPOIS do fato ("reproduções desta semana valeram dobro") e gravados
  no git do lineup.json. Surpresa verdadeira sinaliza dopamina; surpresa
  inventada quebra a régua — só a primeira existe aqui. Frequência: dial
  do dono, começar raro (1/mês).

### Como as duas whitelists atravessam

Tier é calculado do ledger único e vale NOS DOIS produtos: dentro de
cada lista, ordena-se por (tier desc, ordem de entrada asc — número do
issue / timestamp da primeira run). Contribuir no bestmodel sobe sua
posição no llms.surf e vice-versa — "two products, one engine" vira
mecânica, não slogan.

## 2. Nomenclatura (Entregável 2) — 3 esquemas, argumento neuro de cada

**A. The Lineup** (recomendado) — programa: "The Lineup"; tiers acima;
badges abaixo. Argumento: o lineup é a fila REAL do surf — posição
visível, status social e ordem legítima. Ativa goal gradient (§4, posição
é gradiente visível), o queue-jump comprovado de Robinhood/Monzo/Harry's
(§5) e o labelling identitário "you're in the lineup" (§9). Casa com a
copy já shipada ("List order, first wave first") e com o léxico
paddle/tow/surfcheck.

**B. Earn Your Wave** — espinha em accomplishment (Octalysis CD2, §8):
tudo é "earned", nada é dado; resiste a entitlement e soa meritocrático.
Mais fraco em viralização: sem inveja posicional (§5), o motor de
indicação perde tração.

**C. First Wave Crew** — espinha tribal (CD5 + função 5 dos badges §3):
pertencimento e identidade de grupo fortes, ótimo para comunidade quente;
fraco em urgência de escalada — aconchegante e estático.

### Badges (cada um INSTRUI uma ação — Antin/Churchill §3, função 2)

| Badge | Ação que ensina |
|---|---|
| **Duck Dive** | abriu o issue — atravessou a arrebentação (entrar) |
| **Tow-In** | primeira indicação convertida — você rebocou alguém |
| **Signed Set** | primeira run assinada no bestmodel |
| **Same Wave** | reproduziu a run de outra pessoa e bateu o resultado |
| **Shark Eye** | pegou uma divergência/fake |
| **Shared Break** | compartilhou um custom mode na Discussion |

Badge = label no issue + campo no lineup.json + render no Pages. $0.

## 3. Mapa de copy (Entregável 3)

### llms.surf (seção whitelist → seção The Lineup)

- Título mantém a frase honesta existente: "The Lineup — list order,
  first wave first; contribution is what climbs."
- 3 linhas de mecânica: entre (issue) → contribua ou indique → suba de
  tier. Link "how this is computed" → RULES na própria página/repo: a
  tabela de pontos, o cron da Action e o git history como auditoria.
- Progresso pessoal: "you are N pts from <tier>" — só porque lineup.json
  o calcula. Nunca "restam X vagas": o único cap real é First Wave = 25
  (política D6/D9, declarada como regra, não como escassez teatral).
- **Checkbox A3, texto pleno**: "[x] show my handle on the public Lineup
  page — uncheck to stay off the page; your points and place are yours
  either way." Desmarcar não pune (pontos e ordem preservados; só a
  listagem pública sai). O issue é público por natureza do GitHub — a
  página é que obedece o checkbox; dito com todas as letras.
- Email continua dormante (sem endpoint, Pages estático) — rank por
  handle não precisa de email. $0 mantido.

### bestmodel.run (entra o link de volta + convite)

- Bloco "two products, one engine" com link para llms.surf (fecha o gap
  verificado hoje).
- Convite à contribuição: "every signed run scores in the shared Lineup"
  + mini-tabela de pontos dos atos bestmodel (run/reprodução/fake).
- Badge do contribuidor junto ao handle quando o rank-por-contribuidor
  existir (S24 já mostra badges de source-class — mesma superfície).

## 4. Plano dos 2 go-lives integrados (Entregável 4)

Ordem de implementação (mecanismo ANTES de copy — regra da casa: claim
só depois do mecanismo existir):

| # | Item | Onde | Esforço | Custo |
|---|---|---|---|---|
| 1 | Template do issue: campos referred-by + checkbox A3; labels de tier/badge | llms.surf | ~1h | $0 |
| 2 | Rank por contribuidor (export JSON por handle, das runs assinadas) | bestmodel | ~2-3h | $0 |
| 3 | Action cron: issues + export → data/lineup.json commitado | llms.surf | ~2h | $0 |
| 4 | Página Lineup no Pages (tiers, badges, progresso pessoal, RULES) | llms.surf | ~2h | $0 |
| 5 | Passe de copy dos dois sites (mapa acima) | ambos | ~1h | $0 |
| 6 | Gates: honesty estende à página Lineup (números SÓ de lineup.json); teste do checkbox A3 presente e pré-marcado | llms.surf | ~1h | $0 |

Total ~9-10h de sessão nossa, $0 de infra. Itens 1, 3, 4 e 6 numa sessão
llms.surf; item 2 numa sessão bestmodel; item 5 fecha.

**O que só o dono faz**: (a) tirar o DNS llms.surf do parking e apontar
para o Pages (bloqueia a Phase A contra host real); (b) escolher o
esquema de naming (default: A — The Lineup); (c) girar os dials (tabela
de pontos, cadência de surprise drops; First Wave=25 já é política D6/D9);
(d) manter o veto: nada de Vast até o "sobe" voltar.

**Atos de dia de lançamento** (nesta ordem, depois do gate verde no
commit deployado + Phase A A2 contra o host real): abrir a Discussion
"share your break" (aprovada, D4) → fixar o issue-porta do Lineup →
publicar o anúncio (COPY.md) → primeiro surprise drop gravado →
escrever docs/v1-smoke-log.md (A3 do SMOKE: log ou não aconteceu).

## 5. Riscos e anti-vazamento (Entregável 5)

| Fraude/risco | Mecanismo mínimo que barra |
|---|---|
| Auto-indicação / sockpuppet | Indicação só CONVERTE quando o indicado faz a primeira contribuição verificável (run assinada / reprodução / mode); conta indicada mais nova que [dial: 30 dias] não converte. Issue vazio rende só entrada (1 pt), nunca escala. |
| Farm de reprodução em dupla (A reproduz B, B reproduz A, em loop) | Par de handles credita Same Wave UMA vez por par; reprodução exige chave Ed25519 distinta e resultado batendo na tolerância do bestmodel (anti-fraude existente). |
| Run lixo para farmar pontos | Pontos só para run que passa a validação do bestmodel (assinatura + harness); o motor já rejeita fake==fake (S26). |
| Posição inventada na copy | Honesty test pina TODO número da página Lineup a data/lineup.json gerado pela Action — número manual reprova o gate. |
| Dark pattern de consentimento | Teste mecânico: checkbox A3 presente, visível, pré-marcado, e o texto declara que desmarcar não perde pontos/lugar. Falhou, gate vermelho. |
| Leaderboard desmotivador (§6) | A página não TEM ranking global infinito por construção — só progresso pessoal, coorte e hall opt-in. Revisão de copy no gate. |
| Vazamento de escassez falsa | Único cap público: First Wave = 25 (política D6/D9 preexistente). Qualquer outra quantia/data/vaga na copy = reprova na régua. |

## Ligações pesquisa → decisão (índice de auditoria)

§1 contribuição pontuada (não a entrada) · §2 indicação como canal
central com conversão-na-contribuição · §3 seis badges, um por ação ·
§4 entrada = 1 pt + próximo passo nomeado (endowed) · §5 prêmio = fila
do próprio produto, cap real 25 · §6 sem leaderboard global; tiers
finitos + coorte · §7 surprise drops verdadeiros, post-hoc, raros ·
§8 White Hat como base (epic meaning verdadeiro via bestmodel),
Black Hat pontual (escassez real, surpresa) · §9 issue público como
compromisso + handle citado na página (opt-in A3).
