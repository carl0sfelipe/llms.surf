# Dispatch — Orquestração Multi-Modelo

## Onde está o quê

O trabalho é executado por **fluxos**, não por memória de regras. Comece por eles:

| Quero | Leia |
|---|---|
| despachar trabalho para um modelo | `fluxos/dispatch/SKILL.md` |
| entender um dispatch que travou | `fluxos/diagnose/SKILL.md` |
| medir um modelo antes de gravar no registry | `fluxos/verify/SKILL.md` |
| transformar uma falha em proteção real | `fluxos/incident/SKILL.md` |
| saber onde foi parar a regra N | `fluxos/_comum/mapa-regras.md` |

O fluxo diz o que fazer, em que ordem, e grava o estado no artefato. As regras abaixo são só o que **não** coube em passo nem em código.

---

## REGRAS

Em 2026-07-27 havia 35 regras aqui. Quinze viraram passo de fluxo, dez viraram código. Sobraram estas dez — todas exigem julgamento e **nenhuma tem mecanismo que a imponha**. É exatamente por isso que são as mais violadas: a medição de `incidents/2026-07-25-31-regras-em-dois-dias-e-a-maioria-depen.md` mostrou que toda violação registrada foi de regra sem código por trás.

Os números são **imutáveis**. Regra removida deixa buraco; número nunca é reciclado — referência antiga em código ou incidente passaria a apontar para outra regra. Destino de cada uma em `fluxos/_comum/mapa-regras.md`.

<!-- ultimo-numero-de-regra: 52 -->
`bin/incident.sh promote` lê o marcador acima para saber o próximo número. Não edite à mão.

**1. VOCÊ LÊ, DECIDE E DESPACHA — NÃO ESCREVE BULK.**
Seu output é spec curta, instrução de refinamento e decisão. Mais de ~20 linhas de conteúdo vai para modelo free.
**Ressalva que já custou caro:** isto vale para trabalho que exige **julgamento**. Se a entrada é conhecida e a transformação é mecânica, é **código** — despachar só adiciona custo e chance de campo inventado. Pergunte antes: "isso precisa do meu raciocínio, ou é uma transformação determinística?"

**10. FORK EXIGE SESSION ID REAL.**
Obtenha com `bin/session-health.sh`. Nunca invente id. O runner recusa `--fork` sem `--session` (exit 3), mas não sabe se o id que você passou é real.

**12. NENHUM COMANDO SEM TETO DE TEMPO.**
Tudo que toca rede ou modelo vai dentro de `bin/with-timeout.sh <segs>`. macOS não tem `timeout(1)` — sem teto, travamento fica invisível. Nos caminhos de dispatch o teto virou MECÂNICO em 2026-08-13 (lote, direto e escalate embrulham todo call-site de modelo — fase 5 do v4); esta regra permanece para comando ad-hoc FORA deles, onde **nada obriga você a usar o wrapper** — e foi assim que 52 minutos foram perdidos uma vez.

**13. NUNCA JUNTE VALIDAÇÃO + REDE + COMMIT NO MESMO COMANDO.**
Bloco gordo que trava não diz onde parou. Local (instantâneo) separado; rede isolada e com teto.

**14. ANUNCIE A DURAÇÃO ESPERADA ANTES DE RODAR ALGO >10s.**
O humano nunca deve ter que adivinhar se é lentidão ou travamento. Se ele precisou perguntar "travou?", o sistema já falhou.

**16. TODO PROBLEMA QUE PODE SE REPETIR VIRA REGRA OU MECANISMO.**
Registre com `bin/incident.sh new`, promova com `bin/incident.sh promote`. Lição solta não protege ninguém — quem lê depois já errou. Spec: `core/feedback-protocol.md`. `bin/incident.sh audit` cobre a **dívida** de incidentes já registrados; não cobre a identificação, que é sua.

**23. IDENTIFICAR CANDIDATO A REGRA É CONTÍNUO E POR DEFAULT.**
Não espere ser pedido. Ao fim de qualquer bloco de trabalho, varra as falhas repetidas. Toda regra nova declara no incidente `interage_com:` quais regras reforça, restringe ou **supera**, e o que a combinação pode quebrar — as antigas 17 e 18 juntas criaram um bug que nenhuma tinha sozinha. **Consolide antes de multiplicar.**

