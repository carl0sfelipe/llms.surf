---
name: The Lineup — llms-surf cloud tokens
about: Entre na fila do bilhão de tokens. Quem constrói o benchmark leva a maior fatia.
title: "lineup: <um apelido ou 'anônimo'>"
labels: waitlist
---

<!-- O que você está entrando: THE LINEUP — a fila de acesso antecipado aos
     llms-surf cloud tokens (créditos que rodam suas tasks de dev nos modelos
     mais econômicos por task, nas GPUs da casa, sem chave de API sua).
     Os tokens NÃO saíram ainda. Não existe preço, não existe data.
     Entrar custa esta issue; sair custa apagá-la. -->

## A oferta: 1.000.000.000 de tokens

Um bilhão de tokens do llms-surf cloud vai para a lineup, dividido por
quanto você remou. Ninguém compra lugar aqui — se ganha, e o arquivo que
prova isso está neste repo (`data/lineup.json`, auditável no git).

| tier | corte | peso | como se chega lá |
|---|---|---|---|
| **Haole** | 1 ponto | ×1 | você abriu esta issue |
| **Grom** | 5 pontos | ×5 | uma run assinada sua, ou um indicado que contribuiu |
| **Local** | 20 pontos | ×25 | várias runs assinadas, ou você reproduziu o número de outra pessoa |
| **The Legend** | 50 pontos | ×100 | pegou uma fraude, ou refez os números dos outros até eles baterem |

**O peso é fatia, não promessa de número fixo:** você leva
`1 bilhão × seu peso ÷ soma dos pesos de todo mundo`. Número fixo por pessoa
quebraria no dia em que aparecesse gente demais, então a casa não imprime um.
Sua fatia se move conforme a fila cresce, e cada recálculo é um commit legível.

## Sua entrada

- **Que trabalho você mandaria rodar no cloud:** <!-- obrigatório, uma frase -->
- **Adapter que você usa hoje:** <!-- opencode / claude-code / cursor / outro / nenhum -->
- **Volume esperado:** <!-- escolha um: <5 | 5–20 | 20–60 | 60+ dispatches/mês -->
- **referred by:** @handle <!-- opcional — só converte quando o indicado CONTRIBUI de verdade (run assinada, reprodução) -->

## Consentimento (transparente, e desmarcar é livre)

- [ ] **consent:** entendo que meu handle do GitHub aparece na fila pública
  do The Lineup (`data/lineup.json` neste repo, auditável no git) e que a
  minha contribuição técnica no bestmodel.run (runs assinadas, reproduções)
  vale pontos nessa fila. Desmarcar não me tira da fila — muda só a
  gamificação.

## Compromissos da casa (o que fazemos e não fazemos)

- **O bilhão é compromisso, não medida.** É o que a casa decidiu dar. Todo
  número de DESEMPENHO neste projeto continua medido ou declarado ausente —
  os dois nunca se misturam.
- Nenhum preço é anunciado antes de existir custo medido (throughput lido
  do ledger deste repo — número mecânico, não estimativa de marketing).
- Nenhuma data é prometida: os tokens saem quando a medição diz, não o
  calendário. Enquanto o cloud não existir, nada é creditado.
- **O tier sai só dos pontos.** A coluna "como se chega lá" descreve de onde
  os pontos costumam vir; a máquina não finge conferir o que não enxerga.
  Quando o export trouxer o detalhe por tipo de contribuição, ela passa a
  conferir — e a saída diz qual dos dois está valendo (`tier_basis`).
- A ordem da lista é a ordem do acesso: sem pulo de fila para ninguém.
- Quem está na lineup é avisado AQUI, por issue, antes de qualquer canal.
- Sair da lista = apagar esta issue. Um clique, sem perguntas.
