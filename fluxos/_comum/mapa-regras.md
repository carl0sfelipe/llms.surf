# Mapa da poda de regras (D11)

Em 2026-07-27 o `SKILL.md` tinha **35 regras** convivendo com 2 fluxos. Duas fontes de
verdade divergem: "cheque quota antes de despachar" estava na regra 11 **e** dentro de
`fluxos/dispatch/step-02-prepare.md`. Quando as duas discordarem, ninguém sabe qual vale.

Este arquivo registra o destino de cada regra. Serve para auditoria: nenhuma proteção foi
descartada, cada uma foi movida para onde é aplicada.

## Critério

| Classe | Significado | O que aconteceu com o texto |
|---|---|---|
| **P** | vira passo | conteúdo movido para o step do fluxo que o executa; sai do `SKILL.md` |
| **C** | vira código | já existe mecanismo que impõe; sai do `SKILL.md`, comentário no código cita o incidente |
| **R** | permanece regra | exige julgamento, sem mecanismo possível hoje; fica no `SKILL.md` |

## Numeração é imutável

As regras que sobreviveram **mantêm o número original**. Não há renumeração — números não
são reciclados nem deslocados. Uma referência a "regra 12" continua apontando para a mesma
regra depois de qualquer poda futura. Regra removida deixa buraco no número, de propósito.

Código que citava regra removida passou a citar `incidents/<arquivo>` — id de incidente é
imutável por construção.

## Destino de cada regra

