# S4 — mode share / mode add (público = postar o próprio YAML)

Decisão D5: privacidade é localização, não campo. Não existe `private:` no
schema — um modo é privado porque mora no `core/modes/` do SEU workdir; público
é exclusivamente o YAML que você postar. Esta story implementa as duas portas
dessa fronteira: `mode share` (saída — imprime o YAML pronto para postar) e
`mode add` (entrada — instala YAML de terceiro no overlay do workdir, depois
de validar e lintar com o MESMO loader do `run`).

## O que fazer

Estado exigido (implementado; oráculo abaixo é gate permanente):

1. `oracfit mode add <arquivo.yaml>`: validate → lint → instala em
   `$ORACFIT_WORKDIR/core/modes/<id>.yaml`. Recusa id inválido, YAML que não
   passa no loader, e sobrescrita de modo existente com conteúdo diferente
   (colisão hefesto). Re-add idêntico é idempotente.
2. `oracfit mode share <id>`: resolve o modo (workdir primeiro, depois root),
   imprime o cabeçalho com o destino do post (template de issue
   share-your-break) e o YAML inteiro. Zero rede: postar é ato humano.
3. Os templates de issue existem: `.github/ISSUE_TEMPLATE/share-your-break.md`
   e `.github/ISSUE_TEMPLATE/tokens-waitlist.md` (veículo da waitlist — D9).

## Regras

Nao invente numero, prazo ou fonte alem dos listados. Nao use declare const
como workaround — o que prova esta story é round-trip real (add instala
arquivo no disco), não texto de help.

## Dados verificados

- Existe `bin/oracfit` neste tree.
- Existe `examples/glassy.yaml` neste tree.
- Existe `.github/ISSUE_TEMPLATE/share-your-break.md` neste tree.
- Existe `.github/ISSUE_TEMPLATE/tokens-waitlist.md` neste tree.

## Verificação

Round-trip completo em workdir temporário (instala, idempotente, compartilha):

VERIFICACAO: T=$(mktemp -d) && ORACFIT_WORKDIR=$T bin/oracfit mode add examples/glassy.yaml && test -f $T/core/modes/glassy.yaml && rm -rf $T

## Oráculo

- comando: T=$(mktemp -d) && ORACFIT_WORKDIR=$T bin/oracfit mode add examples/glassy.yaml && test -f $T/core/modes/glassy.yaml && ORACFIT_WORKDIR=$T bin/oracfit mode share glassy > $T/share.txt && grep -q "mode share" $T/share.txt && test -f .github/ISSUE_TEMPLATE/share-your-break.md && test -f .github/ISSUE_TEMPLATE/tokens-waitlist.md && rm -rf $T
- exit esperado: 0 — o modo de exemplo instala no overlay de um workdir
  estranho, compartilha com o cabeçalho do post, e os dois templates de issue
  existem no repo.

## Barra

docs/go-live/CUSTOM-MODE-CARD.md seção "Privacidade é localização" — é a
referência nomeada da fronteira pública/privado desta story.
