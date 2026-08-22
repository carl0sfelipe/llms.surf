---
id: 2026-08-12-talos-mcp-do-browser-morre-no-meio-do-veredito-visual-sem-fallback-declarado
titulo: Servidor MCP do browser morreu no MEIO do fluxo autenticado da volta 5 do TALOS e não voltou (2ª indisponibilidade do browser no mesmo repo) — o veredito visual não tinha caminho degradado declarado e o fallback via curl+magic-link foi improviso que deu certo
data: 2026-08-12
recorrivel: sim
regra: nao — 1 regra candidata nova no corpo (preflight de ferramenta do plano da volta + fallback de veredito visual declarado antes do build)
status: aberto
interage_com: "2026-08-12-talos-god-mode-5-voltas-verdes-mas-mode-validate-falha-no-proprio-yaml-e-todo-portao-era-protocolo"
interage_com: "2026-08-12-vision-gate-barra-inalcancavel-prompt-default-rejected"
interage_com: "2026-08-12-servidor-demo-morre-quando-a-sessao-do-s"
---

# MCP do browser morre no meio do veredito visual — god mode sem caminho degradado

## Sintoma

Volta 5 do TALOS (julgamento visual, ~22:00): depois de o browser embutido
navegar 2 páginas públicas e capturar 1 screenshot com sucesso (anúncio da
oferta em es-PY, anúncio com formulário de alerta FR-14 — os 3 itens "vistos
no browser" do diário, linhas 124-131), o servidor MCP `cursor-ide-browser`
caiu no meio do fluxo AUTENTICADO e não voltou até o fim da sessão — as
chamadas seguintes retornaram `MCP server does not exist: cursor-ide-browser`.
Registro durável: `docs/diario-talos.md` linhas 132-141 (commit `e43d22c` do
now.services2.0).

Segunda indisponibilidade do browser no MESMO repo em runs autônomos: no
loop do épico 24, o browser embutido não alcançou `localhost:3002/3001` em
4 tentativas (chrome-error com curl respondendo 200) e o julgamento visual
ficou PENDENTE — `docs/diario-loop-epic24.md` linhas 152-154. Vetores
diferentes (lá inalcançável, aqui morte do servidor no meio), efeito igual:
o estágio de veredito visual perde a ferramenta.

## Por que é um incident PRÓPRIO e não parte do postmortem

É falha de AMBIENTE (ferramenta do IDE), não de contrato nem de processo do
modo — a mesma separação que o pythia fez com o ENOSPC. E expõe uma lacuna
específica do god mode que o postmortem principal só cita:

1. **O estágio de veredito visual não declarava caminho degradado.** O plano
   da volta dizia "validar de olho"; quando a ferramenta morreu, o fallback
   foi IMPROVISADO na hora: login real via curl com o magic link capturado
   do log do transporte dev de e-mail, e assertivas de composição contadas
   no HTML renderizado (1 hero, 1 lede, 1 card, 3 inputs, 1 ajuda, 1 botão
   primário — diário linhas 138-141). Deu certo por disciplina; um executor
   com pressa declararia "visto e aprovado" e nada reclamaria — a classe do
   incident do vision-gate decorativo.
2. **A queda no MEIO do fluxo é pior que indisponibilidade na largada:** a
   metade pública da evidência existia (screenshot capturado) e a metade
   autenticada não — checkpoint "meio visto" é exatamente o tipo de estado
   parcial que contabilidade manuscrita registra como completo sem ninguém
   perceber. Aqui o diário separou explicitamente o que foi visto de olho do
   que foi verificado por HTML; isso foi protocolo.
3. **Preflight teria mudado o plano, não evitado a queda:** a ferramenta
   estava viva na abertura da volta (2 navegações ok). O valor do preflight
   aqui é registrar QUAIS ferramentas o plano assume, para que a morte no
   meio dispare o fallback declarado em vez de improviso.

Bônus de verificação que o improviso rendeu: a 1ª tentativa de login via
curl FALHOU com `error=Configuration` porque o e-mail era novo e o
`createUser` custom recusa criar usuário sem consentimento — a regra do FR-1
mordendo no caminho errado, como deve (diário linhas 135-138).

## Mitigação aplicada na hora

Fallback curl + magic link do log dev + contagem de composição no HTML da
página autenticada (200, classes do design presentes). Dev server derrubado
ao fim (`lsof -ti tcp:3010 | xargs kill`). Tudo registrado no diário da
volta, com a distinção "visto de olho" vs "verificado por HTML" explícita.

## Regra candidata para a v4 (NOVA)

**Ferramentas do plano da volta com preflight e fallback declarado.** O
plano da volta (escrito antes do build) lista as ferramentas de que o
veredito depende (browser MCP, tunnel, DB); o `ring open` checa a
disponibilidade das listadas, e para estágio de veredito VISUAL o plano é
obrigado a declarar o caminho degradado ANTES (ex.: assertivas de composição
sobre HTML renderizado via curl — o improviso desta sessão, promovido a
template). Morte da ferramenta no meio da volta → executa o fallback
declarado ou a volta fecha como INCOMPLETA no checkpoint; "visto e aprovado"
sem evidência deixa de ser escrevível. Custo: 1 seção no template do plano +
checks de disponibilidade de ~5 linhas cada.

## Evidência

- Registro durável da queda e do fallback: `~/now.services2.0/docs/diario-talos.md`
  linhas 132-141 (commit `e43d22c`).
- 1ª ocorrência da família no repo: `~/now.services2.0/docs/diario-loop-epic24.md`
  linhas 152-154 (browser não alcançou localhost; julgamento adiado).
- Erros `MCP server does not exist: cursor-ide-browser` nas chamadas
  pós-queda: transcript da sessão
  (`~/.cursor/projects/Users-mini-now-services2-0/agent-transcripts/4b504622-…`).
- Screenshot pré-queda: arquivo temporário da sessão (efêmero); a descrição
  do que foi visto está no diário — motivo pelo qual a regra candidata exige
  evidência durável no fallback.