**25. DRY-RUN ANTES DE GRAVAR EM STORE DE DADOS.**
Registry e ledger alimentam decisão futura: dado falso ali contamina tudo depois. Rode sem `--write`, **leia** o resultado, só então grave. Zero absoluto (accuracy `0.0`) é quase sempre bug de harness, não incapacidade do modelo — trate como suspeita, não como medição.

**26. AUSÊNCIA SÓ SE PROVADA, E BUSCA PARCIAL NÃO PROVA.**
Diga "não encontrei em X e Y", nunca "não existe". Uma afirmação de ausência baseada em `find` no repo mais `ls` de primeiro nível do home estava errada: o arquivo existia dois níveis abaixo, em diretório oculto. Antes de afirmar ausência: busca recursiva, incluindo ocultos.

**32. TODA REGRA DECLARA SEU MECANISMO — ou declara que não tem.**
Regra sem mecanismo é **dívida**, não entrega. Regra-texto pode inclusive **induzir** erro quando não distingue contexto (foi o que a regra 1 fez até ganhar a ressalva acima). Este é o critério da poda: ao ganhar mecanismo, a regra sai daqui e vira código.

**36. PUBLICAR EXIGE WORKING TREE LIMPA, COMMIT NO REMOTO E TAG. Publicação é irreversível: a versão fica no registry para sempre e não há dry-run depois do fato. Se a fonte não estiver em git no momento do publish, o que foi publicado deixa de ser verificável — ninguém consegue dizer qual código está rodando sem perícia no tarball. Em 2026-07-28 as versões 0.1.3 e 0.1.4 do kit-storefront saíram de uma working tree suja: nenhum commit corresponde a elas, e determinar o que continham exigiu diff entre os dist/ em node_modules e os commits vizinhos. Custo real medido: perícia, não perda de código. Antes de publicar: git status vazio, HEAD presente no remoto, e tag apontando para o commit publicado. SEM MECANISMO HOJE — é dívida, e o mecanismo é o SEP-03 (prepublishOnly recusando tree suja + verificador de pré-publicação).** (incidente: `incidents/2026-07-28-versao-publicada-sem-commit-fonte-de-0-1.md`)

**38. RELATÓRIO NOVO DECLARA TODAS AS FONTES QUE LÊ, E LEDGER NOVO ENTRA NO RELATÓRIO NO MESMO COMMIT. `bin/dispatch-report.sh` lia só `ledger/ledger.jsonl` enquanto o 2.1 gravava em `.dispatch/logs/escalate-ledger.jsonl` e o 2.2 em `batch-ledger.jsonl` — 12 runs de escalonamento e todos os lotes eram invisíveis, e a placa '3 passou / 1 falhou' de 4 registros do dispatch simples foi apresentada como o placar do framework. Não é sensor que mede a coisa errada (24, e os oráculos cegos do 2.0/2.1): é sensor que olha o ARQUIVO errado — mede uma fonte de N e reporta como total. SEM MECANISMO que force a inclusão: nada impede um 2.3 gravar num quarto ledger e sumir do relatório. Mitigação hoje: o relatório imprime o nome de cada fonte e diz quando uma não existe, então operador vê a lacuna em vez de ver um número plausível** (incidente: `incidents/2026-07-29-relatorio-media-um-ledger-de-tres.md`)

**40. Antes de despachar: classifique a task. MECANICO_TRANSFORM (rename/debrand/sed-like, path unico, oraculo grep) → dispatch-escalate. COPY/SCAFFOLD/ARCH (cp N arquivos, ADR, package.json, publish) → shell ou orquestrador — NUNCA flash. Evidencia 2026-07-30: 5 lotes debrand 100% flash 1a tentativa; copia 112 specs foi cp em segundos.** (incidente: `incidents/2026-07-30-cursor-grok-primeiras-impressoes-do-disp.md`)

<!-- 41 → classe C no mapa: bin/emit-usage-feedback.sh (incidents/2026-07-30-feedback-de-uso-forcado-por-humano.md). Fora do SKILL. -->

