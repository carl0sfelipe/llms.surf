# ESCALADA-3 — Fable: whitelist gamificada (viralização) + plano dos 2 go-lives

> Pedido do dono, 2026-08-30, NOITE. Complementa (não substitui) a
> ESCALADA-2-FABLE-MODELO-POR-TASK.md, que será colada junto.
> **Instruções econômicas para o Fable**: NÃO explore o repositório —
> este arquivo + os 2 listados abaixo são autossuficientes. Leia na ordem,
> faça as ligações estratégicas e entregue o plano. Suas saídas são
> julgadas como decisão de arquitetura de crescimento, não como código.

## Arquivos locais (ler nesta ordem)

1. `docs/go-live/pesquisa-gamificacao-whitelist.md` — digest de pesquisa
   compilado hoje (gamificação condicional, referral economics, badges,
   endowed progress, casos Robinhood/Monzo/Harry's, lado escuro de
   leaderboards, neurociência RPE/wanting, Octalysis×Hooked, guard-rails).
2. `docs/go-live/ESTADO-SESSAO.md` — âncora do estado: repos, entregas,
   decisões do dono, fila pendente.

## Contexto comprimido (o resto está nos arquivos acima)

- **Dois produtos, um motor**: llms.surf (dispatcher local: modelo caro
  pensa, modelos grátis suam, oráculo mecânico decide) +
  bestmodel.run (mede qual modelo vence cada objetivo — benchmark, não
  hype). O llms.surf site já diz "two products, one engine"; o
  bestmodel.run ainda NÃO linka de volta (gap verificado hoje).
- **Nada sobe no Vast; cloud NÃO está ativo.** A superfície pública de
  cloud é SÓ a whitelist gamificada (decisão do dono, auditada nas duas
  superfícies). Sem preço, sem data, sem quantia — o futuro é "gated".
- **llms.surf**: S1–S9 completos, gate 40/40, site de teste no ar
  (github.io), DNS ainda em parking. Whitelist hoje = issue público do
  GitHub (porta) + copy de tiers ("List order, first wave first;
  contribution is what climbs"). Email-plugável existe mas fica dormente
  sem endpoint (static Pages não envia confirmação).
- **bestmodel.run**: vivo — leaderboard, runs assinadas (Ed25519 por
  usuário), badges de source-class, anti-fraude, 312 testes. Falta o
  RANK POR CONTRIBUIDOR (existe trust por RUN).
- **Pendências go-live**: Phase A contra host real (bloqueada no DNS do
  dono), smoke log, Discussion "share your break", anúncio (COPY.md).

## O pedido especial (o dono considera isto o mais importante)

A whitelist é a **alavanca de viralização**. O dono quer técnicas
avançadas, com base de neuromarketing, para transformar a entrada numa
escalada: **"indique e suba no ranking para atingir tiers melhores"**,
com **nomes e badges legais** — tudo envolvendo neurociência
(neuromarketing). O Fable desenha essa mecânica COMPLETA e o plano dos
dois go-lives integrados, **barato** (sem cloud, sem backend pago:
GitHub issues/pages/labels/Actions; rank v0 por handle do GitHub).

### Constraints não negociáveis (a mecânica vive dentro delas)

1. **A3 — opt-out transparente**: checkbox visível pré-marcado; desmarcar
   é livre e respeitado. Gamificação dentro do consentimento, nunca
   contra ele (nada de dark pattern de consentimento).
2. **Honestidade verbal**: NUNCA inventar quantia, data, vagas ou
   posição. Posição/fila só se houver mecanismo real que a calcule.
   Surpresas variáveis (RPE) são bem-vindas SE forem verdadeiras.
3. **Camadas White Hat como base, Black Hat pontual** (Chou): epic
   meaning ("seu benchmark treina as predições de todos"), accomplishment
   (tiers finitos), empowerment (contribuição técnica real) — escassez e
   surpresa em doses, nunca ansiedade como alicerce. Leaderboard: NUNCA
   global-infinito (desmotiva a base — ver pesquisa §6).
4. **Badges que instruem**: cada badge ensina UMA ação (Antin/Churchill).
5. **Endowed progress**: ninguém entra do zero (Nunes/Drèze).
6. **O prêmio é o produto**: subir na fila / tier / first wave — o caso
   Robinhood/Monzo/Harry's, com CAC ≈ 0.

### Entregáveis esperados do Fable (decisão, não código)

1. **Mecânica completa da whitelist viral**: loop de entrada → primeira
   conquista → indicação → tier → status público; como "indique e suba"
   funciona SEM backend (o medidor de indicação por handle/issue/Actions,
   ou o que você propor); o que conta como contribuição no bestmodel e
   como vira ponto; como as duas whitelists atravessam.
2. **Nomenclatura e badges** (tema surf/onda do llms.surf): nomes dos
   tiers, dos badges (cada um instruindo UMA ação), do programa em si.
   Propor 3 alternativas de naming com argumento neuromarketing de cada.
3. **Mapa de copy**: o que muda na página atual do llms.surf (seção
   whitelist) e o que entra no bestmodel.run (link de volta + convite à
   contribuição) — respeitando o tom honesto existente.
4. **Plano dos 2 go-lives integrados**: ordem de implementação com
   esforço estimado (horas nossas, custo $0 infra), o que o dono precisa
   fazer (DNS etc.), e o que é ato de dia de lançamento (Discussion,
   anúncio).
5. **Riscos e anti-vazamento**: onde a mecânica pode virar fraude
   (auto-indicação, issue vazio) e o mecanismo mínimo que barra.

### Como julgamos a resposta

- Ligações explícitas pesquisa → decisão (não vagueza).
- Viável em Pages/issues/Actions SEM servidor novo.
- Respeita A3 e a régua de honestidade letra a letra.
- Plano que a gente implementa numa sessão (como fizemos S1–S9 e L03A).

— Gerado pelo ZCode (sessão de implementação) a mando do dono, 2026-08-30.
