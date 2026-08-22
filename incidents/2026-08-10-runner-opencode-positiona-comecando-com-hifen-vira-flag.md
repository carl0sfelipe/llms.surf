---
id: 2026-08-10-runner-opencode-positiona-comecando-com-hifen-vira-flag
titulo: runner-opencode-positional-comecando-com-hifen-vira-flag
data: 2026-08-10
recorrivel: sim
regra: 2
status: promovido
---

# runner opencode: positional começando com `-` vira flag (frontmatter `---`)

## Sintoma

Overnight do tripcstory-mvp1: todo dispatch do mode `deepseek_direct_flash`
morria em ~1s com `runner_exit=1`, sem NENHUMA mensagem no stdout/stderr do
dispatch (apenas `attempt_finished runner_exit=1 duration_s=1.085` no
events.jsonl). O preflight inteiro passava (mode yaml, check-spec, 36 facts,
check-oracle fails-correctly) — o run começava e morria no primeiro attempt.
Reproduzido em 2 ciclos (rc=127 no chamador externo) e isolado em repro
manual do `adapters/opencode/runner.sh`.

## Causa

`runner.sh` passa o spec como positional do opencode:

```
opencode run --auto ... --model "$RESOLVED" "$(cat "$SPEC_FILE")"
```

Specs no formato `fluxos/_comum/artefato-template.md` começam com frontmatter
YAML: a primeira linha é `---`. O yargs do opencode interpreta positional
iniciado por `-` como flag desconhecida → imprime a ajuda em stderr e exita 1.
O runner joga stderr do opencode num tempfile (`ERR_F`) que o trap apaga, e o
watchdog só casa rate-limit/balance → o erro some e sobra exit 1 silencioso.

Smoke de 2026-08-09 passou despercebido porque usou mensagem curta
("responda apenas OK") — sem frontmatter. Toda spec do template é afetada.

## Correção (aplicada)

`adapters/opencode/runner.sh`: `--` antes do positional
(`${PREFIXO[@]+...} "$OPENCODE_BIN" "${ARGS[@]}" -- "$(cat "$SPEC_FILE")"`).
Verificado 2026-08-10: o mesmo spec passou a executar e o modelo trabalhou
(3 commits de polish reais no tripcstory-mvp1).

## Prevenção

1. Teste de runner/smoke DEVE usar spec com frontmatter (o formato real), não
   mensagem curta — smoke curto esconde parsing de argv.
2. `ERR_F` do runner: quando o exit não casa rate-limit/balance, emitir as
   últimas linhas do stderr no log do dispatch antes de `exit 1` (silêncio
   custou ~40min de diagnóstico). [A DEFINIR: implementar tee-condicional]