**42. TODO JOB LONGO LANÇADO FORA DO dispatch.sh (opencode run direto, main.py do CF, nohup&, scripts ad-hoc) FICA ÓRFÃO: o watchdog do dispatch.sh só monitora o que passa por ele. Em 2026-08-09 o pid 4533 (opencode run headless, nicho Beelink) ficou 2h13min 'rodando' depois do trabalho real terminar — o main.py do CF encerrou às 21:16 mas o wrapper opencode ficou vivo em estado S até o humano mandar verificar (regra de ouro do 2026-07-24 violada de novo: 'se o humano precisou perguntar travou, o sistema já falhou'). 3ª manifestação documentada, escalando de 8min (1ª) para 2h13 (3ª). Lição: processo em estado S com baixo CPU NÃO é prova de vida — só kill -0 $PID E mtime crescente do log provam. SEM MECANISMO HOJE para jobs fora do dispatch.sh. Mitigação parcial: o checklist nohup+disown+smoke-30s+PID-file+heartbeat do incidente, mas nada o OBRIGA. O buraco é estrutural: cada caminho que lança job longo (dispatch.sh, opencode direto, cursor shell, main.py) tem seu próprio (ou nenhum) watchdog. Dívida até existir wrapper obrigatório ou heartbeat no inbox por PID.** (incidente: `incidents/2026-08-09-content-factory-morte-silenciosa-sem-watchdog.md`)

**43. TODO CONTEÚDO GERADO PELO CF QUE MENCIONAR PREÇO DE CONCORRENTE DEVE DISCLOSAR A CONDIÇÃO (novo/usado/refurbished) e nunca linkar concorrente sem oferecer alternativa da Orbe primeiro. Em 2026-08-09 o post do Beelink comparava NOVO da Orbe (R$ 4.290) com USADO do ML (R$ 3.299-3.599, sem caixa) sem disclosing, concluindo 'a Orbe tá cara' — factualmente enganoso. O T4-JUDGE aprovou como copy boa porque avalia texto, não intenção comercial nem veracidade da comparação. Comparação novo×usado sem disclosing é o bug. MECANISMO: _fairness_check em src/bmad_crew.py — heurística sobre o output do T4 que detecta 'R$ + concorrente' sem termo de condição (novo/usado/sem caixa/etc) numa janela de 300 chars, e força APPROVED→REVISIONS_REQUIRED se detectar. 7 testes em tests/test_fairness_check.py (caso enganoso reprova, honesto com disclosing passa, não-T4 não roda). Complementa market_prices.py (lib/market_types.py fairness_warning) que faz o mesmo check sobre a TABELA de preços pesquisados. Limitação: heurística textual, não substitui revisão humana comercial; falsos negativos possíveis se o texto omitir preço numérico (ex.: 'mais barato lá' sem R$).** (incidente: `incidents/2026-08-09-conteudo-factualmente-enganoso-compara-n.md`)

**44. O VERDICT DO T4-JUDGE TEM UM CAMPO CANÔNICO, ENFORCED NA ESCRITA E CASADO PELO ORÁCULO. Os quatro nomes coexistindo hoje (status/decision/verdict/approval_gate) são a evidência do bug: sem contrato enforced, cada prompt de agente inventa o seu, e o oráculo aprova/reprova pelo motivo errado (7 de 12 T4s em disco reprovam no gate atual). O expected_output.verdict do tasks.yaml é a fonte da verdade; o código do content-factory valida na escrita e o oráculo casa o mesmo campo. DUAS CAMADAS EXTRAS REGISTRADAS NO INCIDENTE: (1) o truncamento vem do LLM — Final Answer cortado no meio da palavra — e (2) o parser do CrewAI dá FALSO APPROVED sobre YAML truncado; _persist_artifact deve rejeitar YAML truncado e _parse_judge_decision nunca reportar APPROVED sobre conteúdo cortado. Sem validar integridade, qualquer uma das três camadas recria o falso sucesso. MECANISMO: pendente no repo content-factory (schema validation na escrita + rejeição de truncamento) — dívida declarada até entrar. INTERAGE: mesma família das regras 24 (captura mentiu) e 31 (exit 0 sem fazer nada) — falso sucesso; reforça a 16 (problema recorrente vira mecanismo) e a 32 (regra declara mecanismo — aqui, declarado como pendente).** (incidente: `incidents/2026-08-09-oraculo-casa-decision-mas-t4-vem-com-sta.md`)

