# Jornada 1h — do estranho ao viciado (sem chave de API)

> Ordem de trabalho do go-live, não produto (D8). O relógio começa no primeiro
> `git clone` de uma pessoa que nunca ouviu falar do llms.surf. Cada passo
> tem prova mecânica — se um passo só "deveria funcionar", ele não está
> nesta jornada.

## Minuto 0–2 — a promessa (D1: o gate zero)

```
git clone https://github.com/carl0sfelipe/llms.surf.git
cd llms.surf
export ORACFIT_ROOT="$PWD" DISPATCH_RUNNER="$PWD/adapters/stub/runner.sh"
bin/llms-surf start
bin/llms-surf gui
```

O `start` despacha `specs/oracfit-smoke-normal.md` com o stub runner: o laço
inteiro (spec → runner → artefato no disco → oráculo lendo o disco) fecha
verde em segundos, sem rede, sem chave, sem modelo. O `gui` abre o painel
sobre o mesmo run. Prova: `bin/test-oracfit-tldr.sh` (os 3 comandos, os 2
testes, verde).

**Por que o stub e não um modelo de verdade:** a promessa dos 2 minutos é
sobre o CAMINHO, não sobre inteligência. Quem quer ver modelo de graça
trabalhando pula para o minuto 20 com a mesma configuração.

## Minuto 2–5 — o wizard (a TUI é a home)

`bin/llms-surf` sem argumentos abre o wizard. O menu mostra o trio de surf
(D2/D7): **paddle** (a onda normal — modelo barato suando), **tow** (o jet
ski que reboca você pra onda que você não remaria — unlock caro → plano
médio → execução barata), **surfcheck** (juízo visual de tela). Os 17 god
modes existem, ficam no CLI, não estragam a home de ninguém.

O wizard cobra três respostas (spec, task, adapter), mostra o orçamento do
dia ANTES de despachar, e o resultado sai com o oráculo verde ou vermelho —
nunca com "acho que funcionou".

## Minuto 5–20 — a primeira onda de verdade

Uma task própria (issue do próprio repo, um script quebrado, um texto pra
revisar). A pessoa escreve a spec com `## Oráculo` — comando cru, sem crase
(regra 46) —, escolhe paddle, e troca o stub por um adapter real
(`source adapters/opencode/env.sh` ou o que ela já roda). O modelo gratis
sua; o oráculo decide; a diferença entre "o modelo disse que fez" e "o disco
prova que ficou pronto" é o que ela conta pros amigos.

## Minuto 20–40 — o próprio modo (o ouro)

`oracfit mode init meu_modo` → edita o YAML do subconjunto (ficha:
`CUSTOM-MODE-CARD.md`) → `oracfit mode validate` + `oracfit mode lint` (o
MESMO loader que o run usa — o que valida é o que roda) → `oracfit run
meu_modo spec task`. O lint reprovando claim sem mecanismo é feature: é o
pedágio que impede o modo de mentir a própria classe de proteção (lição
aion/demiurgo, medida na primeira versão dos exemplos da ficha).

## Minuto 40–60 — postar a onda (o vício)

`oracfit mode share meu_modo` imprime o YAML com o cabeçalho do post. A
pessoa cola na issue **"share your break"** (template pronto). Privacidade é
localização (D5): nada saiu da máquina dela por magia — público é só o que
ela colou. Quem chega depois instala com `oracfit mode add <arquivo.yaml>` e
roda o modo de outra pessoa no mesmo loader auditado.

O gancho da segunda sessão: a thread "share your break" — ler o modo dos
outros é tão barato quanto postar o seu, e cada YAML postado é um case de
uso do dispatcher que não tivemos que escrever.

## O que esta jornada NÃO promete

- Nenhum modelo hospedado, nenhum token à venda, nenhuma fila com preço (D6).
- Nenhuma data. Os 60 minutos são do estranho disposto, não do calendário.
- Se um passo quebrar, é incidente (`bin/incident.sh new`) — a jornada é
  especificação, não marketing.
