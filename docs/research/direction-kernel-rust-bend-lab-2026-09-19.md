# Direção — kernel do llms.surf "à maneira Bend" em linguagem estabelecida + lab Bend-first

Autor: Fable, 2026-09-19. Complementa `bend2-convergence-2026-09-19.md`.
Pedido do dono: apostar em Bend 2 com segurança — reconstruir o llms.surf
sobre pilares em linguagem performática e estabelecida, pensando à maneira
Bend, e em paralelo uma versão Bend-first como lab; 2.0 só se o lab se
mostrar mais eficaz e seguro. Direção, não implementação.

## D1 — Não reescrever o produto; extrair o kernel (strangler)

O llms.surf que lança é bash/Python com 107 postmortems embutidos em
regras. Reescrever isso é jogar fora o ativo. O que se reconstrói é o
**kernel puro** — as funções onde um erro é um incidente — atrás da mesma
CLI, um pilar por vez, com o shell atual chamando o novo binário. Os
adaptadores (opencode, Claude Code, Cursor, zcode, stub…) são cola e
ficam onde estão.

## D2 — Os pilares (o que é kernel, com a lei de cada um)

| Pilar | Função pura | Lei-exemplo (já existe um incidente para cada) |
|---|---|---|
| P1 Política de despacho | `classify → mode → cadeia de tiers → fallback` | cadeia nunca colapsa provider vazio em 1 (`e82f008`); free path nunca alcança provider pago (gate de 13 checks) |
| P2 Veredito do oráculo | `(exit, artefatos, gauntlet) → verdict` | nada vira `shipped` sem exit 0 **e** artefato no disco; veredito é determinístico |
| P3 Ledger | append-only, assinado, encadeado | todo run tem entrada assinada; nenhuma entrada é reescrita; hash chain fecha |
| P4 Schema de modo | parse/validate/lint de YAML v1 | `parse(render(m)) == m`; modo inválido nunca executa |

Fora do kernel: TUI/painel, adaptadores, site, incidents. Se não tem lei,
não é pilar.

## D3 — Linguagem: Rust, pelo motivo certo

Rust não é escolha de moda aqui: **o sistema de ownership do Rust é
afim, e a BendTT é uma teoria de tipos afim.** Kernel escrito em Rust com
disciplina Bend — funções puras, dados imutáveis, sem estado
compartilhado, paralelismo por divisão de dados (rayon) — porta quase
1:1 para Bend. É isso que torna a aposta segura: o custo do port fica
baixo *por construção*, não por promessa.

Python fica onde já está (loader de modos) até P4 ser extraído; nada de
terceira linguagem no kernel.

## D4 — "À maneira Bend" em ferramentas de hoje: o arquivo de leis

`LAWS.bend` é "AGENTS.md com prova". A versão estabelecida é um diretório
`laws/` onde **cada lei é um nome + um mecanismo que a checa**, e o CI
falha se uma lei não tiver mecanismo:

| Degrau | Mecanismo em Rust | Quando usar |
|---|---|---|
| Tipo | newtypes, enums exaustivos, estados como tipos (typestate) | invariantes estruturais: "provider vazio não é representável" |
| Propriedade | `proptest` (leis como quantificação universal amostrada) | roundtrips, monotonicidade, "nunca X" |
| Modelo | `kani` (model checking limitado) sobre P1/P2 | as leis que já custaram incidente |
| Prova | `verus`/`creusot` — **só** se um pilar justificar | não antes do lab Bend responder E5 |

Cada lei carrega o id do incidente que a motivou. "Incidents promote →
regras" vira "incidents promote → **laws**". Isso já é o loop Bend, sem
Bend.

## D5 — O lab Bend-first: mesma lei, mesmo vetor, outra implementação

O lab não é "outro llms.surf". É **o mesmo kernel, as mesmas leis
(`LAWS.bend` espelhando `laws/`), os mesmos vetores de conformidade**, em
Bend. O ativo compartilhado é a spec (leis + vetores), não o código —
é o que impede virar dois produtos.

Ritmo: P1 primeiro nos dois (é a lei com incidente mais recente); depois
P2. P3 (assinatura) por último no Bend — cripto em linguagem jovem é o
lugar de não confiar. Sincronia semanal: um vetor novo em Rust é um vetor
novo no Bend no mesmo dia, ou é dívida declarada.

## D6 — Gate do 2.0: precondições, não calendário

O lab vira 2.0 quando **todas** valerem, medidas na árvore:

1. Passa 100 % dos vetores compartilhados dos quatro pilares.
2. Toda lei de `laws/` tem equivalente em `LAWS.bend` **checado** (não
   comentário).
3. Desempenho ≥ Rust na carga de despacho real (ledger de 30 dias como
   replay), nas máquinas do dono, não no M4 Max de ninguém.
4. Bend com release versionado e N meses sem quebra de sintaxe que
   exigisse reescrever prova (N a fixar quando existir histórico).
5. E5 da pesquisa respondido: a taxa de fechamento de prova por tier é
   conhecida; o custo por prova está no ledger.
6. Zero incidente causado pelo Bend no lab por um ciclo inteiro de
   Lineup.

Se qualquer uma falhar, o Rust segue sendo o produto e o lab segue sendo
lab. Não há perda: as leis já pagaram por si no Rust.

## D7 — Ordem e tamanho

| # | Item | Tamanho | Quem |
|---|---|---|---|
| 0 | Lançar o llms.surf como está | — | dono |
| 1 | `laws/` com as leis dos incidentes existentes, mecanismo `proptest` sobre o código atual onde couber; CI falha sem mecanismo | story | ZCode |
| 2 | P1 em Rust atrás da CLI atual, leis + vetores, `kani` na cadeia de tiers | epic pequeno | ZCode |
| 3 | E1/E2 do Bend (instalar, leis do S01 do passphrase-helper) — prova de que o checker é usável | duas tardes | ZCode |
| 4 | P1 em Bend contra os mesmos vetores | story | ZCode |
| 5 | P2, depois P4, depois P3 — sempre Rust primeiro, Bend em seguida | epics pequenos | ZCode |
| 6 | E5 (taxa de fechamento por tier) quando P1 Bend existir | pesquisa | ZCode + ledger |

**Rejeitado explicitamente:** reescrever antes do lançamento; kernel em
Bend no caminho crítico; provas formais em Rust antes do lab responder;
adaptadores ou TUI em Rust "já que estamos aqui".

## Riscos desta direção

- Duas implementações dobram manutenção — mitigado só pelo D5 (spec como
  ativo único). Se a sincronia semanal falhar dois ciclos, congelar o lab.
- Rust afim ≠ Bend afim em detalhes (empréstimos, lifetimes não existem em
  Bend). O port "quase 1:1" é hipótese; P1 mede.
- `kani`/`proptest` provam menos que BendTT; a copy do produto continua
  dizendo "degrau" (escada de oráculos), nunca "provado" sem recibo.
