---
id: 2026-09-19-runner-zcode-reescreve-config-global-do-dono
titulo: runner zcode reescreve ~/.zcode/cli/config.json global do dono em todo despacho
data: 2026-09-19
recorrivel: sim
regra: nao — correção exige decisão (sem flag nativa de modelo na CLI zcode; escopo workdir não medido); ver "Correção em aberto"
status: aberto
interage_com: "kernel/test-specs/DECISIONS-wave1-2.md D-DISPATCH item 3 (promoção desta página; 'severity high: it touches the owner's machine')"
interage_com: "adapters/zcode/DISCOVERY.md (2026-08-04, v0.15.2: 'Sem --model no CLI. Modelo vem de ~/.zcode/cli/config.json')"
interage_com: "2026-08-12-runner-herda-cwd-do-lancador-modelo-desp.md (mesma família: efeito do runner vaza fora do workdir do despacho)"
interage_com: "2026-08-13-ring-ledger-central-dividido-por-env-herdado-de-shell.md (classe: estado global do host colidido por execuções concorrentes)"
---

# runner zcode reescreve ~/.zcode/cli/config.json global do dono em todo despacho

Promovido de `kernel/test-specs/DECISIONS-wave1-2.md` (D-DISPATCH item 3,
2026-09-19): "Runner rewrites `~/.zcode/cli/config.json` → **bug**; scope
the write to the workdir or a flag. Incident + regression test in the shell
suite. This one is severity high: it touches the owner's machine." Registrado
com **halt de correção** no mesmo turno: a direção decidida ("workdir ou
flag") foi verificada e o caminho que preserva a função **não existe hoje na
CLI** — não inventar mecanismo (cláusula anti-invenção). Correção virou
decisão em aberto, ver seção própria.

## Sintoma

Toda execução de despacho pelo adapter zcode (`adapters/zcode/runner.sh`)
reescreve a config GLOBAL da CLI no host do dono
(`~/.zcode/cli/config.json`, default de `ZCODE_CLI_CONFIG`), trocando
`model.main` para o modelo do despacho e podendo inserir entradas no bloco
`provider` que o dono não configurou. Efeito colateral: a TUI/sessões do
dono passam a rodar no último modelo despachado, e despachos concorrentes
brigam pelo mesmo arquivo (último vence).

EVIDÊNCIA (código, `adapters/zcode/runner.sh`):

- linha 97: `ZCODE_CLI_CONFIG="${ZCODE_CLI_CONFIG:-$HOME/.zcode/cli/config.json}"`
  — default aponta para a config global; nenhum chamador
  (`bin/dispatch.sh`, `bin/dispatch-mode.sh`, `bin/run-with-fallback.sh`)
  define a variável para outro lugar, e o único outro ponto do repo que a
  define, `adapters/zcode/env.sh:40`, exporta o MESMO default global — o
  opt-in nunca acontece na prática;
- linhas 98–147: bloco Python que abre a config, força `model.main` = hint
  resolvido do registry, garante/altera `provider.<id>` e grava de volta
  (`path.write_text(...)` na linha 147) — incondicional, antes de qualquer
  chamada da CLI;
- linhas 149–151 e 155–169: o preflight de apiKey LÊ a mesma config logo
  depois — a escrita acontece mesmo se o despacho depois recusa (exit 3 sem
  apiKey).

Reprodução MEDIDA 2026-09-19 (segura: `HOME` isolado em scratch +
`ZCODE_BIN` falso que só registra argv e sai 0 + registry de scratch via
`MODEL_REGISTRY`; sha256 da config REAL do dono igual antes/depois do
repro — nenhum token gasto, nada na máquina tocado):

```
$ env HOME=$SCRATCH/home ZCODE_BIN=$SCRATCH/fake-zcode ZCODE_API_KEY=bait \
    MODEL_REGISTRY=$SCRATCH/registry.json \
    bash adapters/zcode/runner.sh dummy-model $SCRATCH/spec.md
# runner exit=0; binário falso chamado; e no HOME isolado SURGIU:

$ cat $SCRATCH/home/.zcode/cli/config.json
{
  "model": { "main": "zai/glm-5.1" },
  "provider": { "zai": { "kind": "openai-compatible", "options": {} } }
}

$ cat $SCRATCH/argv.log   # o que a CLI recebeu
--prompt / --mode yolo / --cwd <cwd> / --json
# NÃO existe --model: o modelo chega à CLI EXCLUSIVAMENTE via o arquivo acima.
```

Ou seja: no uso real, o HOME não é isolado — o arquivo criado/atualizado é
exatamente `~/.zcode/cli/config.json` do dono.

### Agravantes medidos no mesmo repro

A. **Normalização estrita derruba chaves do dono no bloco `model`** (linha
   118 do runner: só sobrevivem `main` e `lite`). Config válida do usuário
   com `model: {main, lite, customPin}` após um despacho:

```
antes: "model": { "main": "zai/glm-5.1", "lite": "zai/glm-4.7", "customPin": "meu-modelo-favorito" }
depois: "model": { "main": "zai/glm-5.1", "lite": "zai/glm-4.7" }   # customPin PERDIDO
```

B. **Config ilegível é descartada em silêncio** (linhas 105–108: exceção no
   `json.loads` → `cfg = {}`; 109–110: não-dict também → `cfg = {}`; o
   write da linha 147 devolve só `model`+`provider`). Arquivo
   troncato (ex.: escrita concorrente interrompida) com a apiKey do dono:

```
antes: { "model": ..., "provider": { "zai": { "options": { "apiKey": "sk-unico-do-dono" } } } }, "trunc
depois: { "model": { "main": "zai/glm-5.1" }, "provider": { "zai": { "kind": "openai-compatible", "options": {} } } }
# apiKey do dono PERDIDA; runner exit=0 (o wipe não é reportado)
```

C. **Corrida**: dois despachos zcode com modelos diferentes (ex. via
   `bin/parallel-dispatch.sh`) escrevem o MESMO arquivo global — o
   `model.main` final é o último a gravar, e a leitura+escrita não é
   atômica (janela do agravante B).

## Causa

A CLI zcode não tem flag de modelo. DISCOVERY (`adapters/zcode/DISCOVERY.md`,
2026-08-04, v0.15.2), linhas 26 e 29:

```
Slash: /model [list|main|lite|provider/model]  /fork ...
**Sem `--model` no CLI.** Modelo vem de `~/.zcode/cli/config.json`
```

Re-verificado 2026-09-19 no binário instalado (wrapper em
`~/.local/bin/zcode` → AppImage extraído, bundle `resources/glm/zcode.cjs`,
versão de runtime 3.11.2): o texto de help embutido do CLI lista TODAS as
opções e `--model` não existe (`--prompt`, `--mode`, `--resume`, `--cwd`,
`--settings`, `--max-turns`, ...; modelo continua sendo slash `/model [id]`
de sessão); as únicas ocorrências da string `--model` no bundle são tabelas
de completion de ferramentas de terceiros embutidas (django-admin, pac
powerpages etc.); o path da config é constante do bundle: `~/.zcode/cli` +
`config.json` (a própria mensagem de erro do CLI manda criar
`~/.zcode/cli/config.json`).

O contrato do runner (`core/runner-contract.md`) exige rodar o modelo
resolvido do registry. Sem flag, a ÚNICA alavanca disponível é a config
global — o runner fez o único caminho que funcionava. O bug não é a escrita
em si; é o ESCOPO do efeito colateral (máquina do dono, fora do workdir do
despacho).

Medição 2026-09-19 (máquina do dono, `adapters/zcode/measure-home-relocation.sh`):

```
HOME relocado: não
XDG_CONFIG_HOME: não
--user-data-dir: não
```

## Correção em aberto — exige decisão (halt do D-DISPATCH)

Direção decidida: "scope the write to the workdir or a flag". Verificação
2026-09-19, caminho mínimo que preserva a função:

1. **Flag nativa `--model`: NÃO EXISTE.** Medido no DISCOVERY (v0.15.2) e
   estáticamente no bundle atual 3.11.2 (help completo sem `--model`; ver
   Causa). Logo o plano "runner passa o modelo por flag e só escreve config
   em opt-in (`ZCODE_CLI_CONFIG` definido EXPLICITAMENTE pelo chamador)"
   está **bloqueado na CLI atual** — exigiria flag nova upstream no zcode.
2. **Escopo workdir: não medido.** A config é ancorada em `$HOME`; nenhum
   `--cwd` muda lookup de config por evidência estática (e medir exige
   rodar a CLI real = gastar token do dono — fora de questão neste turno).
   Leads estáticos que o decisor deve medir com a CLI real (nenhum
   verificado; NÃO apostar código neles):
   - `--settings <path>` ("Load user config from a specific settings file"
     no help atual): se aceitar arquivo com forma de cli config
     (`model`+`provider`) e SUBSTITUIR a lookup global do modelo, o runner
     passa escrever o config no workdir e chamar com `--settings` — global
     intocada, função preservada. É o candidato mais forte.
   - `.zcode/config.json` de workspace existe no bundle, mas o contexto
     estático indica escopo de PLUGINS (marketplace), não model/provider —
     confirmar.
   - Envs `ZCODE_HOME` / `ZCODE_DATA_BASE_DIR` / `ZCODE_STORAGE_DIR`
     aparecem no bundle; a leitura estática de `ZCODE_HOME` só mostrou uso
     em telemetria. Verificar se alguma redireciona a lookup de
     `cli/config.json`.
3. **Enquanto isso, o runner NÃO foi mexido.** Remover a escrita sem
   substituto quebra a função: o despacho rodaria no `model.main` que
   estiver na global (modelo errado em silêncio — pior que o bug atual,
   que é alto mas visível). Meio-termo sem substituto seria inventar
   mecanismo.
4. **Teste de regressão**: spec pronta, implementar JUNTO com a correção
   decidida — snapshot de `~/.zcode/cli/config.json` sob `HOME` isolado
   (mecânica já provada no repro acima), `ZCODE_BIN` falso que registra
   argv e sai 0, assertion dupla: (a) config global NÃO modificada e
   (b) o modelo resolvido chega à CLI (no mundo com flag: presente no
   argv; no mundo `--settings`: caminho scoped no argv + arquivo com
   `model.main` certo). Sem correção, o teste é vermelho para sempre — e
   gate permanentemente vermelho ou gate neutro que mente verde são os dois
   anti-padrões que este diário já executou. Por isso ele não entra na suíte
   neste turno.

## Pode acontecer de novo?

Sim — todo despacho zcode reescreve a config global, agora mesmo. Status
aberto até uma de: (i) flag `--model` upstream na CLI zcode; (ii)
`--settings` medido e adotado como config scoped no workdir; (iii) env de
redirecionamento de config medida. Quem retomar: medir os 3 leads do item 2
com a CLI real (gasta token — pedir aval do dono), escolher o caminho,
só então implementar runner + teste de regressão das duas direções.