**45. TODO EXTRATOR DE FEEDBACK DO GAUNTLET DEVE PROCURAR OS CAMPOS QUE O AGENT REALMENTE PRODUZ (e o tasks.yaml required_fields deve incluir o campo canônico). Incompatibilidade de schema entre tasks.yaml (expected_output.required_fields) e agents.yaml (prompt do agent) é o bug: o agent segue o tasks.yaml e não produz 'biggest_gap' se ele não estiver listado, mas o _extract_biggest_gap só procurava biggest_gap — feedback chegava VAZIO e o builder refazia às cegas, loop não convergia, desperdiçava o teto de 20 iterações (~30min, ~125k tokens). Piloto radeon-680m: 5 iterações todas com biggest_gap vazio. MECANISMO (regra 32 satisfeita): _extract_biggest_gap em src/bmad_crew.py agora cai em cascata por biggest_gap → improvement_requirements → feedback_for_hunter → critical_issues (os campos que o juiz produz de fato) + tasks.yaml T1-JUDGE required_fields agora inclui biggest_gap explicitamente (T4-JUDGE já tinha). 5 testes cobrem: sem-gap-com-improvement (o bug), com-gap (backward), APPROVED vazio, marker textual, feedback_for_hunter sozinho. Lição geral: extrator e schema do agent devem concordar — nada enforceia isso automaticamente, é dívida até um validador de schema cross-arquivo.** (incidente: `incidents/2026-08-10-gauntlet-loop-biggest-gap-vazio-faz-buil.md`)

