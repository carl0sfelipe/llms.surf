# Step 2: Prepare

## REGRAS

- Você prepara o ambiente e a spec antes de executar o dispatch.
- Nenhum comando cru de CLI. Use os wrappers de `bin/`.
- Se um gate mandar esperar, HALT com o motivo — não insista.
- Cada checagem abaixo existe porque uma falha real passou por ali. O incidente está citado.

## Pré-condição

Leia o artefato apontado por `$DISPATCH_ARTEFATO`. Confirme que `status: draft` — se não for, **EARLY EXIT** → `./step-01-route.md` (o estado mudou desde o roteamento).

## INSTRUÇÕES

### 1. Preflight da config do CLI

Antes de qualquer coisa, valide a configuração local do CLI executor:

```bash
bin/check-cli-config.sh <cli>
```

Onde `<cli>` é o adapter ativo (`hermes`, `opencode`, ...). Adapter sem `preflight.sh` devolve 0 com aviso e nunca bloqueia.

Se o exit for diferente de 0, HALT com status `blocked` e bloqueio `config do CLI inválida — <mensagem>`.

**Por que aqui:** config quebrada só falha na primeira chamada real, depois de minutos gastos, e a mensagem de erro costuma nomear um modelo que não é a causa. Em 2026-07-26 o hermes acusou o modelo de compressão quando o problema era o default apontando para um servidor local fora do ar. Modelo default de CLI aponta para API remota; servidor local só entra como fallback explícito. Incidente: `incidents/2026-07-26-hermes-default-em-servidor-local-morto-d.md`.

### 2. Escrever a spec do trabalho

Preencha a seção `## Objetivo` do artefato. A spec precisa de:

- **Caminhos exatos, verificados antes de escrever.** Rode `grep`/`ls`, leia os arquivos — nunca "crie um adapter", sempre "crie `apps/backend/src/X.ts`". Caminho suposto vira arquivo no lugar errado.
- **Um arquivo alvo por unidade de trabalho.** Nada de entregável monolítico com várias stories dentro — refinamento em bulk não converge.
- **Máximo de 3–4 arquivos** por dispatch quando o executor for modelo free.
- **Bloco de dados verificados**: liste explicitamente os números, prazos, nomes e fontes que o executor pode usar, e proíba qualquer outro. Campo que você não decidiu vai marcado `[A DEFINIR]`, nunca em branco — branco é preenchido por invenção, por qualquer redator.
- **Comando de verificação** que teste propriedade do conteúdo, não existência do arquivo.
- **Mensagem de commit** exata.

A seção `## Passos` lista os passos em ordem.

Se não houver informação suficiente, HALT com status `blocked` e bloqueio `spec incompleta — intenção insuficiente`.

**Antes de seguir, pergunte:** a entrada é conhecida e a transformação é mecânica? Se for, isto é **código**, não dispatch — despachar só adiciona custo e chance de campo inventado. Incidente: `incidents/2026-07-25-dispatch-saiu-com-exit-0-sem-fazer-nada-.md`.

### 3. Confirmar capacidade agêntica do runner

Se o trabalho exige ler arquivo, rodar comando ou navegar o repositório, o runner precisa de ferramentas:

```bash
grep '^TOOLS=' adapters/<cli>/capabilities.env
```

Se `TOOLS=0` e o trabalho é agêntico, HALT com status `blocked` e bloqueio `runner sem ferramentas (TOOLS=0) para trabalho agêntico`.

**Por que:** a suíte de verificação mede capacidade de **resposta** (prompts autocontidos), não capacidade **agêntica**. Um modelo local tirou 8/8 e não conseguiu abrir um arquivo. Nota alta não é permissão para qualquer trabalho. Incidente: `incidents/2026-07-25-suite-mede-capacidade-de-resposta-nao-ca.md`.

### 4. Gate de concorrência e quota

```bash
bin/pre-dispatch-check.sh opencode_go
```

Use o `provider_id` correspondente ao modelo escolhido.

| Exit | Significado | Ação |
|------|-------------|------|
| 0 | GO | Prossiga |
| 1 | WAIT | HALT com status `blocked` e bloqueio `gate: esperar — <mensagem do gate>` |
| 2 | SWITCH | Atualize `modelo` no artefato para o provider sugerido, repita o gate |
| 4 | EXHAUSTED | HALT com status `blocked` e bloqueio `gate: quota/token plan exausto — <mensagem>` |

O gate cobre concorrência (outro agente no mesmo `.git`, inclusive com a TUI do CLI aberta) e quota. Não o pule: em 2026-07-24 um dispatch ficou 52 minutos vivo sem produzir um byte porque outro agente ocupava o mesmo repositório. Incidente: `incidents/2026-07-24-travamento-silencioso.md`.

### 5. Verificar a spec antes de despachar

```bash
bin/check-spec.sh "$DISPATCH_ARTEFATO"
```

Exit 1 significa spec sem bloco de dados verificados nem cláusula anti-invenção — volte ao passo 2.

**Limite conhecido:** o script detecta **ausência** de defesa, não defesa **fraca**. Uma spec passou no check com uma cláusula estreita demais e ainda assim recebeu números inventados. Conferir o escopo da cláusula é trabalho seu. Incidente: `incidents/2026-07-26-spec-sem-clausula-anti-invencao-gera-num.md`.

### 6. Smoke test

```bash
MODEL_ID="<model_id>" bin/smoke-test.sh
```

| Exit | Significado | Ação |
|------|-------------|------|
| 0 | OK | Prossiga |
| 1 | Falhou | HALT com status `blocked` e bloqueio `smoke test falhou — modelo indisponível` |
| 2 | Lento | HALT com status `blocked` e bloqueio `smoke test: resposta lenta (>10s) — provável rate limit, espere 3min` |

### 7. Marcar como pronto

Atualize o frontmatter do artefato: `status: ready`. Grave em disco.

## NEXT

Leia integralmente e siga `./step-03-execute.md`.
