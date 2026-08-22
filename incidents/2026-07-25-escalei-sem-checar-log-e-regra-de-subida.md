---
id: 2026-07-25-escalei-sem-checar-log-e-regra-de-subida
titulo: Escalei sem checar log; regra de subida não cobre silêncio sem erro
data: 2026-07-25
recorrivel: sim
regra: 22
status: promovido
---

# Escalei sem checar log; regra de subida não cobre silêncio sem erro

## Sintoma

Dispatch de refinamento para `deepseek-v4-flash-free` estourou o teto de 500s.
Eu troquei de modelo (escalei para Sonnet) **sem abrir o log** e segui em frente.
O usuário perguntou "se falhou, qual regra manda fazer o quê" — e a resposta é
que eu havia quebrado três das minhas próprias regras.

## Causa

**Regras violadas:**

- **Regra 9** — "Rate limit ≠ incapacidade. Cheque logs **antes** de escalar." Não checei.
- **Regra de subida** (seção MODELOS) — "free falhou com erro de lógica → Sonnet;
  free falhou com 429 → esperar, retry". Eu não determinei qual dos dois era, então
  a escolha de escalar foi arbitrária, não fundamentada.
- **Regra 16** — falha que pode repetir vira incidente. Não registrei.
- **Regra 15** — "silêncio >60s = investigue, não espere". Deixei correr 500s.

**E a regra de subida tem um furo.** Ao checar o log (108 bytes) depois:

```
▶ tentando: deepseek-v4-flash-free
⏱️  TIMEOUT: comando excedeu 500s — árvore de processos morta.
```

Zero output, zero erro de provider, zero tool call. **Não é 429** (a regra 18
inspeciona stderr e nada casou) **nem erro de lógica** (não produziu nada para
estar errado). É um **terceiro modo**: silêncio sem erro — o mesmo padrão do
incidente fundador de 52min e do id fantasma do mistral.

A regra de subida oferece dois caminhos para três modos de falha. Sem o terceiro,
a decisão vira chute — foi o que eu fiz.

## Correção aplicada

Nenhuma no código. A correção é de regra: a árvore de decisão precisa do terceiro
ramo, e a checagem do log precisa ser **pré-requisito** da escalada, não opcional.

## Pode acontecer de novo?

**Sim.** Silêncio sem erro é o modo de falha mais comum deste ambiente (aconteceu
4x hoje: dispatch de 52min, mistral fantasma, qwen, e este). Sem ramo próprio na
regra de subida, todo agente vai continuar chutando entre "espera" e "escala".
