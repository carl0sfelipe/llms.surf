---
id: 2026-08-13-oracfit-soldado-no-<repo-cliente>-corte-sem-catego
titulo: Oracfit soldado no <repo-cliente> — corte sem categoria specs
data: 2026-08-13
recorrivel: sim
regra: 52
status: promovido
interage_com: |
  2026-07-28-versao-publicada-sem-commit-fonte-de-0-1 (desacoplar <repo-cliente>↔medusa-br;
  o resíduo daquela guerra já vive neste repo),
  2026-08-11-feedback-uso-exaustivo-sessao-pivot-e-fornecedores-v3
  (22 despachos cujo workdir era <repo-cliente>.live-imports; as specs ficaram aqui),
  docs/PUBLIC-CUT.md,
  bin/oracfit-publish-cut.sh,
  ~/primeiras-palavras/oracfit-code-review-2026-08-13.md
---

# Oracfit soldado no <repo-cliente> — corte sem categoria specs

## Sintoma

Leitura fria de terceiro (2026-08-13, `oracfit-main.zip`, VERSION 3.5.0)
em Ubuntu limpo, sem `sqlite3`, sem git config, sem API key:

1. `specs/fornecedores/` — 56 arquivos, ~988 KB, ~2.500 telefones e 18
   e-mails de empresas reais de terceiros. Bloqueador LGPD se o repo
   um dia for público. O GitHub `carl0sfelipe/oracfit` ainda é PRIVATE
   (`gh repo view` → `"visibility":"PRIVATE"`), mas a descrição do
   remoto é **"corte de produto"** e o zip saiu daqui.
2. Dois testes do *próprio framework* só passam se
   `<home-do-dono>/<repo-cliente>.live-imports` existir nesta máquina:

   ```
   tests/test-oracle-freshness.sh
     POISON=<home-do-dono>/<repo-cliente>.live-imports/apps/content-factory/artifacts/nintendo-switch-2/T4-content-validation.yaml

   tests/test-t4-runid-stamp.sh
     CF_ROOT="<home-do-dono>/<repo-cliente>.live-imports/apps/content-factory"
   ```

3. O modo de produto `content_factory` assume a árvore do <repo-cliente>
   (`apps/content-factory`, `apps/storefront`, porta 3010). O template
   de spec diz literalmente: "Workdir alvo = o repo <repo-cliente>.live-imports".
   A regra 43 do `SKILL.md` é política comercial da <repo-cliente> (preço novo vs
   usado no ML) dentro do skill do orquestrador "genérico".

O absurdo declarado pelo dono: semanas foram gastas **desacoplando o
<repo-cliente> do medusa-br**. O resultado visível hoje é o inverso — o
framework que deveria ser ferramenta de qualquer repo **não roda, não
testa e não se explica sem o <repo-cliente>**.

## Causa

Dois eventos distintos. Não misturar.

### Evento A — o corte inverteu e `specs/` nunca foi categoria

O desenho original (cabeçalho de `bin/oracfit-publish-cut.sh`, manifesto
"derivado empiricamente" em 2026-08-01):

```
dispatch/  = oficina (suja, privada)
oracfit/   = corte público (produto)
```

Defaults ainda hardcoded:

```
DISPATCH_DIR=<home-do-dono>/dispatch
ORACFIT_DIR=<home-do-dono>/oracfit
MIRROR_FULL_DIRS=(adapters panel tests fluxos .github)
CURATED_DIRS=(incidents scripts)
```

`specs/` não está em nenhuma das duas listas. Não é regra violada — é
**categoria que o processo nunca viu**. `docs/PUBLIC-CUT.md` manda
handoffs, labs e diário ficarem "no monorepo de desenvolvimento". O
script não impõe isso.

O que aconteceu no git:

| Quando | O quê | Evidência |
|---|---|---|
| 2026-07-31 | GitHub `oracfit` criado como "corte de produto" | `gh repo view` createdAt |
| 2026-08-10 | Trabalho vivo migra *para dentro* do corte (v1.9.0 gauntlet) | `d01774b` |
| 2026-08-12 | `dispatch/` congela em VERSION **1.8.0** | `git -C ~/dispatch log -1` |
| 2026-08-13 | `oracfit/` está em VERSION **3.5.0** | `cat VERSION` |

A oficina morreu. O produto herdou o cargo. Sem segundo repo, a política
do PUBLIC-CUT ficou texto sem mecanismo — exatamente a tese do Oracfit
(regra 32: "toda regra declara seu mecanismo, ou declara que não tem").

