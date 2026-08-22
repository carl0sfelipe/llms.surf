---
id: 2026-08-11-migracao-zerou-catalogo-medusa-produto-fora-do-seed-perdido
titulo: Limpeza de disco recriou volume Postgres — catálogo zerado; seed recuperou 19 produtos; <host-local> avulso perdido
data: 2026-08-11
recorrivel: sim (disco cheio → colima delete → volume novo → seed obrigatório)
status: corrigido-parcialmente
interage_com: "docs/handoffs/ESTADO-2026-08-11-v3-e2e.md"
---

# Limpeza de disco recriou volume Postgres — catálogo zerado

## Sintoma

Após trabalho de infra na madrugada de 2026-08-11, o catálogo Medusa
(`orbe_prod` no container `infra-postgres-1`) apareceu vazio. O usuário rodou
`seed-products.ts` e recuperou **19 produtos** — todos com `created_at` no
mesmo segundo (~21:16 BRT). O **<host-local> SER** (criado avulso, fora do seed,
handle histórico `<host-local>-ser5-max-ryzen7-24gb-500gb`) **não voltou**; outro
agente está recriando e adicionando ao seed.

O sintoma foi interpretado como "migração Medusa", mas a investigação mostra
que **não houve migration de schema que apagou linhas** — o volume Postgres foi
recriado do zero.

## Causa

**Causa raiz: recriação do volume Docker `infra_postgres_data` durante limpeza
de emergência por disco 100% cheio**, documentada em
`docs/handoffs/ESTADO-2026-08-11-v3-e2e.md` §Infra:

> Disco: estava 100% cheio → 59 GB livres. Removido: colima antigo + datadisk
> órfão de 60 GB + caches npm. Colima recriado. **Banco foi zerado na
> limpeza** → migração teve que rodar DO HOST … Seed via docker compose run …

Sequência verificada:

| Evento | Evidência | Timestamp |
|--------|-----------|-----------|
| Volume Postgres criado (cluster novo) | `docker volume inspect infra_postgres_data` → `CreatedAt: 2026-08-11T02:14:16-03:00` | 02:14 BRT |
| initdb do cluster | `docker logs infra-postgres-1 \| head` → "creating configuration files", "CREATE DATABASE" | 05:14 UTC (= 02:14 BRT) |
| Container Postgres recriado | `docker ps` → `CreatedAt: 2026-08-11 02:14:16` | 02:14 BRT |
| Migrations Medusa em DB vazio | `mikro_orm_migrations`: 167 migrations, lote com `executed_at = 2026-08-11 06:01:37 UTC` | ~03:01 BRT |
| Seed restaurou catálogo | `product`: `min/max(created_at) = 2026-08-12 00:16:32 UTC`, `count = 19` | ~21:16 BRT |
| <host-local> ausente pós-seed | `select handle from product` — 19 handles, nenhum <host-local>* | — |

Inventário pré-limpeza (`~/colima-inventory-2026-08-11.txt`) confirma que
**antes** existia `infra-postgres-1` com **2 weeks ago** e volume
`infra_postgres_data` — dados antigos foram perdidos com a recriação do Colima,
não com `medusa db:migrate` em si.

