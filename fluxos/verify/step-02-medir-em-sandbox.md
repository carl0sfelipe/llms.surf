# Step 2: Medir em Sandbox

## REGRAS

- A medição roda em sandbox (`mktemp -d`), fora do repositório.
- Use `--write` apenas no passo 3 após ler e aprovar o dry-run.
- `suite_accuracy` igual a 0.0 é tratado como suspeita de defeito do harness, não como resultado válido.
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.

## Pré-condição

Leia o artefato. Confirme que `status: in-progress` e `modelo` está preenchido com o id do alvo.

## INSTRUÇÕES

### 1. Rodar medição em dry-run

Execute a medição sem o flag `--write` para evitar contaminação do registry:

```bash
bin/verify-models.sh "<modelo>"
```

Ou, se a intenção for verificar todos os modelos:

```bash
bin/verify-models.sh --all
```

Interprete o exit code:

| Exit | Significado | Ação |
|------|-------------|------|
| 0 | OK | Prossiga para o passo 2 |
| 1 | Modelo falhou | HALT com status `blocked` e bloqueio `verify-models.sh falhou (exit 1) — modelo não respondeu` |
| 3 | Erro de uso | HALT com status `blocked` e bloqueio `verify-models.sh: erro de uso — argumentos inválidos` |

### 2. Ler o resultado da medição

A saída do dry-run imprime os valores medidos. Capture:

- `suite_accuracy`: fração de acertos (0.0 a 1.0)
- `latency_ms`: latência medida
- `context_tokens`: resultado do needle-in-haystack (se foi solicitado)
- `verified_at`: timestamp da medição

Grave a saída completa no campo `evidencia` do artefato.

### 3. Verificar integridade do resultado

Se `suite_accuracy` for exatamente 0.0:

> **Regra 25:** zero absoluto é suspeita de bug de harness, não medição. `bin/verify-models.sh` recusa gravar 0.0 sem `--force`.

Neste caso, **não prossiga para o passo 3**. HALT com status `blocked` e bloqueio `suite_accuracy=0.0 — suspeita de defeito do harness. Investigar core/verify-suite.json antes de tentar novamente. Para gravar mesmo assim, use o flag --force.`

Se `suite_accuracy` for maior que 0.0, prossiga.

## NEXT

Leia integralmente e siga `./step-03-gravar-com-dry-run.md`.
