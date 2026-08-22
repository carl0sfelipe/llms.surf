---
id: 2026-08-12-colisao-de-id-hefesto-dois-god-modes-distintos-com-o-mesmo-nome-a-4min-de-distancia
titulo: Dois god modes DIFERENTES chamados `hefesto` nasceram a 3min42s de distância (core do oracfit 21:14:56 vs workdir do poker-freeroll-radar 21:18:38) — a resolução por overlay muda com o $PWD, o homônimo do core FALHA na própria validação, e nada no registro de modos detecta colisão de id
data: 2026-08-12
recorrivel: sim
regra: nao — regra candidata "unicidade de id + aviso de sombreamento no mode validate" (regra 5 do postmortem principal do hefesto)
status: aberto
interage_com: "2026-08-12-hefesto-god-mode-6-stories-verdes-critic-fresco-pegou-os-2-blockers-e-checkpoint-manuscrito-duplicou"
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
---

# Colisão de id `hefesto` — dois modos distintos, mesmo nome, mesmo dia

## Sintoma

Descoberto DURANTE a escrita do postmortem do god mode HEFESTO (não durante
o run): existem dois arquivos de modo com `id: hefesto`, escritos por
sessões diferentes, com conteúdo e propósito diferentes:

| | hefesto A (core) | hefesto B (workdir) |
|---|---|---|
| Path | `~/oracfit/core/modes/hefesto.yaml` | `~/poker-freeroll-radar/core/modes/hefesto.yaml` |
| Commit | `ac4398c` (repo oracfit), **21:14:56 -0300** | `bc8e1fb` (repo do projeto), **21:18:38 -0300** |
| Propósito | "god mode executor de spec-packs" (`model_ref: frontier-session`) | "god mode de fábrica BMAD" (`model_ref: frontier-host`, stages plan/run/vision_gate/export) |
| Validação (medida) | **FAIL**: `unknown key 'halt_conditions'`, `unknown key 'never'` | **OK**: `roles=['plan', 'run', 'vision_gate', 'export']` |

Medição da resolução (terminal desta sessão): `bin/oracfit mode validate
hefesto` rodado de `~/poker-freeroll-radar` resolve o B e imprime OK; rodado
de `~/oracfit` resolve o A e imprime FAIL. O mecanismo é o overlay
documentado no próprio CLI (`bin/oracfit` linhas 125-133: tenta
`${ORACFIT_WORKDIR:-$PWD}/core/modes/<id>.yaml` primeiro, depois o ROOT) —
ou seja, **qual modo o nome `hefesto` designa depende do diretório em que o
comando roda**.

Sobre a ordem dos nascimentos: não há timestamp confiável para o momento em
que cada sessão ESCOLHEU o nome (transcripts não carregam relógio nos
eventos); o que é medido são os commits, a 3min42s de distância. As duas
sessões corriam em paralelo na mesma máquina — 9 god modes foram commitados
no oracfit só em 2026-08-12 (pythia 16:25 e demiurgo 16:27 à tarde; autarca,
talos, hefesto A, midas, pantocrator, ouroboros e aion na rajada
21:14–21:56; `git log --since='2026-08-12'` do repo), e "deus grego da
forja" é um atrator óbvio para um modo que constrói sozinho.

## Por que é um incident PRÓPRIO

Não é falha do run do hefesto B (que fechou 6 stories sem tocar no A) nem
de ambiente — é falha de CONTRATO do registro de modos:

1. **O id é a chave de tudo e não tem dono**: ledger (quando existir, regra
   1 dos postmortems irmãos), incidents, CHECKPOINTS e o prompt padrão da
   convergência v4 referem-se a modos pelo id. Hoje, "hefesto" é ambíguo em
   qualquer texto que não cite o path — inclusive nos incidents da
   convergência, que é exatamente onde a ambiguidade custa caro.
2. **O sombreamento é silencioso por construção**: o overlay foi desenhado
   para projetos especializarem modos, mas não distingue "especializar o
   modo X do core" de "modo diferente que por azar tem o mesmo nome". O
   validador imprime OK/FAIL sem avisar que outro arquivo com o mesmo id
   existe no outro nível.
3. **O homônimo do core está quebrado e ninguém percebeu**: o hefesto A
   falha a própria validação (`halt_conditions`, `never` — chaves fora do
   schema v1, o mesmo erro que demiurgo/ouroboros cometeram e que o hefesto
   B evitou de propósito). Foi commitado assim mesmo — nenhum hook valida
   modos no commit do repo oracfit.

Dano observado até agora: zero em execução; o custo real recai na
AUDITORIA — este postmortem precisou de uma seção de desambiguação, e
qualquer leitor futuro de `rg hefesto` no oracfit vai misturar os dois.

## Mitigação aplicada

Nenhuma mudança de código (postmortem não edita modos de outros agentes). A
desambiguação está escrita na FICHA TÉCNICA do postmortem principal do
hefesto B, com paths e commits dos dois arquivos.

## Regra candidata para a v4

**Unicidade de id + aviso de sombreamento** (= regra candidata 5 do
postmortem principal):

- `mode validate <id>` e `modes` imprimem WARNING sempre que o id resolve em
  MAIS de um nível (workdir + core), mostrando os dois paths e se os
  conteúdos divergem (hash);
- criar modo novo (`mode init`) recusa id que já existe em qualquer nível
  sem `--shadow` explícito;
- hook de pre-commit no repo oracfit roda `mode validate` em todo yaml de
  `core/modes/` tocado — teria barrado o hefesto A, que está no core FALHANDO
  validação desde 21:14.

Custo: 1 stat + 1 hash no validate; hook de 3 linhas.

## Evidência

- hefesto A: `git -C ~/oracfit show ac4398c` (mensagem, data 21:14:56,
  conteúdo "executor de spec-packs"); validação FAIL medida no terminal
  desta sessão.
- hefesto B: `git -C ~/poker-freeroll-radar show bc8e1fb --
  core/modes/hefesto.yaml` (data 21:18:38, "fábrica BMAD"); validação OK
  medida no mesmo terminal.
- Resolução por overlay: `~/oracfit/bin/oracfit` linhas 90-91 e 125-133
  (workdir primeiro, ROOT depois).
- Rajada de god modes do dia: `git -C ~/oracfit log --format='%h %ad %s'
  --since='2026-08-12 00:00'` (7 commits `feat(modes)` de god modes).
