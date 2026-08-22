---
id: 2026-08-13-run-id-de-ring-colide-entre-alvos-no-mes
titulo: run id de ring colide entre alvos no mesmo minuto e mistura o ledger central
data: 2026-08-13
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/oracfit-ring.sh (run id com segundos + slug do alvo; campo "target" em todo evento ring-v1), pinado por tests/test-ring-runner.sh T17
status: corrigido — working tree, aguardando commit
interage_com: "2026-08-13-executor-duplicado-no-mesmo-worktree-ove.md (mesma noite coordenada; lá a colisão foi de ALVO, aqui de RUN ID — o sleep de espaçamento de init da coordenação protegia exatamente esta granularidade de minuto e não bastou)"
---

# run id de ring colide entre alvos no mesmo minuto e mistura o ledger central

## Sintoma

Dois `oracfit ring init` no MESMO minuto da noite de 2026-08-13 (03:47 local),
em alvos DIFERENTES (worktrees do CanIRunIt e do ai-usage-hub), geraram o
MESMO run id `ananke-20260813-0347`. O ledger central agora agrupa 24 linhas
de dois runs distintos sob um id só — anéis RING-1..RING-4 DUPLICADOS, com as
hipóteses das duas frentes intercaladas:

```
$ rg '"event": "open"' ledger/ledger.jsonl | rg ananke-20260813-0347   # ts / ring / hipótese
06:49:06 RING-1 'B2: run_claim table + UNVERIFIED badge …'          ← CanIRunIt
06:49:41 RING-1 'AIH1-01: testes locais-puros de local_tracker …'   ← ai-usage-hub
06:55:09 RING-2 'B3: claim_vote migration …'                        ← CanIRunIt
06:56:49 RING-2 'Residual local-puro das AIH1-02/08 …'              ← ai-usage-hub
07:00:30 RING-3 'B4: pure builder …'  /  07:03:00 RING-3 'Finding YELLOW …'
07:03:48 RING-4 'C1: markdown+280-char share card …'  /  07:09:46 RING-4 'AIH1-07 …'
```

### Segunda ocorrência na mesma noite: `ananke-20260813-0323`

Não foi caso isolado. O run `ananke-20260813-0323` (24 minutos antes) tem a
MESMA colisão: 18 linhas no ledger central
(`rg '"run": "ananke-20260813-0323"' ledger/ledger.jsonl | wc -l` → 18)
misturam RadioStudio e scentmatch. Seis eventos `open` — RING-1..RING-3
DUPLICADOS, um trio por frente — desambiguáveis só pelos `oracle_sha256`
distintos (`3d3ba88b…` scentmatch × `1f703f4e…` RadioStudio) e pela leitura
das hipóteses:

```
06:25:22 RING-1 'Sessão 08 Scent DNA: /dna com dna.ts puro, DnaCard e
                 ScentDNA reutilizando engine/PerfumeCard/tema …'      ← scentmatch
06:26:42 RING-1 'um passe puro texto→texto (app/core/speech_adapt.py)
                 resolve siglas … sem tocar TTS'                       ← RadioStudio
```

Mesma causa e mesmo mecanismo abaixo cobre — nenhuma correção adicional.
Como no `-0347`, as 18 linhas do `-0323` NÃO foram tocadas (apêndice); ficam
desambiguáveis por este incidente.

## Causa

Duas lacunas somadas em `bin/oracfit-ring.sh`:

1. `run_id="${MODE_ID}-$(date +%Y%m%d-%H%M)"` — granularidade de MINUTO e
   nenhum discriminador de alvo. Dois inits de mesmo modo no mesmo minuto =
   colisão determinística. A coordenação da noite usava sleep de espaçamento
   entre inits justamente por isso, e o espaçamento falhou (processo humano,
   não mecanismo).
2. O schema ring-v1 do `make_event` não carregava NENHUM campo de alvo (os
   modos antigos tinham `workdir`; ring-v1 o perdeu) — por isso a colisão é
   indesambiguável a posteriori: as 24 linhas do `-0347` só se separam por
   leitura humana das hipóteses.

## Correção aplicada

Aplicada ATOMICAMENTE (cp pra `.new` + `mv`; sessões vivas leem do disco).
Sem commit (decisão de dono).

- `bin/oracfit-ring.sh:258-259` — run id agora é
  `<mode>-YYYYMMDD-HHMMSS-<slug-do-basename-do-alvo>` (segundos + alvo
  sanitizado `[a-z0-9-]`, máx. 32 chars). Exemplo real de init de teste:
  `ananke-20260813-042726-ring-demo-5zixst`. O prefixo `<mode>-YYYYMMDD`
  fica INTACTO — monitoração que filtra por startswith não quebra.
- `bin/oracfit-ring.sh:165-176` — `make_event` grava `"target"` (path
  absoluto do alvo) em TODO evento ring-v1, dos DOIS ledgers (workdir e
  central, schema idêntico por construção) — colisão futura de qualquer
  natureza fica desambiguável mecanicamente.
- Compatibilidade: nenhuma validação de formato de id foi adicionada —
  close/score/status continuam usando o `run` do state.json como está, então
  os runs já inicializados esta noite com id antigo seguem funcionando.
- `tests/test-ring-runner.sh` T17 — dois inits consecutivos em alvos
  diferentes → ids distintos, prefixo `<mode>-YYYYMMDD` preservado, slug do
  alvo presente, e o evento `open` do central carrega `run`+`target`
  corretos. Suíte inteira: 45 PASS, 0 FAIL.

As 24 linhas já gravadas do `-0347` NÃO foram tocadas (ledger central é
apêndice, não se reescreve): ficam como registro da colisão, desambiguáveis
por este incidente.

## Pode acontecer de novo?

A colisão de id, não — o discriminador de alvo torna o id único por alvo
mesmo no MESMO segundo, e T17 pina. Colisão residual teórica (mesmo alvo,
dois inits no mesmo segundo) é bloqueada antes pelo próprio init, que recusa
quando `ring/state.json` já existe. A mistura indesambiguável também não: o
campo `target` acompanha todo evento novo. Runs antigos no central continuam
sem `target` — consultas históricas devem tolerar a ausência do campo.