**Por que o <host-local> sumiu e os outros não:** os 19 produtos do seed
(`apps/backend/src/scripts/seed-products.ts`) foram re-aplicados; o <host-local>
havia sido cadastrado manualmente (`docs/handoffs/START-10-POSTS-HERE.md`: "O produto NÃO
está no seed-products.ts … mas está vivo na loja") e não tinha backup fora do
volume.

**Alucinação colateral do content-factory (não causou a perda, mas expôs o
buraco):** o piloto `cf-<host-local>-radeon680m-v3` exportou post que chama o
produto de **"<host-local> EQR6"** com specs **32 GB / 1 TB** (dados do T1-HUNT de
anúncio ML), quando o produto real é **SER 6800U 24 GB / 500 GB**. A spec
citava handle `<host-local>-ser5-max-ryzen7-24gb-500gb`; o post exportado aponta CTA
para `/produtos/<host-local>-ser-6800u-24gb-500gb` — handle que só passou a existir
depois do re-seed/outro agente. Ninguém validou que o CTA apontava para produto
vivo no banco no momento da exportação.

## Correção (em andamento / aplicada)

1. **Re-seed** dos 19 produtos canônicos via `medusa exec …/seed.ts` — feito.
2. **<host-local> recriado e adicionado ao seed** (`<host-local>-ser-6800u-24gb-500gb` em
   `seed-products.ts`) — outro agente, em curso na sessão.
3. **Seed como fonte de verdade do catálogo** — produto manual sem entrada no
   seed não sobrevive a recriação de volume.

## Prevenção

1. **Regra candidata:** todo produto criado à mão **DEVE** entrar em
   `seed-products.ts` no **mesmo dia** — o seed é o único mecanismo de
   recuperação comprovado após wipe de volume.
2. **Backup antes de mexer em infra/volume:** considerar `pg_dump` automático
   (cron ou hook pré-`colima delete` / `compose down -v`) de `orbe_prod` para
   `~/backups/` — diretório **não existe hoje** e nenhum dump `.sql`/`.dump` foi
   encontrado no repo ou em `~/`.
3. **Check de CTA vs catálogo:** o post do blog exportado pelo CF pode apontar
   para handle inexistente ou alucinar nome/modelo ("SER5 Max", "EQR6") —
   candidato a gate futuro: no `export-to-blog.py` ou no
   `vision_gate`/oráculo do oracfit, validar que todo link `/produtos/<handle>`
   resolve para produto publicado no Medusa (e que specs citadas batem com
   metadata do produto).

## Evidência

### Volume e cluster novos

```bash
$ docker volume inspect infra_postgres_data
"CreatedAt": "2026-08-11T02:14:16-03:00"

$ docker logs infra-postgres-1 2>&1 | head -5
The files belonging to this database system will be owned by user "postgres".
...
creating configuration files ... ok
running bootstrap script ... ok
```

### Produtos só do seed (19, mesmo timestamp)

```bash
$ docker exec infra-postgres-1 psql -U <repo-cliente> -d orbe_prod \
  -c "select count(*), min(created_at), max(created_at) from product"
 count |            min             |            max
-------+----------------------------+----------------------------
    19 | 2026-08-12 00:16:32.176+00 | 2026-08-12 00:16:33.344+00

$ docker exec infra-postgres-1 psql -U <repo-cliente> -d orbe_prod \
  -c "select handle from product where handle like '%<host-local>%'"
(0 rows)
```

### Migrations em lote sobre DB vazio (não DROP de produto)

```bash
$ docker exec infra-postgres-1 psql -U <repo-cliente> -d orbe_prod \
  -c "select count(*) from mikro_orm_migrations"
 count
-------
   167

$ docker exec infra-postgres-1 psql -U <repo-cliente> -d orbe_prod \
  -c "select name, executed_at from mikro_orm_migrations order by executed_at desc limit 3"
          name           |          executed_at
-------------------------+-------------------------------
 Migration20260801191222 | 2026-08-11 06:01:37.713047+00
 Migration20260722142500 | 2026-08-11 06:01:37.713047+00
 Migration20260801224755 | 2026-08-11 06:01:37.683295+00
```

### Documentação da sessão (causa operacional)

`docs/handoffs/ESTADO-2026-08-11-v3-e2e.md` §Infra (linhas 37–47):

> Infra (recriada hoje após limpeza de disco) … Banco foi zerado na limpeza →
> migração teve que rodar DO HOST … Seed via docker compose run …

### Inventário pré-limpeza

`~/colima-inventory-2026-08-11.txt` — capturado antes do `colima delete`;
lista `infra-postgres-1` **2 weeks ago** e volume `infra_postgres_data` existente.

### Backup

```bash
$ ls ~/backups
ls: <home-do-dono>/backups: No such file or directory

$ rg --files -g '*.sql' -g '*.dump' <home-do-dono>/<repo-cliente>.live-imports
(sem resultados)
```

### Alucinação CF no post exportado

`apps/storefront/content/blog/cf-<host-local>-radeon680m-v3.mdx`:

- título/modelo: "<host-local> **EQR6**" (produto real: SER 6800U)
- specs no texto: 32 GB / 1 TB (produto <repo-cliente>: 24 GB / 500 GB)
- CTA: `/produtos/<host-local>-ser-6800u-24gb-500gb` (handle pós-recriação; spec
  original citava `<host-local>-ser5-max-ryzen7-24gb-500gb`)
