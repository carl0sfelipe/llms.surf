---
id: 2026-08-12-editar-script-em-execucao-desloca-bytes-exit-127
titulo: "Editar vision-gate-slices.sh enquanto um run o executava fez o bash parsear lixo — 'a: command not found', exit 127, attempt queimado"
data: 2026-08-12
recorrivel: sim
regra: 48
status: promovido
interage_com: "2026-08-12-biggest-gap-heuristic-pega-boilerplate-em-vez-do-gap-real"
interage_com: "regra 13 (reforca: edicao separada de execucao) e regra 42 (mesma familia: dano aparece longe da causa); nao supera nenhuma"
---

# Editar script em execução desloca bytes — exit 127

## Sintoma

Run 177DA27B (content_factory, <host-local>), vision_gate attempt 2:

```
<home-do-dono>/oracfit/bin/vision-gate-slices.sh: line 201: a: command not found
STAGE COMMAND FAILED: role=vision_gate attempt=2 exit=127
```

O arquivo em disco estava íntegro (`bash -n` OK). A linha 201 não continha
nenhum comando `a`.

## Causa raiz

Bash lê scripts do disco **preguiçosamente**, em blocos, conforme executa.
Editei `vision-gate-slices.sh` no lugar (StrReplace = write in-place, mesmo
inode) DUAS vezes enquanto o run em voo o executava — o offset de leitura do
processo apontou para o meio de outra linha após a edição e o parser leu
fragmento de token como comando. Attempt queimado; o gauntlet consumiu um
loop-back por causa disso.

## Proteção

Ao corrigir script de `bin/` com run em voo que o executa:

1. **Nunca** editar o arquivo no lugar. Escrever em temp e `mv` por cima —
   rename é atômico, o processo em voo mantém o inode antigo (conteúdo velho
   e consistente) e só a PRÓXIMA invocação lê o novo.
2. Alternativa: esperar o stage atual terminar (processos `vision-gate-slices`
   somem do `ps`) antes de editar.

O dano é limitado por design: o stage falho vira loop-back, não corrompe
artefato. Mas queima orçamento de loop (aqui: 1 de 4).

## Custo

~7 min de ciclo export→render + 1 attempt de vision_gate + 1 loop global.

## Segunda ocorrência (mesma noite, ~01:32) — o run inteiro

Editei também `dispatch-stages.sh` às ~01:00 (echo do false-green guard,
commit 34a707d) com o MESMO run 177DA27B em voo. O bash do dispatcher chegou
àquela região do arquivo ~30 min depois e parseou lixo:

```
dispatch-stages.sh: line 465: continue: only meaningful in a `for' loop
dispatch-stages.sh: line 466: syntax error near unexpected token `fi'
status: promovido
```

Run inteiro morto por infraestrutura — o conteúdo estava convergindo (retry
de fatia de-flakou 2 confabulações na última passada de vision). Agravante:
escrevi este incidente ANTES do segundo crash e não auditei quais outros
scripts o run em voo ainda ia reler. A regra cobre o conjunto: **qualquer**
script bash que um run vivo ainda vai executar (dispatch-stages.sh, libs
sourced tardiamente, scripts de bin/ chamados por stage) só pode ser trocado
por temp + `mv`.
