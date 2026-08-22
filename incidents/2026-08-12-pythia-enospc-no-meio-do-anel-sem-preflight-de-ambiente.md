---
id: 2026-08-12-pythia-enospc-no-meio-do-anel-sem-preflight-de-ambiente
titulo: ENOSPC estourou no MEIO de um batch de 5 edits durante anel god mode (3ª ocorrência de disco cheio em 24h) — 1 edit falhou e 4 passaram; god mode não tem preflight de ambiente e falha parcial de batch é silenciosa se ninguém confere por chamada
data: 2026-08-12
recorrivel: sim
regra: nao — regra candidata "preflight no ring open" (complementa a regra 51, que trata a causa do disco, não a exposição do anel)
status: aberto
interage_com: "2026-08-12-disco-enche-ate-100-de-forma-recorrente-"
interage_com: "2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco"
---

# ENOSPC no meio do anel — god mode sem preflight de ambiente

## Sintoma

Sessão god mode PYTHIA (~21:30, anel C3 do vagai): batch de 5 operações de
escrita (4 edits + 1 arquivo novo) → a 3ª falhou com
`Error: No space left on device`; as outras 4 passaram. `df` na hora:
**357 MB livres** em 228 GB (`/System/Volumes/Data` a 100%).

Terceira ocorrência de disco no teto em ~24h (ver incident do disco
recorrente: 2026-08-11 com destruição de catálogo Medusa; 2026-08-12 ~14:40
com commits falhando em 10 agentes paralelos; esta às ~21:30).

## Por que é um incident PRÓPRIO e não só mais uma ocorrência do disco

O incident do disco (regra 51) trata a CAUSA (baseline alto + rajadas de
agentes). Este trata a EXPOSIÇÃO específica do god mode:

1. **Falha parcial de batch é silenciosa por construção**: 4 de 5 escritas
   aplicadas deixa a árvore num estado que nenhum edit individual descreve.
   Aqui o executor conferiu o resultado POR CHAMADA, viu o erro isolado,
   liberou espaço e reaplicou só o que faltou — mas isso foi protocolo.
   Um executor que confere só o "fim do batch" seguiria com um CLI cuja
   ajuda não batia com os comandos reais (o edit perdido era o texto de
   usage do `vagai rank`).
2. **O anel abriu sem NENHUMA checagem de ambiente**: 357 MB livres já era
   condição de falha iminente ANTES do batch — detectável por um `df` de
   1 linha no início do ciclo. O modo (docs/modes/pythia.md) define plan →
   build → self-audit → checkpoint e não pede preflight nenhum.
3. **Commit/push também estavam em risco**: com o disco no teto, o próprio
   `git commit` do checkpoint (a ÚNICA interface de revisão humana do god
   mode) teria falhado — o anel perderia exatamente a parte que o torna
   auditável.

## Mitigação aplicada na hora

Liberados ~5.6 GB apagando SÓ caches re-baixáveis (uv 1.4G, npm 1.6G,
bun 282M, pnpm 207M, dotslash 365M, pip 21M) — nada de estado de produção,
lição direta do incident do Medusa. Não tocados por serem dados do dono:
`~/.ollama` (11 GB), `~/Downloads` (6.9 GB). Anel retomado e fechado com
oráculos verdes.

## Regra candidata para a v4

**Preflight no `ring open` do host-mode** (encaixa na regra candidata 1 do
postmortem do ouroboros — o runner de anel é o lugar natural):

- disco livre >= limiar (proposta: 5 GB ou 2x o maior artefato esperado);
- identidade git resolvida (user.name/email não-default — os commits desta
  sessão saíram como `mini@Mac-mini-de-mac.local`, invisíveis para a conta
  GitHub do dono);
- auth do remote viva (`gh auth status` / ssh);
- falha de preflight = anel NÃO abre, com causa impressa.

Custo: 3 comandos de 1 linha. Cobre os sintomas 2 e 3 mecanicamente; o
sintoma 1 (falha parcial de batch) fica mitigado porque o anel nunca abre
já condenado — e a regra "conferir resultado por chamada em batch de
escrita" merece virar linha no doc dos modos god.

## Evidência

- Terminal da sessão: `df` mostrando 357 MB livres e, após limpeza, 6.0 GB
  (`/dev/disk3s5 228Gi 186Gi 6.0Gi 97%`).
- Erro isolado no meio do batch: retorno `Error: No space left on device`
  na 3ª de 5 chamadas de escrita (edit do usage do CLI do vagai).
- Reaplicação pós-limpeza e anel fechado: commit `6fd9118` do vagai com
  19 testes verdes.
- Levantamento do que foi limpo vs preservado: saída de `du -sh` das duas
  rodadas de inspeção na sessão.
