# Um RESET que não destrói a evidência: snapshot WIP por plumbing + restauração escopada

## Objetivo

Dar ao runtime uma ação **RESET** que reverta a deriva do agente sem apagar
o que a deriva mostrou. Hoje não existe nada disso na árvore:
`grep -rn "refs/llms-surf\|write-tree\|update-ref" bin/ core/ fluxos/`
não devolve nada, e o único precedente — o run `951f5899`, que morreu porque
um script em execução foi editado in-place (regra 48) — é uma regra sem
mecanismo.

Este rung entrega o mecanismo: **snapshot WIP imutável por git plumbing**,
**restauração escopada que respeita as zonas protegidas**, e **a linha de
cicatriz** que nomeia o ref para o agente. Nenhum runtime chama isto ainda — a
chamada é o rung do modelo de decisão.

Origin: `docs/decision-supervisor.md` §5.5 e §10 (rung D2).

## Dados verificados

- `git write-tree` escreve o **índice**, não a árvore de trabalho. Medido num
  repositório de teste: depois de editar um arquivo rastreado e criar um
  arquivo não rastreado, `git write-tree` devolveu uma árvore com **só** o
  conteúdo já commitado do arquivo rastreado — a edição suja e o arquivo novo
  faltando. `git ls-tree -r <tree>` confirmou. Uma snapshot feita assim guarda
  o estado **de antes** da deriva, que é o oposto do que se quer.
- `git stash create` grava as modificações de arquivos rastreados mas **não**
  arquivos não rastreados (medido: `git stash create` devolveu um commit; a
  árvore do commit não continha o arquivo novo). `git stash push` pegaria o
  arquivo novo, mas altera a árvore de trabalho — o que a regra 48 proíbe.
- O que funciona: **índice de rascunho fora da árvore de trabalho**. Medido:
  com `GIT_INDEX_FILE` apontando para um arquivo temporário **fora** do
  repositório, `git read-tree HEAD` + `git add -A` + `git write-tree` produz
  uma árvore com o conteúdo editado do arquivo rastreado **e** o arquivo não
  rastreado; o índice real e a árvore de trabalho ficam intactos
  (`git status --porcelain` idêntico antes e depois).
- Se o índice de rascunho fica **dentro** da árvore de trabalho, o `git add -A`
  adiciona o próprio arquivo de índice como arquivo novo (medido: a árvore
  continha `scratch.idx` e `scratch.idx.lock`). Por isso o índice tem que ser
  criado **fora** do workdir.
- Onde o índice de rascunho pode ficar é comportamento medido, e corta dos
  dois lados. Num repositório de teste, com o índice de rascunho **dentro** do
  workdir: com o diretório **ignorado** pelo `.gitignore` e uma cópia nova do
  índice, a árvore **não** continha o índice de rascunho (só os arquivos
  commitados); com o diretório **não** ignorado, a árvore continha o índice de
  rascunho **e** o arquivo `.lock` dele, porque os dois são arquivos reais no
  workdir enquanto o `git add -A` roda; e, uma vez que um caminho está no
  índice, o `.gitignore` não o remove — um índice que entrou fica. `.dispatch/`
  está no `.gitignore` **deste** repo, então o placement conveniente é seguro
  aqui. Ele **não** é seguro num projeto alvo despachado, cujo `.gitignore`
  não é nosso para assumir. Logo: índice de rascunho **fora** do workdir, sem
  condição.
- O índice real e a árvore de trabalho ficam **byte a byte idênticos** antes e
  depois do bloco. Isso não significa "nada foi escrito": o banco de objetos
  ganha objetos sem referência (os blobs e a tree novos) e o namespace de refs
  ganha uma ref. É aditivo e inofensivo.
- `git commit-tree` exige identidade: sem `user.name`/`user.email`
  configurados, ele falha com `Author identity unknown` (medido). Com
  identidade explícita (`git -c user.email=... -c user.name=...`) devolve o
  sha do commit.
- `git update-ref` numa ref fora de `refs/heads/` não move o HEAD nem altera a
  árvore de trabalho.
- Repositório sem commit: `git read-tree HEAD` falha. A árvore vazia é
  `git hash-object -t tree /dev/null` (medido: devolve
  `4b825dc642cb6eb9a060e54bf8d69288fbee4904`).
- `core/protected-paths-default.txt` existe e é o mecanismo da regra 47:
  globs relativos à raiz do workdir, um por linha — `AGENTS.md`, `VERSION`,
  `model-registry.json`, `core/*`, `fluxos/*`, `bin/*`, `adapters/*`,
  `incidents/*`, `.oracfit-protected`. O cabeçalho do arquivo diz: só vale
  quando o workdir **é** este checkout e não há `<workdir>/.oracfit-protected`;
  o **evento** é `protected_paths_alert`, alerta e nunca bloqueio. O consumidor
  é `bin/dispatch-mode.sh` (linha 449 escolhe o arquivo de globs; linha 744
  emite o evento).
