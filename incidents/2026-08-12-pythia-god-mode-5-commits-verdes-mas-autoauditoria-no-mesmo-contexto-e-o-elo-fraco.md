---
id: 2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco
titulo: PYTHIA (god mode v3.5, sessão vagai) fechou C0-C4 com produto real no ar — mas os 2 bugs da sessão foram pegos por ORÁCULO, não pela autoauditoria; validador mecânico de veredito funcionou; ledger vazio confirma o achado do ouroboros em 2ª ocorrência independente
data: 2026-08-12
recorrivel: sim
regra: nao — 5 regras candidatas para a v4 no corpo (3 convergem com as do ouroboros; 2 são novas)
status: aberto
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-08-12-pythia-enospc-no-meio-do-anel-sem-preflight-de-ambiente"
interage_com: "2026-08-12-disco-enche-ate-100-de-forma-recorrente-"
interage_com: "2026-07-26-spec-sem-clausula-anti-invencao-gera-num"
---

# PYTHIA — postmortem do god mode v3.5 (sessão vagai/job-search)

## Contexto

Segundo teste god mode da v3.5, sessão independente do ouroboros (outro
agente, outro alvo, mesmo dia). Modo `pythia` (`docs/modes/pythia.md` +
`specs/pythia-vagai-loop.md`, commit `33483c6`): frontier executa TODOS os
papéis — plan, build, autoauditoria, refino, checkpoint — SEM contexto fresco
por papel (diferença central para o ouroboros, que usava Task subagents
frescos para critic). Guardrail declarado no doc do modo: oráculos
determinísticos (teste/typecheck/build) continuam obrigatórios.

Alvo: empacotar o pipeline de caça a vagas (`~/aiJobSearch`) como SaaS
(`~/vagai`, repo privado `carl0sfelipe/vagai`) e evoluí-lo no automático até
o dono revisar checkpoints.

Resultado bruto: **C0-C4 em duas janelas (~1h de tarde + ~45min de noite)**,
produto no ar com engine + 19 testes verdes + CLI, e dogfood em produção:
pipeline real foi de 416 para 438 vagas, 16 vereditos de ranking aplicados
com 0 erros de contrato. Commits: `eb6d765` (C0+C1), `60531bf` (C2),
`e9b3521` (decisão de nome), `6fd9118` (C3+C4).

## O que funcionou (com evidência)

1. **Oráculos determinísticos pegaram os 2 únicos bugs da sessão** — nenhum
   foi pego pela autoauditoria em contexto quente:
   - `tsc --noEmit` pegou `types: ["bun-types"]` inválido nos 2 tsconfigs
     (pacote real é `@types/bun`, que o TS resolve como `bun`).
   - `bun test` pegou o monkeypatch de módulo ESM que não funcionava no
     teste de pipeline (binding de import é fixo; 15 pass / 1 fail). A
     correção virou design melhor: `AdapterInfo.search?` injetável.
2. **Validador mecânico na saída do juiz** (`rank import`): score fora de
   0-100, verdict fora do enum da rubrica, url fora do state e
   strengths/gaps ausentes são REJEITADOS por código, não por protocolo.
   Testado com 3 vereditos inválidos → 3 erros, 0 aplicados, state intacto
   (`packages/core/tests/rank.test.ts`). É a versão implementada da regra
   candidata 3 do ouroboros (`biggest_gap` falha-fechado) — existir como
   código de produto prova que é barata.
3. **Cláusula anti-invenção no contrato do juiz funcionou na prática**: os
   16 vereditos do dogfood foram dados só com metadados (título/empresa/
   local) e TODOS carregam o gap explícito "avaliação por metadados — ler
   posting antes de aplicar". Exemplo de honestidade sob incerteza: Ford
   Dearborn rebaixada a weak (30) por falta de autorização de trabalho US,
   em vez de score médio confabulado. Linhagem direta do incident
   "spec-sem-clausula-anti-invencao".
4. **Protocolo de escrita segura em state de produção**: antes do dogfood
   gravar no `seen_jobs.json` real (416 entradas), o executor verificou as
   chaves top-level (só `seen` — `saveState` teria descartado qualquer
   extra) e criou backup datado. Custo: 1 comando. Evitou a classe de
   perda do incident "migracao-zerou-catalogo-medusa".
5. **Decisão autônoma desbloqueou o produto**: o dono não respondeu a
   pergunta "API key própria vs BYO-key" entre sessões. O Pythia decidiu
   por juiz plugável via arquivo (nenhum provider amarrado), registrou a
   decisão no CHECKPOINTS.md e seguiu. A pergunta de billing continua
   aberta, mas deixou de bloquear — padrão saudável para god mode noturno.

## Contraste com o ouroboros (mesmo dia, sessões independentes)

| Dimensão | ouroboros | pythia |
|---|---|---|
| Critic | Contexto FRESCO por papel (subagent + profile) | Autoauditoria no MESMO contexto |
| Quem pegou os bugs | Critic fresco (3 rejeições empíricas graves) | Oráculos mecânicos (2 bugs); autoauditoria pegou 0 sozinha |
| Guarda na saída do judge | Protocolo (profile do critic) | MECANISMO (validador de contrato em código) |
| Ledger | Vazio (host-mode invisível) | Vazio (idem — 2ª ocorrência independente) |
| Checkpoint | Manuscrito pelo executor | Manuscrito pelo executor (idem) |
| Falha de ambiente | Sessão de terminais matou cadeia+vigia | ENOSPC no meio do anel (incident próprio) |