### Evento B — despacho de cliente commitado como se fosse o produto

Oracfit guarda spec **ao lado do orquestrador**. Com o evento A, "ao
lado do orquestrador" = "dentro do corte público".

| Quando | Commit | O que entrou no corte |
|---|---|---|
| 2026-08-10 | `d01774b` release v1.9.0 | `core/modes/content_factory.yaml` + os dois testes com path absoluto do <repo-cliente>. O veneno T4 era real (instinto certo); o que foi versionado foi o **caminho da máquina**, não uma fixture em `tests/fixtures/`. |
| 2026-08-10 | `d3b8d6f` `content(<host-local>):` | 10 specs de nicho do catálogo <repo-cliente> |
| 2026-08-11 | `5558b86` **`docs:`** | 23 specs `extract-NN-Copia-de-…FORNECEDORES…`, **29.068 linhas**. Mensagem classifica lista de contato de terceiro como documentação. |
| 2026-08-11 | incidente de uso | 22 despachos, workdir `<repo-cliente>.live-imports`, extração de 5.758 registros / 3.567 únicos. O JSON de saída ficou no <repo-cliente>; as **specs com o texto-fonte** ficaram aqui. |
| 2026-08-12 | `7ce27f7` etc. | lotes v3 2–4, mais specs de fornecedor |

`.gitignore` cobre runtime (`.dispatch/`, `ledger/`, `probe/`, `.env`) e
é cego para *conteúdo*. `bin/check-saude.sh` / `check-spec.sh` recusam
fato inventado, não telefone de terceiro. Não existe `check-publico.sh`.

`bin/cf-probe.sh` declara o universo default:

```
ORACFIT="${ORACFIT_ROOT:-<home-do-dono>/oracfit}"
<repo-cliente>="${ORBE_ROOT:-<home-do-dono>/<repo-cliente>.live-imports}"
```

Contagem em 2026-08-13 (working tree):

```
git grep -l '<repo-cliente>.live-imports'  → 101 arquivos
git grep -l '<home-do-dono>'        → 127 arquivos
git grep -c '<repo-cliente>.live-imports'  → 151 ocorrências
ls specs/                        → 109 arquivos
ls specs/fornecedores/           → 56 arquivos
```

O `dispatch/` original tem `specs/` de produto (PRD, templates, auditoria)
e **zero** `specs/fornecedores/`. A carga LGPD nasceu depois da inversão,
neste repo.

### O que isto NÃO é

Não é "esquecemos de desacoplar o <repo-cliente> do medusa-br". Aquele
desacoplamento é outra guerra (incidente `2026-07-28-versao-publicada-…`,
`kit-storefront` no consumidor <repo-cliente> vs fonte em `medusa-br-framework`).
O resíduo dela já mora *neste* `incidents/` — outro sintoma da mesma
inversão: o diário da oficina <repo-cliente> foi para o corte do orquestrador.

Aqui a seta inverteu de novo: **a ferramenta passou a depender do
cliente**. Mesmo padrão, outro eixo.

## Correção aplicada

Decisão do dono (2026-08-13): **opção 1** — a oficina (este repo)
continua privada; corte público é repo novo, histórico limpo, sem
`specs/fornecedores/`, sem `docs/handoffs/`, sem `incidents/uso/`.
Não é `git rm` neste histórico (o zip e os clones já viram o conteúdo).

Mecanismos aplicados na mesma data (2026-08-13):

1. **`bin/check-publico.sh`** (novo) — C1 telefone BR delimitado,
   C2 e-mail fora de allowlist de domínios sintéticos, C3 caminho de
   máquina (`/Users/<user>`) em código. Dois modos: `--oficina` (varre
   só a superfície exportável deste repo) e `<DIR>` (scan cheio de um
   candidato a corte).
2. **Plug no `bin/check-saude.sh`** — checagem "superfície pública sem
   dado pessoal" na seção Regras; CI (`check-saude.yml`) herda.
3. **`bin/oracfit-publish-cut.sh`** — `PRIVATE_DIRS=(specs docs/handoffs
   docs/prompts incidents/uso lessons)` declarada no manifesto (a
   categoria invisível agora existe, como exclusão); `report` lista a
   presença delas no público como bloqueio; `apply` ganhou pós-condição
   dupla (assert de ausência de PRIVATE_DIRS + `check-publico.sh` scan
   cheio no destino) e guarda anti-corte-regressivo por VERSION
   (fonte 1.8.0 → destino 3.5.0 recusa — o rsync --delete invertido
   deste incidente não passa mais). Defaults `<home-do-dono>/...` → `$HOME`.
