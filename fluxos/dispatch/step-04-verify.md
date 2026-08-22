# Step 4: Verify

## REGRAS

- Exit 0 do dispatch NÃO é prova de trabalho feito. Verifique por `git diff`.
- Máximo de 3 tentativas. Depois disso, bloqueie.
- Incremente `tentativas` no artefato a cada tentativa frustrada antes de decidir.
- Você NUNCA reescreve o entregável. Você instrui o executor a corrigir.

## INSTRUÇÕES

### 1. Pré-condição

Confirme que o artefato em `$DISPATCH_ARTEFATO` existe e está com `status: in-review`. Se não estiver, **EARLY EXIT** → `./step-01-route.md`.

### 2. Verificar evidência de trabalho

Rode `git diff` para verificar se houve alterações no repositório desde o início do fluxo:

```bash
git diff --stat HEAD
```

Se houver alterações (arquivos modificados, adicionados ou removidos), prossiga para o passo 3.

Se NÃO houver alterações, o dispatch foi um no-op silencioso: o modelo encerrou limpo sem produzir nada. Prossiga para o passo 4 com o motivo `sem alterações detectadas por git diff`.

**Por que não confiar no exit code:** um dispatch já saiu com exit 0 tendo parado no primeiro step sem escrever um byte. Evidência é diff, contagem ou hash — nunca exit code. Incidente: `incidents/2026-07-25-dispatch-saiu-com-exit-0-sem-fazer-nada-.md`.

### 3. Conferir o conteúdo contra o objetivo

Houve diff, mas diff não é acerto. Rode o comando de verificação declarado na spec (seção `## Objetivo` do artefato) e confira:

- Os caminhos alterados são os que a spec pediu?
- O comando de verificação passa?
- Há número, prazo, preço, nome de produto ou citação de fonte que **não** estava no bloco de dados verificados da spec?

Se quiser rastrear invenção numérica no output:

```bash
bin/check-output-invencao.sh "$DISPATCH_ARTEFATO" <arquivo_gerado>
```

Se estiver tudo certo, prossiga para o passo 5.

Se estiver errado, prossiga para o passo 4 com o motivo descrito.

### 4. Reexecutar ou refinar

Leia o campo `tentativas` do frontmatter do artefato. Incremente em 1 e grave.

Se `tentativas >= 3`:
- Atualize `status: blocked` no artefato.
- Atualize `bloqueio: 3 tentativas sem resultado aceito — <motivo>`.
- HALT com status `blocked`.

Se `tentativas < 3`, **reescreva a seção `## Objetivo` do artefato como refinamento**, nunca como spec nova e nunca corrigindo o arquivo você mesmo. O refinamento tem três blocos, e só os que se aplicam:

```
DELETE:
- <seção ou trecho> — <motivo>

REESCREVA:
- <seção> — está errado porque <motivo>. O correto é: <dado real, verificado por você>

ADICIONE:
- <o que falta> — <onde exatamente>
```

Regras do refinamento:

- Cite o dado **verificado**, não a suspeita: "conferi e o caminho é `bin/run-check.sh`", não "acho que é".
- 10–20 linhas no máximo. Refinamento longo vira spec nova e o executor recomeça do zero.
- Um arquivo por refinamento. Refinamento em bulk não converge.
- Modelo free falha com frequência ao **modificar arquivo existente com contexto**, e vai bem ao criar arquivo novo. Se dois refinamentos seguidos não pegarem, considere pedir o arquivo inteiro reescrito em vez de emendas.

Depois de gravar o refinamento:

- Acrescente à seção `## Resultado`: `Tentativa ${tentativas}: <motivo>. Refinamento despachado.`
- Atualize `status: ready` no artefato.
- **EARLY EXIT** → `./step-03-execute.md`

### 5. Marcar done

Atualize o frontmatter do artefato:
- `status: done`
- Preencha `evidencia` com o caminho do log de dispatch ou um resumo do `git diff --stat`

Grave em disco.

HALT com status `done`.

## NEXT

Este passo sempre termina em HALT ou EARLY EXIT. Nenhuma transição padrão.