- O canal de leitura do agente é a **spec composta**, não o stderr: o feedback
  do gauntlet (`bin/lib-oracfit-gauntlet.sh`, `oracfit_gauntlet_append_feedback()`)
  entra na spec da tentativa seguinte. A cicatriz entra pelo mesmo caminho
  (rung D).
- O texto injetado na spec neste repo é em **inglês** — o bloco de feedback é
  `## GAUNTLET FEEDBACK (attempt N) — apply ALL before resubmitting` e o bloco
  de ground truth é `## GROUND TRUTH (Oracfit inject — authoritative for this run)`.
- `bin/check-english.py` exige código, nomes, comentários e mensagens em
  inglês. `english-ok` / `english-ok-begin` / `english-ok-end` marcam os trechos
  que ficam em português.

Nao invente numero, prazo, citacao ou fonte alem dos listados ou dos que
voce abrir de verdade.
NUNCA use declare const como workaround — importe de verdade.

## Files you may touch

- `bin/oracfit-wip-snapshot.sh` (novo) — a biblioteca com as quatro funções.
- `tests/test-wip-snapshot.sh` (novo) — o mecanismo.

Nada mais. Nenhum runtime é tocado neste rung: `bin/dispatch-mode.sh`,
`bin/dispatch-stages.sh` e `incidents/` ficam como estão.

## PROIBIDO

- `push`. Local commits are fine.
- `git reset --hard`, `git checkout .`, `git clean`, `git stash push` em
  qualquer caminho: este rung **não** altera a árvore de trabalho além da
  restauração escopada que ele mesmo faz.
- Mexer em `bin/dispatch-mode.sh`, `bin/dispatch-stages.sh`,
  `bin/lib-oracfit-gauntlet.sh`, `incidents/`, `core/protected-paths-default.txt`
  ou testes existentes.
- Dependência nova. Nada de `pip install`, nada de rede, nada de modelo.
- Escrever fora de `<workdir>` do alvo e do diretório temporário do teste. A
  ref `refs/llms-surf/wip/...` é escrita **no repositório do workdir**, e só
  isso.
- Editar `SKILL.md` ou `CLAUDE.md`.
- Tocar qualquer caminho fora deste worktree.

## PASSOS

1. `bin/oracfit-wip-snapshot.sh`, em bash, com quatro funções públicas:

   **`oracfit_wip_ref_name <run_id> <iter>`** — imprime o nome da ref,
   `refs/llms-surf/wip/<run_id>/iter-<iter>`, e sai 0. Não faz mais nada.

   **`oracfit_wip_snapshot <workdir> <run_id> <iter>`** — cria a snapshot WIP
   do estado sujo do workdir:
   - se o workdir **não** é um repositório git, imprime
     `wip snapshot: not a git repository` e sai **2**, sem criar nada;
   - se o workdir está dentro de um repositório mas **não é a raiz** dele
     (`git -C <workdir> rev-parse --show-toplevel` diferente do workdir),
     imprime `wip snapshot: workdir is not the repository root` e sai **2** —
     a restauração posterior é escopada ao workdir, e uma snapshot do
     repositório inteiro não é escopável;
   - se a árvore de trabalho está limpa (nada modificado, nada não
     rastreado), imprime `wip snapshot: nothing to snapshot` e sai **0**
     **sem criar a ref** — quem chama decide pelo que a ref existe;
   - se não há HEAD (repositório sem commit), a árvore base é
     `git hash-object -t tree /dev/null` em vez de `HEAD`;
   - a árvore é montada com **índice de rascunho fora do workdir**: arquivo
     temporário criado com `mktemp` e **removido** antes do uso (um índice de
     zero byte faz o git recusar), `GIT_INDEX_FILE` apontando para ele,
     `git read-tree <base>`, `git add -A`, `git write-tree`; o arquivo
     temporário é removido ao final, inclusive em falha;
   - o commit é criado com identidade **explícita** (não a do usuário):
     `git -c user.email=llms.surf@localhost -c user.name=llms.surf
     commit-tree <tree> -p <base-commit> -m "llms.surf: wip run=<run_id>
     iter=<iter>"`; se não houver commit base (repositório sem commit), o
     `-p` é omitido;
   - a ref `refs/llms-surf/wip/<run_id>/iter-<iter>` é criada com
     `git update-ref` (com o sha que veio do commit-tree, e **não** com
     `HEAD`);
   - imprime o sha do commit e sai **0**.
   O HEAD, o índice real e a árvore de trabalho **não** podem mudar: o teste
   prova isso.

   **`oracfit_wip_restore <workdir> <ref> <path> [<path> …]`** — restaura os
   caminhos listados a partir do ref:
   - caminho que casa com os globs protegidos é **recusado**: nada é restaurado,
     o caminho é listado na saída e o comando sai **3**; os globs protegidos
     são os de `core/protected-paths-default.txt` quando o workdir **é** este
     checkout, ou de `<workdir>/.oracfit-protected` quando esse arquivo
     existir — nos dois casos, se nenhum dos dois existir, o conjunto protegido
     é `<workdir>/.dispatch/**` e nada mais;
   - caminho que está dentro de `<workdir>/.dispatch/` é **recusado**;
   - a restauração usa `git checkout <ref> -- <path>` (o `HEAD` não se move);
     a restauração **não apaga** arquivo nenhum: arquivo criado pelo agente e
     não rastreado continua existindo, e arquivo rastreado que não existe no
     ref **não** é apagado — no máximo o comando avisa e sai 3;
   - um caminho que não existe no ref é erro: a mensagem diz
     `wip restore: path not in ref: <path>` e a saída é **3**;
   - com pelo menos um caminho restaurado, a saída é **0**.

   **Escopo dos globs protegidos**: os globs casam com o caminho **relativo à
   raiz do workdir**, com o mesmo `fnmatch` do bash que o `bin/dispatch-mode.sh`
   usa (`*` cruza `/`), exatamente como o arquivo
   `core/protected-paths-default.txt` diz no cabeçalho.

   **A cicatriz** — uma quarta função,
   **`oracfit_wip_scar_line <run_id> <iter> <ref_path>`** — imprime **uma
   linha**, em inglês, com este formato:

   ```
   [SUPERVISOR]: your attempt <iter> degraded the tree without reducing the errors. The state was saved in <ref_path>. The out-of-scope files were restored to the last clean checkpoint. Do not repeat this approach.
   ```

   A função **não** verifica nada e **não** injeta nada: ela formata. A
   injeção na spec é o rung do matcher (rung D), e a chamada ao reset a partir
   de uma decisão do modelo é o rung do modelo de decisão.

