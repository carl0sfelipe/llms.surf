---
id: 2026-08-27-dogfooding-tres-despachos-no-mesmo-workdir-e-veredito-lido-grepa-crud
titulo: três dispatchs do mesmo spec sobrepuseram-se no mesmo workdir e o operador leu veredito errado por grep cru no events.jsonl
data: 2026-08-27
recorrivel: sim
regra: 53
status: promovido
repo: eaas-bitcoin (workdir) + operador humano-agente (beelink)
---

# Dogfooding d0gfood-03: sobreposição de 3 despachos no mesmo workdir + veredito lido com grep

Contexto: madrugada 26→27/08, pipeline novo (endpoint local ornith-1.5-35b em vast.ai via
llama-server :8020, runner opencode, spec de tradução EN do relatório de mercado da
eaas-bitcoin). Tudo funcionava no despacho nº1 e nº2 (pass attempt-1). O nº3 virou novela.

## Sintoma

1. **05:55:35** — despacho `dogfood-03` (spec fraca) inicia. 5 attempts, oráculo dá exit 1 em
   todas (06:00, 06:03, 06:05). Run **fail às 06:12:01**.
2. **Enquanto isso**, sem checar se o anterior tinha terminado, o operador lança **06:05:16**
   o `dogfood-03c` (spec hardened). **07 minutos de sobreposição real** com o despacho
   anterior — dois agentes opencode escrevendo o MESMO arquivo
   `docs/en/relatorio-inteligencia-mercado.md`.
3. **06:10:54** — terceiro (`dogfood-03d`) lançado também, morto logo depois (killed, SEM-FINISH).
4. **06:0x** — operador verifica artefato: algumas âncoras presentes, outras sumidas;
   cabeçalho inventado ("Prepared by: BMAD (Board of Modular Autonomous Directors)",
   data fictícia de agosto/2025) apareceu e sumiu entre leituras.
5. **O golpe final de confusão:** para saber o resultado, o operador rodou
   `grep '"run_finished"' events.jsonl | tail -1` e leu `status: pass`.
   Era a linha do **dogfood-02** (que tinha passado às 05:33). O último run_finished REAL
   da fila era fail. Meia hora perdida em diagnósticos contra um estado que não existia.

Estado final: as 3 traduções EN do dia (dogfood-01d, dogfood-02 verdes; relatório WIP)
**sumiram do worktree** durante as corridas — nenhum commit intermediário existia.
Specs sobreviveram porque estavam separadas em `specs/`.

## Causa raiz (três erros empilhados)

### A — Single-flight ausente no `run`

Nada impede `bin/llms-surf run normal <spec> <task> --workdir W` duas vezes simultâneas no
mesmo W. Dois agentes opencode com alvo de escrita igual não têm nem lock de arquivo nem
aviso. A sobreposição não foi hipótese: timestamps do ledger provam (05:55–06:12 ∩ 06:05–06:18).

### B — Veredito consumido por grep de texto, não por interface

O ledger é jsonl append-only (correto! isso salvou a verdade). Mas não há comando
canônico de STATUS — o operador fez grep manual e pegou a última linha **da tabela toda**,
não a do run dele. `tail -1` sobre linhas filtradas por tipo ≠ último estado do MEU run.

### C — Artefato avaliado no meio de reescritas multi-turn

Entre attempt N e N+1, ou entre turnos de agente dentro da mesma attempt, o arquivo-alvo
passa por estados transitórios (agente corta/seção reescreve). Quem julga é o oráculo na
janela certa; quem INVESTIGOU depois foi eu, fora dela — e vi "regressão de invariáveis"
que era só estado transitório gravado por outro run ainda vivo. Sem snapshot imutável do
conteúdo aprovado (ground-truth guarda só excerto de 11–21 linhas), auditoria pós-hoc vira
arqueologia.

## O que já funcionou e merece ser dito

- **Ledger append-only**: reconstruí a verdade inteira DEPOIS do caos usando só os eventos,
  parseando por run_id. O registro nunca mentiu.
- **check-spec + gauntlet**: a spec hardened (greps negativos de metadado inventado +
  âncora de tabela) passou a reprovar o que a fraca aceitava — evolução da defesa funcionou
  no primeiro uso.
- **ADR-0002** (reler disco no fechamento) cobre falso-fail de fechamento; o gap aqui é o
  falso-pass **lido pelo operador fora da janela correta**, classe diferente.

## Mecanismos propostos (pendentes de implementação)

1. **Single-flight por workdir**: `bin/llms-surf run` adquire `flock` exclusivo em
   `$ORACFIT_WORKDIR/.dispatch/.lock` antes de classify; segunda instância recusa com
   mensagem apontando o PID dono. Regra nova com código atrás — sem isso é dívida.
2. **`llms-surf status --task NAME`**: emitir JSON canônico `{run_id, status, attempts,
   last_oracle_exit}` SOMENTE do run mais recente com aquele task-name. Proíbe na prática o
   grep cru que gerou este incidente (prova real do custo: 30 min de diagnóstico errado).
3. **Imprint de integridade no green**: quando o oracula passa, gravar `sha256` de cada
   arquivo tocado; ao fechar o run, recomparar — divergiu ⇒ `artifact_regressed` no evento
   final em vez de pass silencioso.
4. *(bônus barato)* runner opencode recusa começar se `pgrep -f "opencode run"` já tiver
   processo com o mesmo base-path de workdir na cmdline.

## Lição para mim-mesmo (processo humano-agente)

Antes de relançar qualquer dispatch: `pgrep` dos runners vivos + conferir o ÚLTIMO
evento do run anterior por run_id, não por tail global. Um `sleep 10 && pgrep` custaria
zero; custou uma noite de sinais cruzados.
