# Step 2: Antes do Provider

## REGRAS

- Chegou aqui porque **nenhuma sessão foi criada no banco**. O dispatch travou antes de sequer falar com o provider.
- Você vai investigar causas conhecidas em ordem fixa. Na primeira causa confirmada, HALT com a conclusão.

## INSTRUÇÕES

### 1. Carregar estado

Leia o artefato apontado por `$DISPATCH_ARTEFATO`. Confirme que `status: in-progress`.

### 2. Verificar agente concorrente

Dois agentes no mesmo repositório contendem e penduram o dispatch — inclusive quando o segundo "agente" é o usuário com a TUI do CLI aberta, que o gate também detecta. Incidente: `incidents/2026-07-24-travamento-silencioso.md` e `incidents/2026-07-24-gate-nao-via-tui-do-opencode.md`. Rode:

```bash
bin/pre-dispatch-check.sh opencode_go
```

Interprete o exit code:

| Exit | Significado | Ação |
|------|-------------|------|
| 0 | GO — sem concorrência | Prossiga para o passo 3 |
| 1 | WAIT — agente concorrente ativo | **HALT** com `conclusao: agente-concorrente`, `bloqueio: "pre-dispatch-check.sh detectou agente concorrente — dois agentes no mesmo repo travam o dispatch"` |
| 2 | SWITCH | Prossiga para o passo 3 (troca de provider não é relevante aqui) |
| 4 | EXHAUSTED | Prossiga para o passo 3 |

**Importante:** a saída WAIT já confirma a causa. Registre a evidência no artefato (copie a mensagem do gate).

### 3. Verificar processos órfãos

Processos do dispatch órfãos de um teto anterior podem consumir o lock. A seção 2 da saída de `bin/diagnose-hang.sh` já mostra isso. Releia a saída:

- Se "órfãos" > 0: **HALT** com `conclusao: processo-orfao`, `bloqueio: "processos órfãos do dispatch encontrados — %d processo(s) vivo(s)"` (preencha o número)
- Se "zero órfãos": prossiga

### 4. Verificar id do modelo no catálogo

Um id de modelo que não existe no catálogo real **pendura em vez de dar 404**, imitando rate limit. Incidente: `incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md`. Rode:

```bash
bin/audit-registry-ids.sh
```

Interprete a saída:

| Resultado | Significado | Ação |
|-----------|-------------|------|
| "FANTASMA" para algum modelo | Id de modelo que não existe em catálogo nenhum | **HALT** com `conclusao: modelo-fantasma`, `bloqueio: "audit-registry-ids.sh reporta modelo(s) FANTASMA — id(s) sem correspondência em catálogo"` |
| "NAO-ENCONTRADO" para algum modelo | Não encontrado, mas pode ser provider sem catálogo público | Registre como evidência, mas não HALT ainda — pode ser falso positivo |
| Exit 0 (tudo OK) | Nenhum problema de catálogo | Prossiga |

### 5. Separar runtime quebrado de provider fora

O runtime agêntico é **ponto único de falha**: todo dispatch passa por ele, e quando ele trava (após `init`, sem erro em lugar nenhum) o framework inteiro para — com providers, credenciais e rede íntegros. Runtime quebrado imita modelo indisponível.

Antes de concluir que um modelo ou provider está fora, **prove o acesso por HTTP direto ao endpoint do provider**, fora do CLI, e sempre dentro de `bin/with-timeout.sh <segs>` para não trocar um travamento por outro.

- Endpoint responde: o provider está de pé, a causa é o runtime. **HALT** com `conclusao: runtime-agentico-travado`, `bloqueio: "endpoint do provider responde por HTTP direto; travamento é do runtime agêntico, não do provider"`.
- Endpoint não responde: o problema é do provider ou da credencial. Registre a evidência e prossiga.

Incidente: `incidents/2026-07-25-opencode-trava-apos-init-para-todos-os-p.md`.

### 6. Conclusão: não determinado

Se nenhuma causa foi encontrada, o travamento antes do provider requer investigação mais profunda (rede, estado do opencode, permissões). Faça HALT com:

- `conclusao: nao-determinado`
- `bloqueio: "nenhuma causa conhecida identificada — investigar rede, estado do opencode e permissões"`
- Inclua a saída completa do `diagnose-hang.sh` como evidência no artefato

## Registro no artefato

Antes de HALT, atualize o frontmatter:

- `status`: `done` (se causa encontrada) ou `blocked` (se não determinado)
- `conclusao`: a causa identificada
- `bloqueio`: descrição da causa
- `evidencia`: caminho ou saída relevante

Grave em disco.

## NEXT

Este passo termina em HALT. Nenhuma transição padrão.
