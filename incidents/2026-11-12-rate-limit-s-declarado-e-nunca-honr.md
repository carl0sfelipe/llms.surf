---
id: 2026-11-12-rate-limit-s-declarado-e-nunca-honr
titulo: rate_limit_s declarado no modo e nunca honrado pelo runtime
data: 2026-11-12
recorrivel: sim
regra: mecanismo aplicado
status: fechado
---

# rate_limit_s declarado no modo e nunca honrado pelo runtime

## Sintoma

Um modo pode declarar um limitador de taxa e o runtime ignorá-lo:

```yaml
# core/modes/vision_catalog.yaml
  - role: map
    model_ref: tier:vision
    rate_limit_s: 15
```

Dois modos que já vêm no repositório declaram `rate_limit_s: 15` na stage de
`map`. O runtime, porém, não tinha **um único `sleep`** dentro dele: os dois
dispatchers (`bin/dispatch-stages.sh` e `bin/dispatch-mode.sh`) chamavam o
provedor em seguida, sem pausa nenhuma. O limitador existia no papel — no
loader (que o exige na stage `map`), no catálogo (que o documenta como "pause
between attempts") — e não existia no caminho de execução.

O pior: o limitador de verdade do polo de visão morava **fora** do YAML do
modo, dentro do script (`bin/dispatch-vision-map.sh`, `INTERVALO=12`), fora
do alcance de quem escreve o modo. Um modo novo escrito por outra pessoa não
tinha como pedir uma pausa: escrevia `rate_limit_s: 15` e não recebia nada.

## Causa

`rate_limit_s` entrou na gramática do modo como restrição do loader (a stage
`map` precisa dele) e como campo aceito, mas **nenhum runtime o consumia**:

```console
$ grep -c "sleep" bin/dispatch-stages.sh bin/dispatch-mode.sh
bin/dispatch-stages.sh:0
bin/dispatch-mode.sh:0
```

É a mesma classe do `input: prev_stage` declarado e nunca consumido
(incidente `2026-11-12-input-prev-stage-declarado-e-nunca-consu`) e do
`artifacts:` aceito e nunca lido
(`2026-11-12-stage-que-declara-artifacts-e-nao-escrev`): um campo que o
loader valida (e, no caso do `map`, até exige) e que ninguém lê em tempo de
execução. A validação do loader dava a impressão de que o campo valia
alguma coisa — e não valia.

## Correção aplicada

- `bin/lib-oracfit-rate-limit.sh` (novo): o mecanismo. Um portão que espera
  até a pausa declarada ter passado, um registro que marca o **fim** de cada
  despacho (a pausa é medida do fim de um despacho ao começo do próximo: uma
  chamada lenta não conta como pausa), e o teto de 3600s (regra 12: nenhum
  comando sem teto). O registro vive no processo, não em arquivo — o arquivo
  de controle do orquestrador nunca vai para o workdir despachado (regra 47).
- `bin/dispatch-stages.sh` e `bin/dispatch-mode.sh`: os dois runtimes honram o
  campo. O portão fica no topo do laço de tentativas, **antes** da leitura do
  inbox: uma interrupção durante a espera não pode engolir a mensagem do
  humano. A espera é anunciada no stderr e no `events.jsonl`, acontece em
  passos de 1 segundo, e uma interrupção do humano (o mesmo arquivo que o
  watchdog do runner assiste) encerra a espera em vez de esperar até o fim.
- `bin/lib-oracfit-mode-loader.py`: o loader passa a recusar o que o runtime
  não consegue honrar — `rate_limit_s` em qualquer stage (não só na `map`)
  precisa ser número, ≥ 0 e ≤ 3600. Antes, uma string, um negativo ou um
  valor absurdo passavam na validação e significavam nada em execução.
- `tests/test-rate-limit.sh` (novo): o mecanismo. Prova que os dois runtimes
  esperam entre tentativas quando o campo está declarado, que quem não declara
  não é desacelerado, que o loader recusa string/negativo/acima do teto, que
  o teto do loader e o do runtime são o mesmo número, que uma espera acima do
  teto é presa ao teto, e que uma interrupção do humano acaba com a espera.
- `docs/modes-catalog.md` e `site/llms.txt`: a semântica escrita onde o
  agente lê.

## Pode acontecer de novo?

Sim, na mesma classe: **campo aceito (ou exigido) pelo loader sem consumidor
no runtime**. A regra 32 pelo outro lado — uma afirmação de que o modo respeita
um limite precisa apontar para um mecanismo que existe e roda. E a lição do
`map` de visão: o limitador real estava no script, não no modo, ou seja,
fora do alcance de quem escreve o modo. Quando o limite é do **modo**, ele
precisa ser do runtime; quando é do **provedor**, ele pode ficar no script —
mas aí tem que estar escrito no YAML de algum lugar, senão a segunda pessoa
não sabe que ele existe.
