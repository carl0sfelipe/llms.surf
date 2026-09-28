# Dogfood 2026-09-26 — llms.surf × benchmark v4 (rails-chatapp, GGUF local na RTX 3090)

**Setup:** dispatch-mode (classe MECANICO_TRANSFORM, gauntlet + oracle) · tarefa `rails-chatapp-gguf` ·
modelo `qwen38-27b-q5km-gguf-3090` (Qwen3.8-27B UD-Q5_K_M GGUF, llama.cpp mainline sm_86, `127.0.0.1:8802`) ·
workdir isolado `/tmp/surf-gguf-3090/project` · `with-timeout.sh 7200` · spec de 4103 bytes (sha256 `5088954f…`).
Executor: opencode `build` agent, XDG isolado, permissões YOLO com escopo, GIT_CEILING no workdir.
Contexto: dogfood real — o mesmo brief que o benchmark v4 do Akita roda no harness limpo, agora
passando pelo produto. Run anterior equivalente (EXL3 via surf, 2026-09): `pass`, oracle 0, 9/9 estrutural.

## Resultado executivo

| | Run surf (hoje, GGUF Q5) | Referência surf (EXL3, set) | Harness limpo (Bonsai, hoje) |
|---|---|---|---|
| Status | **fail — timeout 7200s** | pass, oracle exit 0 | timeout 5400s, exit -15 |
| Arquivos entregues | 0 (skeleton `rails new` pós-kill) | app completo, 9/9 | 0 (skeleton) |
| Oracle | exit 1 (correto) | exit 0 | n/a |
| Onde morreu | arqueologia de gems do host | — | idem (65 de 90 min) |

**A promessa central segurou nos três pontos testados:** (1) modelo fora do registry → dispatch
recusado; (2) workdir vazio no timeout → oracle exit 1, nada "shipou" na palavra do modelo;
(3) oracle rodado à mão no estado final → exit 1 de novo (sem `ruby_llm` no Gemfile, sem compose,
sem uso de RubyLLM). Nenhum artefato saiu sem prova mecânica.

## O que o produto fez bem (com evidência)

1. **Registry gate funcionou de graça.** Primeiro launch falhou porque o modelo novo não estava em
   `model-registry.json` — comportamento projetado (nada de despachar modelo não verificado), e o
   produto **abriu incidente de uso sozinho** (`incidents/uso/2026-09-26-rails-chatapp-gguf-154815.md`,
   `emit-usage-feedback.sh`), com spec sha256, workdir e env DISPATCH_* sem secrets.
2. **Spec preflight** antes do dispatch: `✅ spec OK (declara dados verificados e proíbe invenção)`.
3. **Isolamento segurou.** Modelo vagou pelo host lendo gems (`~/.local/share/gem`), mas o GIT_CEILING
   + workdir isolado mantiveram o clone do benchmark intocado e o artefato dentro de `/tmp/…/project`.