| # | Assunto | Classe | Destino |
|---|---|---|---|
| 1 | orquestrador não escreve bulk | **R** | permanece (absorveu a 2 e a ressalva da 31) |
| 2 | lê + decide + despacha | P | fundida na regra 1 |
| 3 | refinamento = DELETE/REESCREVA/ADICIONE | P | `fluxos/dispatch/step-04-verify.md` §3 |
| 4 | verificar contra código real | P | `fluxos/dispatch/step-02-prepare.md` §2 |
| 5 | 1 arquivo por story | P | `fluxos/dispatch/step-02-prepare.md` §2 |
| 6 | smoke test antes de despachar | P | `fluxos/dispatch/step-02-prepare.md` §6 |
| 7 | timeout ≥ 30min para free | C | `bin/dispatch.sh` (`DISPATCH_TIMEOUT=1800`) |
| 8 | nunca 2 agentes no mesmo `.git` | C | `bin/pre-dispatch-check.sh` + lock RNF-07 em `bin/dispatch.sh` |
| 9 | rate limit ≠ incapacidade | P | `fluxos/diagnose/step-01-triagem.md` (superada pela 22) |
| 10 | fork exige session ID real | **R** | permanece |
| 11 | checar quota antes de despachar | P | `fluxos/dispatch/step-02-prepare.md` §4 |
| 12 | nenhum comando sem teto de tempo | **R** | permanece para comando AD-HOC (julgamento: use `bin/with-timeout.sh`). Nos caminhos de dispatch virou mecânico em 2026-08-13 (fase 5 do v4): lote (`bin/dispatch-batch.sh`, 1200s + rollback), direto (`bin/dispatch.sh`, watchdog `DISPATCH_TIMEOUT`) e escalate (`bin/dispatch-escalate.sh` embrulha claude/runner/opencode em `bin/with-timeout.sh`, default 1200s, exit 124 = tentativa falhada; teste `tests/test-gates-dispatch.sh`) |
| 13 | não juntar validação + rede + commit | **R** | permanece |
| 14 | anunciar duração esperada | **R** | permanece |
| 15 | silêncio ≠ progresso | P | `fluxos/diagnose/` (fluxo inteiro) |
| 16 | todo problema que pode repetir vira regra | **R** | permanece — `bin/incident.sh audit` cobre a dívida, não a identificação |
| 17 | teto mata o grupo | C | **superada pela 21** — `bin/with-timeout.sh` |
| 18 | erro de provider não vira timeout mudo | C | `adapters/opencode/runner.sh` (inspeção em streaming) |
| 19 | gate cobre a TUI, não só o subcomando | C | `bin/pre-dispatch-check.sh` |
| 20 | medição registra provider e quantização | C | `bin/verify-models.sh` + `bin/audit-registry-ids.sh` |
| 21 | teto mata a árvore de processos | C | `bin/with-timeout.sh` (`pgrep -P` recursivo) |
| 22 | classificar a falha pelo log — 3 modos | P | `fluxos/diagnose/step-01-triagem.md` |
| 23 | identificar candidato a regra é contínuo | **R** | permanece |
| 24 | `$?` após pipe mente; nunca `2>&1` na resposta | C | `bin/run-check.sh` |
| 25 | dry-run antes de gravar em store | **R** | permanece — `--write` existe, mas nada obriga o dry-run antes |
| 26 | ausência só se provada | **R** | permanece |
| 27 | travamento se classifica, não se adivinha | P | `fluxos/diagnose/` + `bin/diagnose-hang.sh` |
| 28 | medição roda em sandbox | C | `bin/verify-models.sh` (`mktemp -d`) |
| 29 | runtime agêntico é ponto único de falha | P | `fluxos/diagnose/step-02-antes-do-provider.md` |
| 30 | wrapper que dá `exec` trata stdin | C | `bin/with-timeout.sh` |
| 31 | exit 0 não é prova de trabalho | P | `fluxos/dispatch/step-04-verify.md` §2 (ressalva sobre transformação determinística foi para a regra 1) |
| 32 | toda regra declara seu mecanismo | **R** | permanece — é o critério desta poda |
| 33 | nota alta ≠ capacidade agêntica (`TOOLS`) | P | `fluxos/dispatch/step-02-prepare.md` §3 |
| 34 | config default do CLI | P | `fluxos/dispatch/step-02-prepare.md` §1 |
| 35 | spec declara dados verificados | **C** | `bin/check-spec.sh` (a spec tem o bloco) **+ `bin/check-spec-facts.py`** (o bloco é VERDADE), ligados no gate de `bin/dispatch-batch.sh`. Era P — e em 2026-07-29 o orquestrador afirmou num bloco de dados verificados um glob de `vitest.config.ts` que existia em outro repo; a spec passou nos 5 checks e foi despachada. Passo documentado não impede quem escreve o passo. Incidente: `incidents/2026-07-29-spec-com-dado-inventado-passou-no-gate.md` |
| 37 | bloco de dados verificados passa pelo `check-spec-facts.py` | C | o gate virou do DISPATCH em 2026-08-13 (fase 5 do v4): `oracfit_preflight` (`bin/lib-oracfit-preflight.sh`) roda check-spec + facts + check-oracle em `bin/dispatch.sh` direto, `bin/dispatch-escalate.sh`, `bin/dispatch-mode.sh` e `bin/dispatch-stages.sh`; o lote mantém o gate próprio equivalente. Teste: `tests/test-gates-dispatch.sh`. Incidente: `incidents/2026-07-29-spec-com-dado-inventado-passou-no-gate.md` |
| 38 | relatório declara suas fontes; ledger novo entra no relatório | **R** | permanece — **dívida declarada**: nada força a inclusão. O relatório hoje imprime o nome de cada fonte e avisa quando falta, o que expõe a lacuna sem impedi-la. Incidente: `incidents/2026-07-29-relatorio-media-um-ledger-de-tres.md` |
| 39 | exit≠0 do oráculo não prova trabalho faltando | C | o gate virou do DISPATCH em 2026-08-13 (fase 5 do v4): `bin/check-oracle.py` (lint de padrão + prova de esqueleto + classificação de stderr) roda via `oracfit_preflight` em `bin/dispatch.sh` direto, `bin/dispatch-escalate.sh`, `bin/dispatch-mode.sh` e `bin/dispatch-stages.sh`, além do lote. Oráculo quebrado = exit 2 sem chamar modelo. **A formulação registrada como candidata era errada** — "exigir que cada grep case algo" reprovaria todo oráculo correto; o exigível é o ESQUELETO, não o ALVO. Teste: `tests/test-gates-dispatch.sh`. Incidente: `incidents/2026-07-29-oraculo-com-pipe-escapado-nao-passa-nunca.md` |
| 36 | publicar exige tree limpa, commit no remoto e tag | **R** | permanece — **dívida declarada**: o mecanismo previsto (hook `prepublishOnly` recusando tree suja, mais um verificador de pré-publicação no repositório do framework) ainda não foi escrito. Vira C quando o SEP-03 entrar. Incidente: `incidents/2026-07-28-versao-publicada-sem-commit-fonte-de-0-1.md` |
| 40 | classificar task antes de despachar (MECANICO→escalate; COPY/ARCH→shell) | **R** | permanece — julgamento do orquestrador; sem classificador automático ainda. Incidente: `incidents/2026-07-30-cursor-grok-primeiras-impressoes-do-disp.md` |
| 41 | todo modo emite telemetria + incidente de uso automático | **C** | `bin/emit-usage-feedback.sh` nos exits de escalate/batch/ledger-finalize. Coleta automática; promoção continua 16/23. Opt-out `DISPATCH_USAGE_FEEDBACK=0`. Incidente: `incidents/2026-07-30-feedback-de-uso-forcado-por-humano.md` |
| 42 | job longo fora do dispatch.sh fica órfão (sem watchdog) | **R** | permanece — checklist nohup+disown+smoke-30s+PID-file+heartbeat documentado no incidente; nada obriga. Vira C quando houver wrapper obrigatório ou heartbeat por PID no inbox. 3ª manifestação (8min → 2h13). Incidente: `incidents/2026-08-09-content-factory-morte-silenciosa-sem-watchdog.md` |
| 43 | preço de concorrente exige disclosing de condição; nunca linkar concorrente sem alternativa <repo-cliente> | **R** | permanece — mecanismo parcial externo: `_fairness_check` em src/bmad_crew.py do content-factory + 7 testes (heurística textual; falso negativo se preço não for numérico). Complementa market_prices.py. Vira C quando cobrir também ausência de R$ explícito. Incidente: `incidents/2026-08-09-conteudo-factualmente-enganoso-compara-n.md` |
| 44 | verdict T4-JUDGE: um campo canônico, enforced na escrita, casado pelo oráculo; YAML truncado nunca é APPROVED | **R** | permanece — mecanismo pendente no repo content-factory (schema validation na escrita + rejeição de truncamento no parser). Dívida declarada. Incidente: `incidents/2026-08-09-oraculo-casa-decision-mas-t4-vem-com-sta.md` |
| 45 | extrator de feedback do gauntlet deve procurar os campos que o agent produz; required_fields no tasks.yaml | **R** | permanece — mecanismo parcial em `_extract_biggest_gap` (cascata de campos) + `required_fields` no T1-JUDGE; dívida até validador de schema cross-arquivo entre tasks.yaml e agents.yaml. Incidente: `incidents/2026-08-10-gauntlet-loop-biggest-gap-vazio-faz-buil.md` |
| 46 | linha `- comando:` do oráculo deve ser texto cru, sem crase (backtick) | **R** | permanece — mecanismo parcial em `bin/check-spec.sh` (reprova crase na linha `- comando:`); crase em outros pontos da spec não é checada. Incidente: `incidents/2026-08-10-backtick-no-comando-do-oraculo-vira-substituicao-e-127.md` |
| 47 | arquivos de controle do orquestrador (stop, pause, interrupt) nunca no workdir despachado | **R** | permanece — oracfit satisfaz por design (`.dispatch/logs/inbox/<run_id>.interrupt` fora do workdir, HITL-only); princípio de design para orquestradores futuros. Incidente: `incidents/2026-08-10-modelo-despachado-cria-arquivo-de-parada-e-mata-loop.md` |
| 48 | nunca editar in-place script bash que run vivo ainda vai executar — temp + mv atômico ou esperar o run | **R** | permanece — julgamento a cada edição: editor externo (Cursor/vim) não passa por gate nenhum; sem mecanismo que intercepte write em `bin/` com dispatch vivo. Incidente: `incidents/2026-08-12-editar-script-em-execucao-desloca-bytes-exit-127.md` |
| 49 | processo de longa duração do orquestrador Cursor usa background gerenciado do harness, nunca `&`/nohup em chamada pontual; prova de vida em chamada POSTERIOR | **R** | permanece — procedimento do orquestrador, fora do alcance do oracfit (o harness do Cursor mata a árvore da chamada; nenhum script daqui intercepta). Incidente: `incidents/2026-08-12-servidor-demo-morre-quando-a-sessao-do-s.md` |
| 50 | oráculo de artefato não usa `wc -l` como critério dominante; régua de tamanho só com greps de conteúdo por seção + grep negativo para decisões de recorte | **R** | permanece — exige julgamento na autoria da spec; mecanismo futuro possível (lint de `wc -l` dominante em `bin/check-spec.sh`), não construído. Incidente: `incidents/2026-08-12-oraculo-com-regua-de-linhas-minimas-indu.md` |
| 51 | limpeza de disco nunca destrói estado sem backup verificado (dump é gate); < 25 GB alerta, < 10 GB pausa trabalho em massa; alvos seguros primeiro, VM/volume de produção por último; medir com df antes de agir | **R** | permanece — julgamento do operador em ação destrutiva fora do alcance dos gates do oracfit; MECANISMO pendente declarado na própria regra (watchdog launchd + alerta Hermes < 25 GB), não construído. Incidente: `incidents/2026-08-12-disco-enche-ate-100-de-forma-recorrente-.md` |
| 52 | repo do produto não é workdir nem spec-store de despacho de cliente; specs/ é categoria declarada (privada) do corte; teste do framework não aponta pra árvore de outro projeto | **R** | permanece — mecanismo construído: `bin/check-publico.sh` (telefone BR, e-mail fora de allowlist, caminho de máquina em código) no `check-saude.sh` (--oficina) e pós-condição do `oracfit-publish-cut.sh apply` (scan cheio + PRIVATE_DIRS + guarda anti-corte-regressivo). Resíduo de julgamento: allowlist de e-mail e curadoria de incidents/ no corte. Incidente: `incidents/2026-08-13-oracfit-soldado-no-<repo-cliente>-corte-sem-catego.md` |
| 53 | veredito de run só existe na superfície canônica do próprio workdir (status --task), e não existem dois dispatches vivos no mesmo workdir; log existente não é log DO seu run | **R** | mecanismos 1–2 CONSTRUÍDOS (S7, 2026-08-29): single-flight portátil por workdir (oracfit_run_lock_acquire/release, lib lib-oracfit-root.sh sourced pelos dois entrypoints, exit 6 + takeover de lock órfão) e oracfit status --task (cmd_status em bin/oracfit); mecanismo 3 (imprint sha256 no green) segue pendente — dívida declarada; interage_com 24, 31, 42, 44 e 26. Incidente: `incidents/2026-08-27-dogfooding-tres-despachos-no-mesmo-workdir-e-veredito-lido-grepa-crud.md` |
| 54 | allowlist de provider (E5-M6/R4) só governa o caminho free; dispatch com model-id explícito grava fora-do-escopo, nunca violado | **R** | permanece — MECANISMO pendente: campo origem no .efetivo (run-with-fallback) + decisão por origem no ledger-finalize; até entrar, dispatch pago canônico é caluniado (falso violado). Incidente: `incidents/2026-08-30-allowlist-do-free-path-assertiona-dispat.md` |
| 55 | fallback de registry validado no encadeamento: ref existe E endpoint responde; fantasma/morto pula, cadeia vazia = exit 2 limpo | **R** | permanece — MECANISMO pendente: checagem pré-fallback no run-with-fallback.sh; audit 2026-08-30 achou 7 fantasmas + 1 morto em 11 refs. Incidente: `incidents/2026-08-30-fallback-do-registry-aponta-endpoint-sus.md` |

**Resultado:** 35 → **10 regras** na poda; depois cresceu com 36–41. 15 viraram passo, 10+ viraram código.

## O que a poda não resolve

As 10 que sobraram são exatamente as **sem mecanismo** — a medição do incidente
`2026-07-25-31-regras-em-dois-dias-e-a-maioria-depen.md` mostrou que todas as violações
registradas foram de regras assim. Podar reduziu o ruído; não transformou disciplina em
garantia. Cada uma que ganhar mecanismo depois sai daqui e vira C.

<!-- 54 → viva no SKILL.md: allowlist do free path não calunia dispatch pago explícito. Mecanismo PENDENTE: campo origem no .efetivo (run-with-fallback) + decisão por origem no ledger-finalize (incidente 2026-08-30). -->
<!-- 55 → viva no SKILL.md: fallback validado no encadeamento (ref existe + endpoint responde; fantasma/morto pula; cadeia vazia = exit 2). Mecanismo PENDENTE: checagem pré-fallback no run-with-fallback.sh (incidente 2026-08-30). -->
