# Pesquisa — llms.surf × Bend 2: a escada de oráculos

Autor: Fable, 2026-09-19. Pedido do dono: "elabore e escreva pesquisas
aprofundadas" sobre a convergência entre o llms.surf (pré-lançamento) e o
Bend 2. Isto é direção e programa de pesquisa, não implementação. Nada
abaixo entra no site antes de ser medido (regra do go-live: nenhum número
fora da árvore).

## 0. Fontes e o que é fato vs. reivindicação

**Verificado na árvore do llms.surf** (`docs/PUBLIC-CUT.md`,
`docs/go-live/DECISIONS-D1-D10.md`, `COPY.md`, `LAUNCH-POST-LLMSSURF.md`):

- Core: `classify → mode → runner → oracle → panel`. Tiers
  `cheap|mid|expensive|vision`; roles `unlock|plan|run|map|reduce|export|render|vision_gate`.
- **Oráculo mecânico**: "nothing ships on a model's word — a real command
  must exit 0 on disk". No loader, `oracle: true|<string>` e `command:`
  para estágios mecânicos; bloco `gauntlet`. Custom modes sem mudança de
  schema (D3).
- Ledger assinado registra quem serviu cada run; 106–107 postmortems na
  árvore; The Lineup pontua **só atividade assinada**.
- Economia declarada: 1 % das tarefas ao modelo de fronteira (`tow`), 99 %
  a modelos baratos (`paddle`).
- Licença proprietária; o ímã OSS é o bestmodel.run (D1).

**Reivindicado pelo Bend 2** (bend-lang.com, repo `HigherOrderCO/Bend`,
21,6k estrelas em 2026-09-19; GUIDE.md não está acessível no raw — só via
`bend guide` após instalar):

- Type checker **é** proof checker (linhagem Lean/Rocq), "um segundo no
  máximo" num codebase médio — feito para o agente checar a cada mudança.
- `LAWS.bend` declara leis; `PROOF.bend` é escrito pela IA; `bend
  PROOF.bend` sai 0 se a lei vale. Slogan literal: "`LAWS.bend` is
  `AGENTS.md` backed by proof".
- Nativo ≈ C em 1 core; mesmo binário em 16 cores/GPU; números do site
  (game of life 7,8 s → 0,06 s) são de um M4 Max, não reproduzidos aqui.
- BendTT (teoria de tipos dependente **afim**) e BendRT (runtime paralelo).
- Autodeclarado jovem: "expect bugs"; back-end, Linux/macOS; sem browser.

Tudo do Bend é reivindicação até os experimentos da §6 rodarem nas
máquinas do dono. Esta pesquisa não repete número nenhum do site como fato.

## 1. Tese em uma frase

**O llms.surf é a economia e o recibo do loop "tente até o oráculo
aceitar"; o Bend 2 é o oráculo mais forte que existe para esse loop.**
Um tem o dispatcher, o ledger e a régua de custo mas um oráculo raso
(exit 0 de *algum* comando). O outro tem o veredito mais forte possível
(um teorema checado em sub-segundo) mas nenhum dispatcher, nenhum tier,
nenhum recibo. São as duas metades do mesmo desenho — e a página do Bend
descreve, sem nomear, exatamente o produto do llms.surf: *"the AI had to
retry until it built a wall and proved the law holds"*. Quem faz o retry,
com que modelo, a que custo, e quem assina que aconteceu? Isso é o
llms.surf.

## 2. A escada de oráculos (o conceito que une os dois)

O llms.surf já vende "oráculo mecânico" como categoria única. Não é: é
uma escada, e cada degrau prova uma coisa diferente.

| Degrau | O que "exit 0" prova | Custo do veredito | Onde o llms.surf está hoje |
|---|---|---|---|
| 0 | O runner rodou (`stub_ok`) | ~0 | smoke padrão |
| 1 | Um comando arbitrário passou | baixo | `oracle: <string>` |
| 2 | Testes existentes passaram | médio | `command:` em modos |
| 3 | Lint/type-check passou | baixo | idem |
| 4 | Propriedades amostradas valem (property tests) | médio | não formalizado |
| **5** | **Um teorema sobre o programa vale para todas as entradas** | **sub-segundo (reivindicado)** | **ausente — é o Bend** |

Três consequências:

1. **Zero mudança de schema.** O degrau 5 entra como
   `command: bend PROOF.bend` num modo YAML. O mesmo argumento do D3
   ("custom modes precisam de zero schema") vale aqui. O experimento E4
   custa uma tarde.
