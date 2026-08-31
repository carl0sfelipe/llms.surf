# spec: run-luna-catalog-2026-08-31 — endpoints de catálogo (bestmodel)

Implementação. A decisão já foi tomada (unlock do Fable, item D5.1). Você
executa; não redecide. Backend com pytest + a ligação no front.

Três histórias, **um commit por história**, nesta ordem. A 2 depende da 1
(o front consome a rota que a 1 cria). Você toca 7 arquivos no total — se o
seu diff quiser tocar um oitavo, PARE e relate no relatório final em vez de
alargar o escopo.

## Protocolo (obrigatório)

1. **Ler antes de escrever.** Todo arquivo que você tocar, leia inteiro antes.
2. **O disco vence esta spec.** Achou fato aqui que não bate com o disco:
   pare, anote no relatório, siga o disco.
3. **Proibido shotgun.** Diff querendo tocar >7 arquivos = repensar.
4. **Nunca enfraquecer teste para ficar verde.** Conserta o código.
5. **Nada de `declare const`, `as any`, `@ts-ignore` ou stub** para calar tipo.
   Importe de verdade ou relate o bloqueio.
6. Não invente numero, prazo, fonte ou nome de campo alem dos listados aqui.
7. Não rode `git push`. Commits locais só.
8. Não crie migração de banco. Nenhuma tabela muda.

## Dados verificados

Workdir = repositório bestmodel. API em `apps/public-api` (FastAPI, pytest).
Front em `apps/web-next` (Next 15 App Router, TypeScript strict, npm).

O esquema das duas tabelas de catálogo está em
`infra/migrations/0002_create_model_catalog.sql`. A tabela `model_release` tem
chave primária `id` (TEXT) e as colunas `family`, `release_name`,
`parameter_count_billion` e `max_context_tokens`, entre outras. A tabela
`quantization_profile` tem chave primária `id` (TEXT) e as colunas
`display_name`, `weight_format` e `weight_bits`, entre outras.

A camada de sessão está em
`apps/public-api/src/dependencies/database_session_provider.py`: uma classe
abstrata `DatabaseSession` e a implementação real logo abaixo. Nela já existe
`fetch_quantization_profiles`, que roda `SELECT * FROM quantization_profile
ORDER BY id`, e já existe `fetch_all_gpus`, que segue o mesmo padrão para GPUs.
Para modelos existem apenas `fetch_models_by_family` e `fetch_model_by_id` —
não existe nenhum método que devolva todos os `model_release`.

O fake que os testes usam é `packages/fake-adapters/src/fake_database.py`. Ele
carrega o catálogo dos arquivos de seed via `_load_seed`, guardando os modelos
em `self._models` e os perfis em `self._quants`, e implementa
`fetch_quantization_profiles` devolvendo `list(self._quants)`. Os seeds são
`infra/seed/model_releases.json` e `infra/seed/quantization_profiles.json`;
entre eles existe o modelo de id `model-qwen25-coder-32b` com `release_name`
igual a `Qwen2.5-Coder-32B`, e o perfil de id `q-fp16` com `display_name`
igual a `FP16`.

O registro de rotas está em `apps/public-api/src/main.py`, numa sequência de
chamadas `include_router`. Uma rota mínima de leitura pública, sem auth, está
em `apps/public-api/src/routes/transparency_route.py` — é o padrão de estilo a
copiar. Uma rota que injeta a sessão está em
`apps/public-api/src/routes/claim_route.py`, com a assinatura
`session: DatabaseSession = Depends(get_database_session)`.

Os testes ficam em `apps/public-api/tests`. O `apps/public-api/tests/conftest.py`
expõe a fixture `client`, um TestClient com `get_database_session` sobrescrito
pelo fake — é a fixture certa para rota de leitura sem auth.

No front, `apps/web-next/lib/social.ts` exporta hoje `fetchClaimCatalog`, que
deriva a lista de modelos e quantizações lendo o próprio feed de claims, porque
não existe rota de catálogo publicada. `apps/web-next/app/submit/submit-client.tsx`
consome essa função, guarda o resultado no estado `catalog`, e tem uma função
`decorate` que casa o id opaco contra os slugs derivados do tipo `ModelLabel`
para achar um nome legível e uma categoria de modalidade.