4. **Fixture dos testes T4** — `tests/fixtures/t4-poison-nintendo-switch-2.yaml`
   (cópia byte a byte do veneno, sha `47a7c3ef…` idêntico ao travado);
   `test-oracle-freshness.sh` e `test-t4-runid-stamp.sh` apontam pra ela
   por `$REPO_ROOT`. Os dois passam sem o <repo-cliente> no disco (7/0 e 6/0).
5. **Varredura de caminho de máquina em código** — `cf-probe.sh`
   (defaults por script-dir/`$HOME`), `card_redesign.yaml`
   (`$ORACFIT_WORKDIR`), `check-import-symbols.py`, `check-gguf.sh`,
   `adapters/hermes/env.sh`, `fluxos/_comum/artefato-template.md`.
   `check-publico.sh --oficina` verde depois disso.

Fica pra frente (fora desta fatia): criar o repo público novo (rsync sem
histórico) e decidir a curadoria de `incidents/` no corte.

Complemento (2026-08-13, tarde — decisão de dono): `specs/fornecedores/`
(56 arquivos, ~988 KB) **movido para o repo do <repo-cliente>**, ao lado do resto do
pipeline: `<repo-cliente>.live-imports/data/fornecedores/specs-extracao/` (irmão de
`extracted/` e `enrichment/`, fonte em `fornecedores/`). Na working tree
do oracfit ficaram só as 56 deleções aguardando commit;
`check-publico.sh --oficina` verde após o move. O conteúdo permanece no
HISTÓRICO deste repo (e do origin, privado) — a limpeza continua sendo o
corte novo sem histórico, como decidido acima.

## Pode acontecer de novo?

Sim. Já está acontecendo no mesmo formato com outros alvos: specs de
`vagai`, `torlink`, `isef`, `wt-oracfit` overnight, todas com path
absoluto de máquina, todas neste repo. Fornecedores é só o caso
juridicamente pior de um bug geral:

> o repo do produto é o disco de rascunho de todo despacho.

Enquanto spec viver "ao lado do orquestrador" e o orquestrador for o
corte público, cada cliente novo recontamina. A recontaminação agora
bate no `check-saude` (CI vermelho, não review): telefone/e-mail na
superfície exportável e caminho de máquina em código são bloqueio
mecânico. O que o gate NÃO cobre, declarado: spec nova de cliente em
`specs/` continua entrando na oficina sem alarde (é onde ela mora por
design da opção 1) — o que está garantido é que ela **não sai** no
corte (`PRIVATE_DIRS` + scan cheio no destino).

Promovido com mecanismo existente (regra 32 satisfeita) — ver campo
`regra:` no frontmatter.

Complemento (2026-08-14 — corte criado): repo público novo montado em
`<home-do-dono>/oracfit-public` a partir do commit `62281c8` (HEAD da
oficina; nada da working tree suja), histórico limpo de 1 commit
(`86be7cf`), 367 arquivos. Fora: specs/, incidents/uso/, handoffs/,
prompts/, pesquisa/, ring/, scripts/, CHECKPOINTS*, DO-DONO,
fantasma-baselines. Dentro: 94 postmortems de mecanismo ANONIMIZADOS
(`<home-do-dono>`→`$HOME`, <repo-cliente>.live-imports→`<repo-cliente>`, e-mail real
do dono→`dev@local`); 9 postmortems de cliente excluídos por título.
`check-publico.sh` scan cheio VERDE; testes T4 (7/0, 6/0) e smoke do CLI
passam no corte isolado.

Complemento (2026-08-14, tarde — o review do corte pescou vazamentos
deixados pela primeira passada): `bin/corte-review.py` (novo, mecanismo da
página /corte.html de triagem) REJEITOU o corte inicial e achou: (1)
"<repo-cliente>" em caixa alta sobrando no postmortem da regra 43 (a anonimização
só trocava "<repo-cliente>"); (2) `incidents/evidence/` inteira no corte — 1,7MB de
logs brutos de dispatch com paths de máquina e specs de cliente, INVISÍVEL
aos dois gates (.log/.json fora das include-lists do C3; o anon do review
só lia .md). Corrigido: evidence/ removida (vira categoria privada
declarada no corte-review), marcadores trocados; corte final `d2aa07c`,
351 arquivos, review APPROVED. Lições: anonimização por casamento exato de
case é furo; evidência crua não é postmortem — não entra em corte. Pendente do dono: rename GitHub
(oracfit→oficina), criar repo público `oracfit`, push — corte fica
local até revisão.