2. **A copy precisa dizer o degrau.** "Um oráculo mecânico prova que foi
   entregue" é verdade no degrau 0–2 num sentido fraco. Com Bend na
   escada, o site tem de distinguir "um comando saiu 0" de "uma lei foi
   provada" — senão o teste de honestidade (`test-site-honesty.sh`) tem de
   ser estendido para impedir que "provado" apareça onde só houve teste.
3. **O degrau 5 muda a economia do retry.** Um veredito de sub-segundo
   permite dezenas de tentativas baratas por tarefa. É precisamente o
   regime em que "99 % em modelos baratos" faz sentido: o modelo barato
   pode errar muito se o juiz é rápido e infalível.

## 3. Onde a convergência é forte, onde é fraca (honestamente)

**Forte — o alvo é código Bend.** Se o projeto orquestrado é Bend, o loop
é completo: `tow` (fronteira) escreve `LAWS.bend` = a intenção; `paddle`
(barato) escreve código + `PROOF.bend`; `bend` julga; o ledger assina o
recibo com o hash das leis. Aqui o llms.surf vira "o dispatcher com
recibos do loop de prova" — um produto nítido para uma comunidade de
21 mil estrelas que hoje não tem dispatcher nenhum.

**Fraca — o alvo é o resto do mundo.** 99 % dos repositórios que o
llms.surf orquestra são bash, Python, TS, Rust. As leis do Bend só falam
de código Bend. Para esses, Bend só serve como **camada de modelo**:
escreve-se o núcleo crítico (um codec, uma máquina de estados, uma
política) em Bend com leis, e o resto o chama ou espelha. Isso é o padrão
"kernel verificado + casca não verificada" — útil, mas o recibo diz "o
modelo obedece à lei", não "o sistema obedece". A copy tem de manter essa
distinção ou vira mentira.

**O que Bend não resolve:** a lei errada. A página mostra "you can't
win" bloqueando uma feature; num produto real, o bug migra para cima —
passa a ser "a lei não expressa a intenção". O llms.surf tem justamente a
peça que falta ao Bend aqui: o ledger + postmortems como memória de
*quais leis estavam erradas e por quê*. Incidente → lei corrigida é o
mesmo loop "incidents promote → regras" já descrito no PUBLIC-CUT.

## 4. Economia: a hipótese que vale a pesquisa

**H-Bend-1:** modelos baratos conseguem fechar provas em BendTT com taxa
útil, desde que a lei já exista e o checker devolva erro localizado em
sub-segundo. Se verdadeira, a divisão 1 %/99 % ganha uma forma precisa:
**leis são o 1 %, provas são o 99 %.** Escrever a lei exige entender a
intenção (fronteira); fechar a prova é busca guiada por um juiz rápido
(barato, muitas tentativas).

**H-Bend-2:** a taxa de fechamento por tier, o número de retries e o custo
por prova fechada são **mensuráveis pelo ledger sem instrumentação nova**
— cada tentativa é um run assinado com provider, custo e exit do oráculo.
O llms.surf é o instrumento natural para responder H-Bend-1, e a resposta
é um número *da árvore*, publicável sob a regra do go-live.

Se H-Bend-1 for falsa (modelos baratos não fecham provas), a conclusão
também é valiosa e publicável: "provas dependentes ainda são tarefa de
fronteira; Bend faz o veredito barato, não a autoria". O produto continua
de pé nos dois casos.

## 5. Ledger, Lineup e o recibo de teorema

- **Recibo de teorema.** Entrada de ledger = (commit, hash de
  `LAWS.bend`, exit de `bend PROOF.bend`, provider efetivo, custo,
  assinatura). É um recibo qualitativamente mais forte que "testes
  passaram": afirma que *uma propriedade universal* valia naquele commit.
  Nenhum campo novo; só um novo tipo de oráculo no mesmo formato.
- **Lineup.** Pontos só por atividade assinada — "lei contribuída" e
  "prova fechada" são atividades assinadas por construção. Um degrau novo
  na escada Haole → Grom → Local → Legend cabe sem mudar a regra.
- **Anti-fake.** "Fakes caught" já pontua. Uma prova é impossível de
  falsificar sem quebrar o checker; a superfície de fraude desloca-se
  para *leis vazias* (lei trivialmente verdadeira). Isso é um item de
  gauntlet: lei sem hipótese sobre a entrada, ou sem referência à função
  sob teste, não pontua.

## 6. Programa de pesquisa (experimentos com saída mensurável)