FATOS DE RUNTIME (não estão no disco — medidos por mim no Postgres de produção
em 2026-08-31 com `psql` no container bestmodel-prod-postgres-1): a tabela
model_release tem 78 linhas, a quantization_profile tem 10, e as claims
existentes referenciam apenas 37 model_release_id distintos. O formulário de
captura, que só enxerga o que o feed mostrou, oferece menos que isso. Abrir o
catálogo leva a porta de entrada de 37 para 78 modelos e, mais importante, troca
id opaco por nome legível vindo da fonte autoritativa.

Escada de honestidade da casa: measured = n≥3; reported = 1-2; ausência se
declara "no data yet"; NUNCA estimativa com cara de medida.

### História 1 — as duas rotas de catálogo

Acrescente ao provedor de sessão um método que devolva todos os model_release,
seguindo exatamente o padrão de fetch_all_gpus: declaração abstrata com
docstring de uma linha na classe abstrata, e implementação real rodando
`SELECT * FROM model_release ORDER BY id`. Nomeie-o fetch_all_model_releases.
Implemente o mesmo método no fake, devolvendo uma cópia da lista de modelos,
ao lado da implementação de fetch_quantization_profiles que já está lá.

Crie a rota em apps/public-api/src/routes/catalog_route.py, com
`router = APIRouter(prefix="/v1", tags=["catalog"])` e dois GET públicos, sem
autenticação nenhuma:

- GET /v1/model-releases
- GET /v1/quantization-profiles

Cada uma devolve um envelope, NÃO um array pelado:

    {"items": [...], "count": <int>}

O envelope é obrigatório e é decisão tomada: o catálogo é tabela de referência
que vai crescer, e o envelope permite acrescentar limite e deslocamento depois
sem quebrar quem já consome. Registre num comentário de 2 linhas no arquivo
que hoje não há paginação porque o catálogo inteiro cabe numa resposta, e que
limite/deslocamento entram quando deixar de caber. NÃO implemente paginação
agora — nem parâmetro de query, nem limite.

Cada item é uma PROJEÇÃO explícita, nunca a linha inteira do banco. O
`SELECT *` traz todas as colunas; a rota escolhe as que publica. As chaves são
exatamente estas, nesta ordem, e nenhuma outra:

    model-releases:        id, release_name, family, parameter_count_billion,
                           max_context_tokens
    quantization-profiles: id, display_name, weight_format, weight_bits

parameter_count_billion e weight_bits são NUMERIC no Postgres e chegam como
Decimal. Converta os dois explicitamente para float na projeção, tratando None
como None — não confie no encoder do FastAPI para isso. Ordem dos itens: por
id ascendente, que já é a ordem do SELECT.

Escreva os testes em apps/public-api/tests/test_catalog_routes.py usando a
fixture client, sem mandar header de autorização em nenhum deles. Cubra:

1. as duas rotas respondem 200 sem token;
2. em cada uma, count é igual ao comprimento de items e maior que zero;
3. o conjunto de chaves de um item é EXATAMENTE o conjunto especificado acima
   — este teste é o que impede a linha inteira do banco de vazar, então não o
   afrouxe;
4. items de model-releases contém o id `model-qwen25-coder-32b` com
   release_name `Qwen2.5-Coder-32B`;
5. items de quantization-profiles contém o id `q-fp16` com display_name `FP16`;
6. a lista vem ordenada por id ascendente.

Registre as duas rotas em apps/public-api/src/main.py, na mesma sequência de
include_router, importando no mesmo padrão dos vizinhos. Posição: antes de
claim_route, porque são prefixos fixos e não colidem com nada.

NÃO: não toque em claim_route.py, não toque em create_run_claim, não mexa em
nenhuma outra rota, não acrescente autenticação, não acrescente cache.

### História 2 — o formulário de captura passa a ler o catálogo

Em apps/web-next/lib/social.ts, acrescente os dois tipos e as duas funções que
consomem as rotas da História 1. Tipos: um para o item de modelo com os cinco
campos publicados, outro para o item de quantização com os quatro. As funções
usam o mesmo helper `request` interno que as outras chamadas usam — não escreva
fetch na mão, não duplique tratamento de erro.

Substitua o uso de fetchClaimCatalog por uma função nova que:

