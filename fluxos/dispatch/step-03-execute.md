# Step 3: Execute

## REGRAS

- NUNCA execute o CLI diretamente. Use SEMPRE `bin/dispatch.sh` como wrapper.
- O dispatch roda em background com watchdog — você monitora, não executa inline.
- Marque o estado ANTES de iniciar e DEPOIS de terminar.

## INSTRUÇÕES

### 1. Pré-condição

Confirme que o artefato em `$DISPATCH_ARTEFATO` existe e está com `status: ready`. Se não estiver, **EARLY EXIT** → `./step-01-route.md`.

Confirme que as variáveis obrigatórias estão definidas:

```bash
echo "DISPATCH_RUNNER=$DISPATCH_RUNNER"
echo "LOG_DIR=${LOG_DIR:-NÃO DEFINIDA}"
echo "PID_DIR=${PID_DIR:-NÃO DEFINIDA}"
```

Se `LOG_DIR` ou `PID_DIR` não estiverem definidas, HALT com status `blocked` e bloqueio `env obrigatória não definida`.

### 2. Marcar in-progress

Atualize o frontmatter do artefato: `status: in-progress`. Grave em disco.

### 3. Despachar

Extraia do artefato o `modelo` e o caminho do próprio artefato como spec. Execute:

```bash
bin/dispatch.sh <modelo> "$DISPATCH_ARTEFATO" <task_name>
```

O `task_name` deve ser derivado do `id` do artefato ou de um slug do objetivo.

Anuncie a duração esperada antes de rodar (regra 14 do SKILL.md raiz). O dispatch roda em background; o script imprime o PID e os caminhos de log.

### 4. Aguardar conclusão

Monitore o log com:

```bash
bin/watch.sh <task_name>
```

O watchdog de `bin/dispatch.sh` garante que silêncio > `DISPATCH_SILENT_LIMIT` (default 300s) mata o processo. Se o watchdog matar o dispatch, `bin/dispatch.sh` atualiza o artefato para `status: blocked` automaticamente — nesse caso, HALT com o bloqueio registrado.

Se o dispatch terminar com sucesso (processo encerrado, log contém output do modelo), prossiga.

### 5. Marcar in-review

Atualize o frontmatter do artefato: `status: in-review`. Grave em disco.

## NEXT

Leia integralmente e siga `./step-04-verify.md`.