2. `tests/test-wip-snapshot.sh` (bash, hermético: repositório git temporário em
   `$TMPDIR`, sem rede, sem modelo, sem tocar em nenhum repositório real). Ele
   prova:
   - **snapshot pega a deriva**: repo de teste com um commit, um arquivo
     rastreado editado e um arquivo novo não rastreado; depois do
     `oracfit_wip_snapshot`, a árvore do commit da ref contém o **conteúdo
     editado** do arquivo rastreado **e** o arquivo novo;
   - **nada se move**: o `HEAD` é o mesmo sha de antes, `git status
     --porcelain` é idêntico antes e depois, e o índice real não mudou (o
     arquivo rastreado continua modificado na árvore de trabalho);
   - **o nome da ref**: existe `refs/llms-surf/wip/<run>/iter-<n>` e a mensagem
     do commit contém o run id e a iteração;
   - **árvore limpa**: com a árvore limpa, a snapshot imprime
     `nothing to snapshot`, sai 0 e **não** cria a ref;
   - **não é repositório**: num diretório que não é repo, a snapshot imprime
     `not a git repository` e sai 2;
   - **workdir que não é a raiz do repo**: num subdiretório de um repositório, a
     snapshot imprime `workdir is not the repository root` e sai 2;
   - **restauração escopada**: depois de modificar ainda mais um arquivo
     rastreado, `oracfit_wip_restore` com um caminho devolve o conteúdo do ref
     **só** nesse caminho, e o outro arquivo continua modificado;
   - **zona protegida é recusada**: um caminho que casa com `core/*` (no workdir
     do próprio repo, com `.oracfit-protected` presente) é recusado, sai 3, e o
     arquivo **não** é tocado;
   - **`.dispatch/` é recusado**: um caminho dentro de `.dispatch/` é recusado
     com a mesma saída;
   - **nada é apagado**: um arquivo não rastreado criado pelo agente continua
     existindo depois de um restore;
   - **a cicatriz**: `oracfit_wip_scar_line` imprime uma linha só, com o texto
     `[SUPERVISOR]:` e o caminho da ref dentro dela.
   O teste imprime no final `test-wip-snapshot: N passed, M failed` e sai
   diferente de zero quando M > 0.

3. Nenhuma chamada a estas funções é feita por nenhum runtime neste rung.
   `grep -rn "oracfit_wip" bin/` só pode mostrar a própria biblioteca e o teste.

## Verificação

```bash
bash tests/test-wip-snapshot.sh && grep -q "refs/llms-surf/wip" bin/oracfit-wip-snapshot.sh
```

## Oráculo

- comando: test -f tests/test-wip-snapshot.sh && bash tests/test-wip-snapshot.sh
- exit esperado: 0

## Barra

- nome: tests/test-wip-snapshot.sh
- como fetchar: bash tests/test-wip-snapshot.sh
- como comparar: ORACLE VERDE — a suíte imprime "test-wip-snapshot: N passed, 0 failed" e sai 0

Nao invente numero, prazo, citacao ou fonte alem dos listados acima.
NUNCA use declare const como workaround — importe de verdade.
