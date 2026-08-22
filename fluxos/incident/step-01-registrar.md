# Step 1: Registrar

## REGRAS

- Este passo NÃO classifica nem implementa. Ele registra o incidente e coleta as informações mínimas.
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.

## INSTRUÇÕES

### 1. Criar o artefato do fluxo

1. Copie o template de `fluxos/_comum/artefato-template.md` para `.dispatch/artefatos/incident-<YYYY-MM-DD>.md`.
2. Gere um `id` no formato `incident-<YYYY-MM-DD>`.
3. Defina `status: in-progress` e `owner: "incident"`.
4. Grave em disco.

### 2. Identificar o título

O título do incidente deve ser uma descrição direta e curta do que aconteceu — evite interpretação. Exemplos:

- `"dispatch travou sem output"`
- `"suite_accuracy 0.0 para modelo conhecido"`
- `"gate não bloqueou agente concorrente"`

O título será usado como argumento para `bin/incident.sh new`.

### 3. Registrar o incidente

```bash
bin/incident.sh new "<titulo>"
```

Isso cria o arquivo do incidente a partir do template em `incidents/<data>-<slug>.md`.

### 4. Preencher evidência

Edite o arquivo do incidente recém-criado em `incidents/`. Preencha as três seções obrigatórias:

- **Sintoma:** o que foi observado (saída, log, erro)
- **Causa (com evidência):** o que causou o problema — exija evidência, não plausibilidade. Se a causa não for determinada, escreva `causa: não determinada`.
- **Correção aplicada:** o que foi feito para resolver

Não se esqueça do campo `recorrivel` no frontmatter: `sim`, `nao` ou `?`.

### 5. Registrar no artefato do fluxo

Atualize o artefato do fluxo:
- `evidencia`: caminho do incidente criado (no formato `incidents/<data>-<slug-do-titulo>.md`, gerado pelo próprio `bin/incident.sh new`)
- Grave em disco

## NEXT

Leia integralmente e siga `./step-02-classificar.md`.
