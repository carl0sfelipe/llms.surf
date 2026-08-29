# Ficha — syntax custom de modo (D3: subconjunto do loader, zero schema novo)

> Ordem de trabalho do go-live, não produto. Entra no PRIVATE_DIRS do
> publish-cut antes do próximo corte (D8).

**Decisão D3 em uma linha:** a syntax custom de modo não é uma gramática nova —
é um SUBCONJUNTO documentado do loader que já existe
(`bin/lib-oracfit-mode-loader.py`). Zero mudança de schema, zero parser novo,
zero superfície de ataque nova. Quem escreve `core/modes/meu-modo.yaml` no
workdir está usando o mesmo contrato que os 20 modos do tree usam.

## A gramática do subconjunto (1ª onda)

```yaml
id: meu_modo              # [a-z0-9_]+ — TEM que bater com o nome do arquivo
version: "1"
name: Meu modo            # linha de exibição
description: >            # campo de MÁQUINA: lint procura claims aqui (ver abaixo)
  O que o modo faz, uma frase.
stages:
  - role: run             # run é o papel do subconjunto (unlock/plan/map/reduce
    model_ref: tier:cheap #   existem no loader; entram em ficha própria)
    oracle: true          # o oráculo vem da SPEC da task, não daqui
    max_attempts: 3
    rate_limit_s: 2       # opcional — segundos entre chamadas
on_fail: halt             # pare quando o oráculo não fecha
```

Campos do loader **fora** do subconjunto da 1ª onda (existem, não entram na
ficha: `preflight`, `gauntlet`, `publish`, `run_attempt_budget`, `command`,
`json_schema`, `input`, `prompt_template`, `tools`, `loop_target`,
`stage_oracle`, `freshness_targets`). Nada te impede de usá-los — o loader
aceita — mas a ficha não promete o que não foi ensaiado (lição demiurgo:
mentir a classe da proteção é incidente).

## As três regras que a ficha ensina junto

**1. O oráculo vive na spec da task, não no YAML (D4).** O modo diz COMO trabalhar
(modelo, tentativas, limite); a spec da task diz O QUE É PRONTO, na seção
`## Oráculo` — comando cru, **sem crase** (regra 46: crase na linha
`- comando:` vira substituição no eval e mata o run com exit 127 fantasma).
O YAML com `oracle: true` só declara que a spec vai ser julgada por um
comando no disco.

**2. Privacidade é localização, não campo (D5).** Não existe campo `private:`
nem `secret:`. O que torna um modo privado é ONDE ele mora: `core/modes/` do
SEU workdir nunca sai da sua máquina. Público é só o que VOCÊ postar —
`oracfit mode share <id>` imprime o YAML pronto para colar numa issue, e
`oracfit mode add <arquivo.yaml>` instala o YAML de outra pessoa no seu
overlay do workdir, depois de validar e lintar com o MESMO loader que o `run`
usa. Antes de postar: segredo nenhum dentro do YAML (chave mora em env;
`model_ref` referencia tier ou id de modelo, nunca credencial).

**3. Claim sem mecanismo não registra (o lint cobra).** A `description` é
campo de máquina: palavras como "watchdog", "ledger", "gate visual",
"mecânico" disparam exigência de `# mecanismo(<classe>): <caminho>` apontando
para executável que EXISTE. Foi o lint que reprovou a primeira versão dos
exemplos desta ficha ("ledger" na description, classe ring sem mecanismo) —
o gate funciona; a ficha existe para você não pagar o mesmo pedágio.

## Os dois exemplos que acompanham (validam e lintam neste tree)

| arquivo | ensina |
|---|---|
| `examples/glassy.yaml` | o mínimo viável: 1 stage run, tier cheap, oráculo na spec |
| `examples/outside_set.yaml` | mini-tow de 2 stages: unlock caro + run barato com `input: prev_stage` (a composição entre stages) |

Prova (roda em qualquer checkout deste corte):

    python3 bin/lib-oracfit-mode-loader.py validate examples/glassy.yaml
    python3 bin/lib-oracfit-mode-loader.py lint    examples/glassy.yaml
    python3 bin/lib-oracfit-mode-loader.py validate examples/outside_set.yaml
    python3 bin/lib-oracfit-mode-loader.py lint    examples/outside_set.yaml

## Ciclo completo de um modo custom (o caminho do estranho viciado)

    oracfit mode init meu_modo        # scaffold honesto no SEU workdir
    $EDITOR core/modes/meu_modo.yaml  # subconjunto acima
    oracfit mode validate meu_modo    # schema
    oracfit mode lint meu_modo        # claims → mecanismos + shadow de id
    oracfit run meu_modo spec.md t1   # o run resolve workdir → root (AD-16)
    oracfit mode share meu_modo       # quando valer a pena, poste

Validação por baixo dos panos é literalmente o mesmo binário do `run`
(`dispatch-mode.sh` chama `validate` antes de qualquer modelo) — o que você
valida é o que roda. Sem drift entre "o YAML que passou no check" e "o YAML
que o runtime leu", porque são a mesma leitura.

## Por que subset e não DSL nova

- **Schema zero-mudança:** todo YAML da ficha já é aceito hoje; todo modo dos
  20 do tree continua válido. Nada de migração, nada de feature flag.
- **Um só loader:** colisão de id, shadow de workdir, claim sem mecanismo —
  os incidentes que viraram lint valem igual para modo custom e modo nativo,
  porque passam pelo mesmo código.
- **Superfície de confiança:** "mode share" circula YAML, e YAML só é
  executável como configuração do MESMO schema auditado — não como script.
