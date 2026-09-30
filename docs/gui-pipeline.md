# Pipeline da GUI — como nasce um passo fácil de usar

Um passo da tela "Passo a passo" não começa no HTML. Ele nasce de um
contrato, ganha um oráculo que falha, e só então alguém implementa.

## Os cinco passos

1. **Contrato** em `docs/stories/`. O JSON do passo (ids, `state`,
   `action.kind`, frases) e as frases em português simples, **≤140
   caracteres, sem jargão**. Se o dono não entende a frase no celular,
   o contrato está errado — não a implementação.
2. **Oráculo** em `tests/test-gui-*.sh`. Ele descreve o comportamento
   com o servidor de verdade. Enquanto o oráculo falha, o trabalho
   ainda não acabou.
3. **Implementação** delegada (outro modelo, outro checkout). Não
   reescrever o contrato no meio do caminho.
4. **Revisão Opus** com três evidências: screenshot no desktop, outra
   em **390px**, e a mesma tela no modo **Simplificar**. Sem as três,
   não é revisão.
5. **PR**. Só então o passo existe para o dono.

## Regra do agente

Todo relatório de agente que pede algo ao dono roda `oracfit acao add`.
Sem isso o pedido some no chat e a GUI não tem o que mostrar.

```
oracfit acao add <id> --title "uma linha" --plain "o que fazer, ≤140" \
  [--href URL] [--command "comando"] [--step "texto"]… \
  [--artifact P] [--context P]… [--prioridade alta|normal] [--decisao] \
  [--source "quem pediu"] [--blocks "o que destrava"]
```

O id casa `^[a-z0-9][a-z0-9-]{0,63}$`. Title vazio ou plain longo
recusam sem gravar. A GUI mostra a ação de prioridade alta primeiro,
depois a mais antiga; o dono marca "Já fiz" ou "Me lembre amanhã".

Cartão que manda abrir algo tem **link direto** (deep link da tela
exata). Se o agente gerou um arquivo, passa `--artifact` e `--context`
para a GUI mostrar se o script é da vez ou se ficou velho.
