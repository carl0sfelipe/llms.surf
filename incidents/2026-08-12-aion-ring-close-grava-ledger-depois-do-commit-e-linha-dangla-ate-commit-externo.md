---
id: 2026-08-12-aion-ring-close-grava-ledger-depois-do-commit-e-linha-dangla-ate-commit-externo
titulo: AION (god mode v3.5) ring.sh grava o evento close no ledger DEPOIS do commit de checkpoint — a linha danglou 27 min não-commitada na árvore e foi commitada por sessão externa; o mecanismo anti-"protocolo" nasceu com um buraco de transação
data: 2026-08-12
recorrivel: sim
regra: nao — regra candidata "close transacional com pós-condição de árvore limpa" (complementa a regra 1 do ouroboros/pythia, que pede o runner; esta pede a atomicidade dele)
status: aberto
interage_com: "2026-08-12-aion-god-mode-1-anel-com-mecanismo-real-mas-perpetuidade-morreu-com-a-sessao"
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
---

# ring.sh grava ledger depois do commit — linha órfã varrida por commit externo

## Sintoma

Sequência real do fechamento do RING-1 (branch `demo/neural-loop` do
relay-juggler), reconstruída por evidência:

1. `21:31:05` — commit `82c59a84` (build, pathspec explícito, feito pelo script).
2. `21:31:06` — commit `3f1ee2a9` (checkpoint: CHECKPOINTS.md, ledger,
   verdict, notes). **O ledger dentro deste commit tem SÓ a linha `open`**:
   `git show 3f1ee2a9:aion/ledger.jsonl | wc -l` → 1.
3. Só DEPOIS do commit o script appenda o evento `close` no
   `aion/ledger.jsonl` (ordem do código: bloco "Commit do checkpoint"
   precede o `append_ledger "$line"` do close em `aion/ring.sh`).
4. A linha do close ficou 27 min não-commitada na árvore de trabalho.
5. `21:58:18` — commit `a9cbf48e` ("data(aion): registrar close do RING-1 no
   ledger — APPROVED", 1 insertion) commitou a linha — **feito fora da
   sessão de agente que rodou o anel**: nenhum terminal daquela sessão
   estava ativo no horário (mais recente: 21:33, o despertador morto) e a
   autoria git é idêntica em todos os commits da máquina
   (`Carlos <carlos.felipe@hotmail.com.br>`), o que impede atribuir a
   origem — outra sessão de agente ou o dono à mão.

## Por que é um incident PRÓPRIO e não um detalhe do postmortem

1. **É falha de CONTRATO do mecanismo, não de ambiente nem de processo**: o
   `ring.sh` existe exatamente para que o estado do anel não dependa de
   disciplina — e a sua última operação viola a própria promessa, deixando
   o registro mais importante (o close com oracle_exit, veredito e commits)
   fora de qualquer commit. Um mecanismo com buraco de transação dá
   FALSA CONFIANÇA: pior que protocolo assumido, porque ninguém está
   vigiando o que "o script garante".
2. **Reencenou a lição da árvore compartilhada do ouroboros por outro
   caminho**: lá, `git add -A` de um agente varreu arquivos de outro; aqui,
   um arquivo órfão deixado pelo mecanismo foi commitado por sessão que não
   rodou o anel. Mesma classe (estado dangling em árvore compartilhada),
   causa nova (ordenação interna do runner, não pathspec largo).
3. **A auditoria do anel fica mentirosa por 27 min**: quem lesse o repo no
   intervalo veria checkpoint commitado dizendo "anel fechado" e ledger
   commitado dizendo "anel aberto". Para um modo cuja interface de revisão
   humana é exatamente esse par, a janela de inconsistência é o defeito.

## Causa

Ordenação escrita errada no próprio executor ao criar o mecanismo (frontier
escreveu o runner e não viu o buraco; o critic fresco revisou o BUILD do
anel, não o runner — o runner nunca passou por critic). Evidência: ordem
dos blocos em `~/relay-juggler/aion/ring.sh` (commit do checkpoint antes do
`append_ledger` do close). Não determinado por que a sessão externa
commitou a linha (mensagem de commit sugere intenção deliberada de
consertar o registro).

## Correção proposta (não aplicada — anel já fechado, postmortem primeiro)

No `ring.sh close`, inverter a ordem e fechar a transação:

1. montar a linha do close ANTES do commit de checkpoint;
2. appendar no ledger do workdir;
3. commitar checkpoint INCLUINDO a linha (`CHECKPOINTS.md` + ledger completo
   + verdict + notes);
4. pós-condição mecânica: `git status --porcelain -- aion/ CHECKPOINTS.md`
   vazio, senão exit 1 com o anel marcado inconsistente;
5. espelho no ledger do oracfit continua fora da transação (repo alheio),
   explicitamente rotulado de best-effort.

## Regra candidata para a v4

**Close de anel transacional com pós-condição de árvore limpa** — todo
runner de anel (a regra 1 do ouroboros/pythia, da qual o aion é piloto)
termina com verificação mecânica de que NADA do estado do modo ficou fora
do commit do anel. Custo: reordenar ~10 linhas + 1 checagem `git status
--porcelain`. Cobre também a variante "executor esqueceu arquivo do modo no
stage" que pathspec explícito sozinho não cobre.

## Evidência

- Ordem dos blocos: `~/relay-juggler/aion/ring.sh` (261 linhas; bloco
  "Commit do checkpoint" antes do append do close).
- Ledger no commit vs na árvore: `git show 3f1ee2a9:aion/ledger.jsonl | wc -l`
  → 1; `wc -l ~/relay-juggler/aion/ledger.jsonl` → 2.
- Janela e varredura: commits `3f1ee2a9` (21:31:06 -0300) e `a9cbf48e`
  (21:58:18 -0300, 1 file changed, 1 insertion em `aion/ledger.jsonl`).
- Ausência de terminal da sessão do anel no horário do commit externo:
  `ls -lt ~/.cursor/projects/Users-mini-relay-juggler/terminals/` (mais
  recente 21:33, `844673.txt`).
