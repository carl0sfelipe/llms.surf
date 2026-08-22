---
id: 2026-07-25-captura-de-resultado-mentiu-3x
titulo: Captura de resultado mentiu 3x: $? após $(), 2>&1 e | tail
data: 2026-07-25
recorrivel: sim
regra: 24
interage_com: 18 (a 18 manda inspecionar stderr; esta manda NÃO fundir stderr com stdout — complementares, mas fáceis de confundir: inspecionar != capturar como resposta); 15 (o "| tail esconde progresso" explica parte do silêncio que a 15 manda investigar); 20 (medição sem proveniência vs medição mal lida). RISCO: item (b) pode ser lido como "ignore stderr", o oposto da 18.
status: promovido
---

# Captura de resultado mentiu 3x: $? após $(), 2>&1 e | tail

## Sintoma

Três formas diferentes de ler o resultado errado, cada uma me fazendo reportar
fato falso ao usuário:

1. **`$?` depois de `$(...)` ou pipe** — 3 ocorrências: critério F1 do PRD
   (`grep -c && echo`), teste F5.2 (`echo "$(dirname ...) exit=$?"` deu 0 para
   todos os 5 runners), e o exit do audit (reportei 0, o real era 1).
2. **`2>&1` ao capturar output de modelo** — o aviso legítimo que o runner escreve
   em stderr ("modelo auxiliar sem saldo") entrou **como se fosse a resposta**,
   dando 0/5 num modelo que acertava 5/5 e gravando `accuracy 0.0` no registry.
3. **`| tail -N`** — buffer só libera no fim, então trabalho em curso parece
   travamento. Foi parte do que fez o usuário perguntar "travou?".

## Causa

Substituição de comando reseta `$?`; `2>&1` funde canais com semânticas
diferentes (resposta vs diagnóstico); pipe com `tail` retém saída.

Todas são armadilhas conhecidas de shell — o defeito é não ter checklist ao
**medir**, e medição errada é pior que ausência de medição, porque vira dado.

## Correção aplicada

Nenhuma automática (é disciplina de escrita). Documentado no HANDOFF, seção de
armadilhas do macOS. Vira regra para virar hábito.

## Pode acontecer de novo?

**Sim** — as três apareceram múltiplas vezes na mesma sessão, mesmo depois de eu
ter consertado a primeira.