**46. A LINHA '- comando:' DO ORÁCULO (## Oraculo da spec) DEVE SER TEXTO CRU, SEM CRASE (backtick). Crase no eval do gauntlet (lib-oracfit-gauntlet.sh) e no check-oracle.py vira SUBSTITUIÇÃO de comando: o bash executa o backtick, captura o stdout, tenta rodar ESSE stdout como comando -> exit 127 fantasma. O oraculo 'falha' pelo motivo errado (parsing, nao falta de trabalho) e pode liberar dispatch quebrado. Incidente 2026-08-10 (overnight tripcstory-mvp1): 3 ciclos morreram com rc=127 sem mensagem, ~7min cada, porque a linha comando: estava envolta em crase. MECANISMO (regra 32 satisfeita): bin/check-spec.sh reprova linha 'comando:' que contenha crase — verificado com spec sintetica (com crase reprova, sem crase passa). Familia da regra 2 ('o que o grep casa nao e o que o shell roda') e 39 (exit do oraculo pode ser oraculo quebrado). Limitacao: o check so pega crase na linha '- comando:' literal; crase em outros pontos da spec (ex: bloco de verificacao VERIFICACAO:) nao e checada — o oraculo principal e o que mata.** (incidente: `incidents/2026-08-10-backtick-no-comando-do-oraculo-vira-substituicao-e-127.md`)

**47. ARQUIVOS DE CONTROLE DO ORQUESTRADOR (stop, pause, interrupt, flags) NUNCA no workdir despachado ao modelo — sempre fora do repo ou em dir só-legível-pelo-orquestrador. O modelo despachado TEM permissão de escrita no próprio palco: se o botão de desligar vive lá, ele é gravável por acidente. Incidente 2026-08-10 (overnight tripcstory-mvp1): o modelo despachado tocou 'tools/STOP' durante um ciclo de polish (git commit, nohup) e o orquestrador obedeceu e encerrou às 07:54 — nenhuma intervenção humana. A mensagem de log do oracfit também NÃO deve anunciar o mecanismo de parada em texto que o modelo possa ler (info leakage). MECANISMO: o oracfit já satisfaz por design — marcador de parada é '.dispatch/logs/inbox/<run_id>.interrupt', FORA do workdir despachado, criado SÓ por HITL humano (POST /api/message do painel), e nenhum script anuncia o mecanismo em log. A regra protege orquestradores futuros e o tripcstory (que movimentou STOP pra ~/.tripstory-overnight.stop). Sem código novo no oracfit — é princípio de design.** (incidente: `incidents/2026-08-10-modelo-despachado-cria-arquivo-de-parada-e-mata-loop.md`)

**48. NUNCA EDITE IN-PLACE SCRIPT BASH QUE UM RUN VIVO AINDA VAI EXECUTAR (dispatch-stages.sh, libs sourced tardiamente, scripts de bin/ chamados por stage). Bash le o arquivo preguicosamente por offset: write no mesmo inode desloca bytes e o parser le fragmento de token como comando — exit 127 ou syntax error minutos a horas DEPOIS da edicao, matando attempt ou o run inteiro. Duas ocorrencias na mesma noite (2026-08-12, run 177DA27B): a 1a queimou um attempt de vision_gate; a 2a (edicao no dispatch-stages.sh as 01:00, crash as 01:31) matou o run que estava convergindo. Correcao segura: escrever em arquivo temp no MESMO filesystem e mv por cima — rename e atomico, o processo em voo mantem o inode antigo integro e so a PROXIMA invocacao le o novo; ou esperar o run terminar. Antes de editar, audite TODOS os scripts que o run vivo ainda vai reler, nao so o que voce quer mudar. SEM MECANISMO HOJE — editor externo (Cursor, vim) nao passa por gate nenhum; e julgamento a cada edicao com dispatch vivo. INTERAGE: reforca a 13 (blocos separados — aqui, edicao separada de execucao); mesma familia da 42 (job longo fora do watchdog: o dano aparece longe da causa).** (incidente: `incidents/2026-08-12-editar-script-em-execucao-desloca-bytes-exit-127.md`)

**49. PROCESSO DE LONGA DURACAO LANCADO PELO ORQUESTRADOR CURSOR (dev server, painel, watcher) usa o mecanismo de background GERENCIADO do harness (terminal persistente), NUNCA `&`/subshell/nohup+disown dentro de chamada pontual de shell — o harness limpa a arvore de processos ao fim da chamada e nohup nao protege de kill de process group. Smoke em T+segundos prova NASCIMENTO, nao vida: antes de entregar URL ao humano, prove vida numa chamada POSTERIOR (kill -0 + resposta HTTP/mtime crescente). Medido 2026-08-12: mesmo servidor, 3 formas de lancar — as duas dentro da chamada morreram mudas apos smoke verde; a gerenciada sobreviveu. INTERAGE: complementa a 42 (la: zumbi orfao fora do watchdog; aqui: vivo que vira defunto na limpeza da sessao) e reforca a 14** (incidente: `incidents/2026-08-12-servidor-demo-morre-quando-a-sessao-do-s.md`)

**50. ORACULO DE ARTEFATO NAO USA wc -l COMO CRITERIO DOMINANTE — regua de tamanho e metrica de Goodhart: quando o unico gap entre fail e pass e contagem de linhas, o caminho mais barato do modelo e padding, nao conteudo (medido 2026-08-12: modelo apensou ~70 linhas de filler, incluindo frase que contradizia decisao da spec, so pra bater -ge 130). Regua minima de linhas SO acompanhada de greps de conteudo POR SECAO; e toda decisao negativa da spec ('X fica fora do V1') exige grep negativo (! grep -qi ...) no oraculo — grep positivo nao protege recorte. Familia das 24/31/44 (sinal de pass mentiu sobre a qualidade real)** (incidente: `incidents/2026-08-12-oraculo-com-regua-de-linhas-minimas-indu.md`)

**51. LIMPEZA DE DISCO NUNCA DESTRÓI ESTADO SEM BACKUP VERIFICADO: colima delete / remoção de volume Docker / recriação de VM só DEPOIS de pg_dump do Postgres de produção conferido (backup é gate, não opção — 2026-08-11 o colima delete zerou o catálogo Medusa e perdeu produto fora do seed). Disco < 25 GB livres = alerta; < 10 GB = pausar trabalho em massa (dispatch paralelo, builds) e liberar espaço pelos alvos SEGUROS primeiro: caches npm, ~/Library/Caches, imagens Docker dangling, Downloads antigos — VM/volume de produção é o ÚLTIMO recurso e sempre com dump. O livre do APFS oscila (purgeable): medir com df antes de agir, não confiar em leitura única. MECANISMO pendente: watchdog launchd + alerta Hermes < 25 GB.** (incidente: `incidents/2026-08-12-disco-enche-ate-100-de-forma-recorrente-.md`)

**52. O REPO DO PRODUTO ORACFIT NÃO É WORKDIR NEM SPEC-STORE DE DESPACHO DE CLIENTE. Spec de trabalho vive no repo-alvo ou fora do git do produto; teste do framework não aponta para árvore de outro projeto (fixture em tests/fixtures/, path relativo a ORACFIT_ROOT); default de script nunca é caminho de máquina — use $HOME, $ORACFIT_ROOT ou $ORACFIT_WORKDIR. Categoria fora do manifesto do corte é a que vaza: specs/ chegou ao repo do produto com ~2.500 telefones de terceiros num commit docs: porque não era categoria de lista nenhuma do publish-cut. MECANISMO: bin/check-publico.sh (C1 telefone BR, C2 e-mail fora de allowlist, C3 caminho de máquina em código) roda no check-saude.sh via --oficina (superfície exportável) e como pós-condição do oracfit-publish-cut.sh apply (scan cheio no destino + PRIVATE_DIRS declara specs/, docs/handoffs/, docs/prompts/, incidents/uso/, lessons/ + guarda anti-corte-regressivo por VERSION).** (incidente: `incidents/2026-08-13-oracfit-soldado-no-<repo-cliente>-corte-sem-catego.md`)

---

## Protocolo anti-travamento silencioso

Incidente fundador: `incidents/2026-07-24-travamento-silencioso.md` — 52min perdidos, humano teve que interromper para destravar.

| Camada | Mecanismo | Onde |
|---|---|---|
| Antes | gate de concorrência recusa despachar com outro agente ativo (inclusive TUI aberta) | `bin/pre-dispatch-check.sh` |
| Durante | watchdog mata dispatch sem output (`DISPATCH_SILENT_LIMIT`, default 300s) e impõe teto (`DISPATCH_TIMEOUT`, 1800s), gravando `blocked` no artefato | `bin/dispatch.sh` |
| Qualquer comando | teto explícito, exit 124 ao estourar, matando a **árvore** de processos | `bin/with-timeout.sh` |
| Depois | classificação do travamento em vez de palpite | `fluxos/diagnose/` + `bin/diagnose-hang.sh` |

Modelo lento **não** é morto: ele escreve no log e o contador de silêncio zera. Só morre silêncio real (zero byte novo).

---

## MODELOS

| Modelo | Runner (adapter) | Papel |
|--------|-------------------|-------|
| DeepSeek V4 Flash FREE | `source adapters/opencode/env.sh` | JÚNIOR (padrão) |
| Sonnet | `source adapters/claude-code/env.sh` (ver `adapters/claude-code/CLAUDE.md`, segurança RF-01.1) | ARQUITETO |
| (você) | — | ORQUESTRADOR |

Ranking medido, por tarefa: `RUNBOOK-dispatch.md`. Estado dos providers: `ESTADO-2026-07-27.md`.

`DISPATCH_RUNNER` nunca é comando cru — aponta para `adapters/<cli>/runner.sh` (`core/runner-contract.md`). Ver `adapters/opencode/AGENTS.md` e `adapters/claude-code/CLAUDE.md`.

---

## SCRIPTS (`bin/`, parametrizados por `$DISPATCH_RUNNER` — ver `core/dispatch-spec.md`)

Antes de qualquer script: `source adapters/<cli>/env.sh`.

```bash
bin/session-health.sh [horas]              # dashboard de sessões
bin/decide-context.sh <session_id>         # REUSE / FORK / FRESH
bin/check-cli-config.sh <cli>              # config do CLI antes de usá-lo
bin/pre-dispatch-check.sh <provider_id>    # 0=GO 1=WAIT 2=SWITCH 4=EXHAUSTED
bin/smoke-test.sh <model_id>               # modelo responde?
bin/check-spec.sh <spec>                   # spec sem cláusula anti-invenção reprova
bin/check-spec-facts.py <spec> <workdir>   # o que a spec AFIRMA existir, existe? (--also DIR)
bin/check-oracle.py <spec> <workdir>       # 0=falha certo 1=já passa 2=quebrado (--static-only)
bin/dispatch.sh <model_id> <spec> [nome]   # despacha em background com watchdog
bin/dispatch-escalate.sh <spec> <task>     # 2.1 — vertical: flash → pro → opus
bin/dispatch-batch.sh <batch_file>         # 2.2 — horizontal: N itens, checkpoint + rollback
bin/dispatch-report.sh [--since DATA]      # placar: os 3 ledgers (simples, 2.1, 2.2)
bin/check-import-symbols.py <dir> <spec> <pkg_src>  # símbolo importado existe? (sem node_modules)
bin/watch.sh [task_name]                   # listar dispatches ou tail -f
bin/attach.sh <task_name> [--dry-run]      # TUI (requer ATTACH_TUI=1)
bin/check-output-invencao.sh <spec> <out>  # número inventado no resultado
bin/run-check.sh <cmd>                     # exit code correto (`$?` após pipe mente)
bin/with-timeout.sh <segs> <cmd>           # teto; mata a árvore
bin/critic-guard.sh arm|check|run|watch    # critic é read-only por código: write mata o dispatch (v4)
bin/diagnose-hang.sh [model_id]            # classifica travamento
bin/verify-models.sh                       # mede modelo em sandbox
bin/audit-registry-ids.sh                  # id fantasma no registry
bin/incident.sh new|promote|audit          # incidente → regra
bin/emit-usage-feedback.sh                 # telemetria + incidents/uso/ (auto; ver mapa C #41)
bin/usage-hub.py status|recommend|pick|observe|limits  # tokens/quota built-in (v3.5)
bin/ledger.sh [task_name]                  # histórico de dispatches
bin/oracfit-gui.sh [--target DIR] [--port N]  # GUI local (oracfit gui): home/anéis/dispatches/incidents/registry; read-only exceto score
oracfit hitl <target-dir>                  # calibração HITL: nota real 0-10 por anel fechado (grava delta no ledger)
bin/lint-steps.sh                          # step com comando cru de CLI
bin/check-gguf.sh <arquivo.gguf>           # valida GGUF seguindo o symlink
bin/check-saude.sh                         # bateria inteira de verificação local
```

Antes de commitar qualquer mudança no framework: `bash bin/check-saude.sh`.

---

## USAGE HUB (v3.5 — built-in, sem daemon)

`bin/usage-hub.py` substitui o `~/ai-usage-hub` (daemon HTTP que nunca entregou
dado confiável: API do OpenCode Go inexistente, OAuth Claude bloqueado, limits
todos null). Só fontes locais: `opencode.db` (tokens reais por providerID),
`core/usage-limits.json` (limites calibrados pelo humano — null = só rastreia)
e `.dispatch/usage/observations.jsonl` (rate limit/saldo REAIS, gravados pelo
runner opencode e pela cadeia RF-08).

```bash
oracfit usage status                        # tokens por provider, 5h/day/week
oracfit usage recommend --provider opencode # use/wait/exhausted (exit 0/1/4)
oracfit usage pick --tiers "$DISPATCH_TIERS"  # 1º model ref viável → stdout
oracfit usage limits --set opencode 5h 4000000  # calibrar com valor REAL (regra 37)
```

É isso que o orquestrador consulta para escolher modelo por subagent:
`DISPATCH_MODEL_REF=$(oracfit usage pick --tiers "ref1 ref2 ref3")`.
`pre-dispatch-check.sh` usa o mesmo `recommend` por baixo. Fail-open: sensor
ausente (db, limites) nunca trava o gate; observação de rate limit sempre veta.

---

## CUSTO (regra mental)

- **Seu output**: CARO. Máximo ~30 linhas por ação.
- **Seu input (leitura)**: BARATO. Leia à vontade.
- **Free model output**: GRÁTIS. Use para todo bulk que exige julgamento.
- **Transformação determinística**: nem seu, nem do free — é código.