1. chama as duas rotas de catálogo;
2. se AS DUAS derem certo, devolve o catálogo real, marcado como vindo da API;
3. se qualquer uma falhar, cai de volta em fetchClaimCatalog e devolve o
   resultado marcado como derivado do feed.

O fallback é obrigatório e não é zelo excessivo: o front roda na Vercel e a API
roda em outra máquina, então existe uma janela real em que o front novo fala
com a API velha. Nessa janela o formulário tem de continuar funcionando em vez
de ficar vazio. MANTENHA fetchClaimCatalog exportada — ela vira o caminho de
degradação, não código morto.

Em apps/web-next/app/submit/submit-client.tsx:

- o estado do catálogo passa a guardar os objetos, não listas de string;
- o rótulo de cada opção de modelo passa a ser o release_name vindo da API,
  que é o nome autoritativo. A função decorate continua sendo usada, mas SÓ
  para descobrir a categoria de modalidade que agrupa o select; quando a API
  deu o release_name, ele ganha do nome derivado. Sem release_name (caminho do
  fallback), o comportamento de hoje continua igual;
- o rótulo de cada opção de quantização passa a ser o display_name;
- o texto de ajuda embaixo do select de modelo diz hoje que a API não tem
  endpoint de catálogo. Essa frase deixa de ser verdade: quando a lista veio da
  API, o texto passa a dizer que é o catálogo completo da API; quando veio do
  fallback, diz que a rota de catálogo não respondeu e que a lista é o que o
  mural já mostrou. Dois textos, escolhidos pela procedência real — não escreva
  um texto que sirva para os dois casos.

NÃO: não mexa nas duas portas (found/ran), não mexa em nenhuma validação de
campo, não mexa no envio, não toque em nenhuma outra rota do front, não crie
token de cor.

### História 3 — a documentação da API acompanha

Em `docs/en/api.md`, se o arquivo existir, acrescente as duas rotas na mesma
forma que as vizinhas usam: caminho, método, se pede auth, e a forma da
resposta. Se o arquivo não existir, NÃO crie um: pule a história inteira e
diga no relatório que pulou e por quê. Não invente estrutura de documentação
nova para justificar a história.

## Regras

Nao invente numero, prazo, fonte ou campo alem dos listados nos Dados
verificados. NUNCA use declare const como workaround de checagem de tipo —
importe de verdade; se um símbolo não existir, relate em vez de declarar.

Ao final escreva `.dispatch/run-luna-catalog-report.md` com: o que foi feito
por história, divergências entre esta spec e o disco (com arquivo:linha), e o
que você decidiu não fazer.

## Oráculo

- comando: test -f apps/public-api/src/routes/catalog_route.py && test -f apps/public-api/tests/test_catalog_routes.py && test -f apps/public-api/src/main.py && grep -q "catalog_route" apps/public-api/src/main.py && test -f apps/public-api/src/dependencies/database_session_provider.py && grep -q "fetch_all_model_releases" apps/public-api/src/dependencies/database_session_provider.py && test -f packages/fake-adapters/src/fake_database.py && grep -q "fetch_all_model_releases" packages/fake-adapters/src/fake_database.py && test -f apps/web-next/lib/social.ts && grep -q "model-releases" apps/web-next/lib/social.ts && test -f .dispatch/run-luna-catalog-report.md && python3 -m pytest apps/public-api/tests/test_catalog_routes.py -q && npm --prefix apps/web-next run build
- exit esperado: 0 = as duas rotas existem, estao registradas, o metodo novo
  existe na sessao real e no fake, o front consome a rota, o relatorio foi
  escrito, a suite nova passa e o build do front fica verde. Antes do run,
  exit 1 e o estado CORRETO — nada disso existe ainda.

## Verificação

VERIFICACAO: python3 bin/check-oracle.py docs/go-live/RUN-LUNA-CATALOG-2026-08-31.md "$(mktemp -d)" --quiet

Resultado esperado: "oráculo falha (exit 1) e falha pelo motivo certo", exit 0.

## Barra

A referência é o protocolo anti-bug já field-testado nesta casa: spec congelada
antes do código, um commit por história, main intocada, zero teste enfraquecido
e relatório de divergências no fim. Passa na barra o diff em que um revisor lê
a projeção da rota e sabe, sem perguntar, quais colunas do banco são públicas
e quais não são.