4. **`with-timeout.sh` matou a árvore certinha** (`dispatch-mode.sh:460` registra o kill; "árvore de
   processos morta") e o estado do agente (todos + "Relevant Files") foi preservado no log para
   postmortem.
5. **Oracle imune a argumento.** Três execuções (pré, pós-timeout, manual) → exit 1 nas três.

## Dores encontradas (feedback para o produto)

1. **Registry recusa deveria falhar rápido.** Com modelo ausente do registry, o gauntlet queimou
   5 tentativas (`attempts: 5`, `flash_work_s: 0.54`) antes de falhar. Ação: pré-checagem de registry antes
   do loop, com mensagem acionável ("adicione `{id}` a `model-registry.json` com cli_hints.opencode").
2. **Estado do host fora do workdir é o boss final dos modelos locais.** Os dois runs de hoje
   (GGUF e ternário, harnesses diferentes) morreram no mesmo lugar: gems/ruby quebradas em
   `~/.local/share/gem` (rails meta-gem 8.1.4 incompleta, 7168 bytes). O llms.surf isola git e
   workdir, mas não o toolchain. Ideia de produto: **preflight toolchain oracle** (mise/ruby/bundler/
   `gem pristine` sanity) antes do dispatch, ou overlay de ruby-env por workdir
   (`test-oracfit-workdir-overlay.sh` já aponta o caminho).
3. **Mensagem de gap do gauntlet usou texto de template** ("re-check ## Oráculo comando and expected
   artifacts") quando o oracle real é um `oracle.sh` apontado pelo operador — confunde na primeira
   integração.
4. **`⚠️ nenhum literal conferível em spec.md`** — o operador novo não sabe se é bloqueante (não era).
   Vale uma linha de doc ou trocar por texto que diga o que falta no spec.
5. **Ledger não fechou no kill por timeout** (`ledger/mode.jsonl` vazio; `events.jsonl` tem os 103
   tool_calls com timestamp, mas sem contabilidade de tokens do run). Para modelo local o custo é
   zero, mas o produto promete "per-provider token accounting" — em timeout o número deveria ser
   emitido mesmo parcial.

## Rodada 2 — surf-v2 (gates verdes, modelo DNF por conta própria)

Com o toolchain consertado, a suíte `surf-v2.sh` rodou limpa: Gate 0 registry ✓,
Gate 1 toolchain ✓, Gate 2 servidor ✓ (com probe de coerência), dispatch saudável.
Resultado: **fail por timeout 7200s de novo — mas agora a causa é o modelo**, não o
ambiente: loop de thinking (relê Gemfile/ci.yml e replaneja a cada ~3 min, 140
eventos), `ruby_llm` nunca adicionado ao Gemfile, zero código de app. Oracle exit 1
(três checagens). Registro: `qwen-bench-runs/surf-gguf-3090/v2.result.json`.

Leitura: os gates fizeram exatamente o trabalho do produto — **provaram por código**
que a infra estava boa antes de gastar GPU, e que o DNF é do modelo. Sem os gates,
a suspeita ainda seria "ambiente quebrado".

## Root cause encontrado depois do relatório (mesma noite)

Os dois runs não morreram de "modelo fraco" ou "gems corrompidas" genéricas. Causa exata:

1. **`~/.local/share/mise/shims/bundle` era um ELF binário** (não script) — `bundle install`
   falhava com `Invalid char '\x7F' in expression` para qualquer processo usando o shim.
   Conserto: `sudo chown` dos shims + `mise use -g ruby@3.4.10` + `mise reshim` + wrapper
   `exec ruby …/bundler-4.0.21/exe/bundle "$@"`. Depois: `bundle --version` → 4.0.21 ✓.
2. **`rails` shim era symlink → /usr/sbin/mise** resolvendo só no ruby@4.0.6 (não ativo) —
   wrapper para `railties-8.1.4/exe/rails`. Depois: `Rails 8.1.4` ✓.
3. **O meta-gem `rails-8.1.4` "incompleto" era red herring** — meta-gem legítimo contém só
   MIT-LICENSE + README; o executável vive no `railties`. O modelo passou ~1h "consertando"
   algo que não estava quebrado, porque o caminho óbvio (`rails`, `bundle`) era o quebrado.
4. **`~/.config/zsh/secrets` não existe no host** — a spec manda sourcear um arquivo que não
   está lá; o modelo queima tokens procurando. Tratado como AVISO no gate (build usa WebMock).

Produto disto: **`bin/check-toolchain.sh`** — oracle mecânico de toolchain que verifica o que
a spec exige **pelo caminho que funciona**, avisa as armadilhas (shim mise, secrets) e falha
rápido com instrução acionável. Plugar no preflight do dispatch-mode é decisão do dono; a
suíte de dogfood já o usa como Gate 1 (`qwen-bench-runs/surf-gguf-3090/surf-v2.sh`, a nova
versão do teste com os gates na ordem da dor: registry → toolchain → servidor → dispatch).

## Ajustes feitos durante o dogfood (no repo do produto)

- `model-registry.json`: entrada `qwen38-27b-q5km-gguf-3090` adicionada (28 modelos),
  `cli_hints.opencode = qwen38-27b-3090/qwen38-27b-q5km`, `id_status: EXISTE`, `verified_by: opencode`.

## Artefatos

- Run dir: `/home/carlos/Projects/qwen-bench-runs/surf-gguf-3090/` (launch.sh, opencode.json,
  spec.md, oracle.sh, logs/dispatch.{out,err})
- Eventos: `/tmp/surf-gguf-3090/project/.dispatch/logs/events.jsonl` (103 eventos)
- Incidente auto-gerado: `incidents/uso/2026-09-26-rails-chatapp-gguf-154815.md`
- Comparação de harnesses (mesmo brief, 3090): Bonsai 2 27B via opencode limpo = 16/100 D
  (`results-v4/bonsai2_27b_ptq1_0_3090/sprints/sprint01_foundation/grade.json`);
  resposta-akita anterior: EXL3 via surf = pass/9-9 vs opencode no clone = failed/cola.