Leitura honesta: a autoauditoria quente do pythia é MAIS FRACA que o critic
fresco do ouroboros — nesta sessão ela só agregou valor quando tinha
CHECKLIST escrito antes (critérios de aceite da spec) e quando o objeto era
processo (backup antes de gravar), não código. Cegueira de autor em contexto
quente é real: os bugs de código passaram batido até o oráculo gritar.

## O que quebrou / ficou frágil

1. **Ledger vazio** — `rg -c pythia ledger/ledger.jsonl` → zero. Mesma causa
   raiz do ouroboros: host-mode não passa por `bin/oracfit`, então
   contabilidade de anéis/tetos/vereditos é manuscrita pelo próprio
   executor. Duas sessões independentes no mesmo dia = evidência forte.
2. **Granularidade de checkpoint derivou sob pressão**: C0+C1 saíram num
   commit só, C3+C4 idem. O doc do modo diz "ciclo sem commit revisável não
   conta"; nada mecânico impede fundir ciclos. Auditoria a posteriori fica
   mais grossa.
3. **ENOSPC no meio de batch de edits** (incident próprio, interage_com):
   disco a 357 MB fez um StrReplace falhar no MEIO de um batch de 5 — estado
   parcial silencioso se o executor não conferisse o resultado por chamada.
4. **Identidade git errada em TODOS os commits**: `mini@Mac-mini-de-mac.local`
   — commits não contam para a conta GitHub do dono e a autoria fica
   ambígua. Classe preflight, nunca checada pelo modo.
5. **Juiz míope por economia**: rankear 16 vagas só por metadados foi
   decisão de custo/tempo correta para triagem, mas o contrato do veredito
   não tem campo estruturado de nível de evidência — a honestidade ficou em
   texto livre no gap. Um `evidence_level: metadata|full_posting` no
   contrato tornaria o filtro mecânico ("não aplicar sem full_posting").

## Causa raiz

A mesma do ouroboros, confirmada em 2ª ocorrência independente: **host-mode
é invisível aos mecanismos da v3.5** — ledger, teto, preflight e
granularidade de anel degradam para protocolo. A novidade do pythia é a
contraprova positiva: onde a proteção FOI código (validador de contrato do
juiz, oráculos de teste/typecheck), ela funcionou sem depender de
disciplina.

## Regras candidatas para a v4

Convergentes com o ouroboros (reforço, não repetição):

1. **`bin/oracfit ring open|close` para host-mode** (= regra 1 do ouroboros;
   2ª sessão a precisar). `ring close` exige: commit hash + oracle_exit real
   + entrada no ledger. De quebra resolve a granularidade (sintoma 2): sem
   `ring close`, o ciclo não fecha — fundir ciclos vira impossível de
   esconder.
2. **Contrato de veredito falha-fechado como MECANISMO** (= regra 3 do
   ouroboros): o `rank import` do vagai é a implementação de referência —
   validação de range/enum/campos obrigatórios em código, estado intacto em
   caso de erro. Promover o padrão para o judge/critic do core.
3. **Preflight de ambiente no `ring open`** (nova forma da regra 4 do
   ouroboros): disco livre mínimo, identidade git resolvida, auth de remote
   viva. Ver incident irmão do ENOSPC.

Novas (evidência desta sessão):

4. **Critic fresco obrigatório para anéis de CÓDIGO em god mode**: a
   autoauditoria quente pode manter processo/documentação, mas veredito de
   código sem contexto fresco não fecha anel. Custo: 1 subagent por anel.
   Evidência: 0 bugs pegos pela autoauditoria vs 2 pelos oráculos aqui, e
   3 rejeições empíricas do critic fresco no ouroboros.
5. **`evidence_level` estruturado no contrato do juiz**: veredito declara
   mecanicamente sobre QUAL evidência foi dado (metadata | artefato parcial
   | artefato completo); consumidores podem filtrar por nível. Honestidade
   deixa de morar em texto livre.

## Evidência preservada

- Modo e spec: `docs/modes/pythia.md`, `specs/pythia-vagai-loop.md`
  (commit `33483c6`).
- Produto: `carl0sfelipe/vagai` privado — commits `eb6d765`, `60531bf`,
  `e9b3521`, `6fd9118`; `CHECKPOINTS.md` com autoauditoria por ciclo.
- Oráculo pegando bug: run de `bun test` com 15 pass / 1 fail (monkeypatch
  ESM) e correção em `packages/core/src/adapters.ts` (`search?` injetável).
- Validador do juiz: `packages/core/tests/rank.test.ts` (3 vereditos
  inválidos → 3 erros, 0 aplicados).
- Dogfood em produção: `~/aiJobSearch/job_scraper/seen_jobs.json` 416→438,
  backup `seen_jobs.backup-20260812-*.json`, 16 vereditos com gap de
  metadados explícito.
- Ledger sem entradas do modo: `ledger/ledger.jsonl`.

## O que este incident PROVA pra v4

1. Proteção como código funciona em god mode (validador de contrato,
   oráculos); proteção como protocolo depende de sorte e disciplina —
   mesma conclusão do ouroboros, por caminho independente.
2. Autoauditoria em contexto quente NÃO substitui critic fresco para
   código. Os dois god modes do dia, combinados, dão a receita da v4:
   executor quente + critic fresco + contratos falha-fechado + ledger de
   anel obrigatório.
3. God mode com decisão autônoma registrada em checkpoint destrava trabalho
   noturno sem sequestrar decisões do dono (billing segue aberto; produto
   andou).

## Pode acontecer de novo?

Sim — qualquer sessão host-mode continua fora do ledger até a regra 1
existir, e qualquer anel de código auditado só pelo próprio executor quente
repete o risco de cegueira de autor (aqui os oráculos seguraram; num alvo
sem suíte de testes, nada segura).