Ordem por custo crescente; cada um produz um número ou um "não".

| # | Experimento | Máquina | Saída |
|---|---|---|---|
| E1 | Instalar Bend 2; reproduzir o demo do jogo (lei `you_cant_win`, feature "wrap around", ver o checker bloquear) | Omarchy | funciona/não; tempo real do check |
| E2 | Spec S01 do passphrase-helper como leis: `decode(encode(i)) == i`, "troca simples é detectada", "gerador ∈ [0,7775]" | Omarchy | quais leis fecham; quantas linhas de prova; tempo |
| E3 | Reproduzir um benchmark do site (game of life) em 1 core / 16 cores / RTX 3090 | 3090 box | tabela própria vs. números do M4 Max |
| E4 | Modo YAML `paddle` + `command: bend PROOF.bend` — validar com `mode validate`, rodar 1 tarefa ponta a ponta com ledger | Omarchy | schema intacto? recibo gerado? |
| E5 | **O experimento central (H-Bend-1/2):** 10 tarefas Bend com leis dadas; despachar em `cheap`, `mid`, `expensive`; medir taxa de fechamento, retries, custo por prova via ledger | Omarchy | a tabela que decide o posicionamento |
| E6 | Lei sobre um núcleo do próprio llms.surf modelado em Bend (ex.: "cadeia de tier nunca colapsa provider vazio em 1" — o bug do commit `e82f008`) | Omarchy | a lei captura o incidente? |

E1–E4 cabem em duas tardes. E5 é a pesquisa de verdade e depende de E1
funcionar. E6 é o teste da "camada de modelo" (§3, caso fraco) num
incidente real da árvore.

## 7. Riscos e anti-hype

1. **Bend é jovem** por autodeclaração. Nada de Bend no caminho crítico
   do lançamento; tudo é modo opcional e pesquisa.
2. **Teoria afim.** BendTT é afim: recursos usados no máximo uma vez.
   Programas com compartilhamento livre podem ser difíceis de expressar;
   isso pode limitar quais núcleos se modelam. E2/E6 medem isso.
3. **Números do site não são seus.** Só entram na copy depois de E3.
4. **"Provado" na copy.** Estender o teste de honestidade: a palavra só
   pode aparecer atrelada a um recibo de degrau 5 na árvore.
5. **Licenças.** llms.surf é proprietário; a comunidade Bend espera
   abertura. Conflito real de distribuição (ver §8).
6. **Lei errada é o novo bug** (§3). O produto tem de tratar leis como
   código revisado, com postmortem quando uma lei errada bloqueou ou
   liberou algo — e isso o llms.surf já sabe fazer.
7. **Dependência de fornecedor único.** Se o Bend mudar sintaxe ou morrer,
   o modo morre; o dispatcher não. Mantê-lo como adaptador.

## 8. Posicionamento e distribuição

- **Pré-lançamento: nada muda.** A copy aprovada fica. Bend é v2.
- **Conteúdo pós-lançamento:** um post "A escada de oráculos" (§2) com a
  tabela do E5. Esse texto é o argumento do produto inteiro, com ou sem
  Bend; Bend é o degrau que torna a escada visível.
- **Canal:** a comunidade Bend é o público mais qualificado possível para
  "dispatcher com recibos": já aceita a premissa de que a IA precisa de um
  juiz mecânico. Mas é uma comunidade OSS e o llms.surf é proprietário.
  Saída consistente com D1: o **adaptador Bend** (pequeno: modo YAML +
  runner que chama `bend`) nasce OSS, como ímã, no mesmo modelo do
  bestmodel; o dispatcher segue proprietário. Decisão do dono.
- **Nome interno do degrau 5**, se virar alias: uma palavra de surf para
  "o que não quebra" — não decidir aqui; taste call do dono, com a mesma
  regra do D2 (alias na copy, id na árvore).

## 9. Decisões que ficam para o dono

1. Autorizar E1–E4 (duas tardes, ZCode) logo após o go-live — sim/não.
2. Adaptador Bend como OSS ímã (§8) — sim/não/depois.
3. Estender o teste de honestidade para a palavra "provado" antes de
   qualquer copy sobre Bend — recomendo sim, independente do resto.

## 10. Resumo para o ZCode

Nada a implementar antes do lançamento. Depois: E1 → E2 → E4 → E5, nesta
ordem, cada um com o número na árvore; E3 quando a 3090 estiver livre;
E6 por último. A única mudança de produto antes de Bend existir de fato é
a regra 4 da §7 (honestidade da palavra "provado").
