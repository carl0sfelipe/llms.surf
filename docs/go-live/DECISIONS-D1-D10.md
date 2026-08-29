# Decisões D1–D10 do go-live — matriz com fatos verificados

> Ordem de trabalho do go-live, não produto (D8). Cada decisão lista o fato
> verificado que a sustenta — caminho e, onde cabe, o gate mecânico que a
> impõe. Nada aqui é aspiração: tudo neste corte está implementado e com
> oráculo verde (ver `specs/S1..S6` e `tests/test-go-live-local.sh`).

| # | decisão | fato verificado | mecanismo |
|---|---|---|---|
| **D1** | A promessa de 2 minutos é o gate zero: nenhum tráfego sobe antes de S1 verde. | O quickstart do site (`site/app.js`) termina em `bin/llms-surf start`; em HEAD esse comando despachava `specs/oracfit-smoke-normal.md` — e `specs/` inteiro ficou fora do corte público (regra 52). Seis pontos do tree apontavam para o arquivo morto: `bin/oracfit` (first-proof), `bin/test-oracfit-tldr.sh:20`, `bin/release-gauntlet-verify.sh:72` **e `:80`** (uma segunda spec morta, `oracfit-smoke-unlock-plan.md`, achada nesta sessão), `tests/test-gui-remote.sh:63`, `tests/test-protected-paths.sh:14`. | As duas smokes recriadas; `check-spec` + `check-oracle` + stub dispatch verdes; `dispatch-stages.sh` agora cria `.dispatch` antes do preflight (mesmo invariante do dispatch-mode). Oracle: S1. |
| **D2** | Os ids do tree ficam; a UI ganha aliases de surf: `paddle` (normal), `tow` (unlock_plan), `surfcheck` (ui_visual_qa). Alias é apelido, nunca modo-irmão. | 20 modos em `core/modes/` (conta que o teste de honestidade do site já cobra); colisão de id é incidente conhecido (colisão hefesto, lint de shadow no loader). | Mapa único `MODE_ALIASES` em `bin/oracfit`; `oracfit alias` resolve/recusa (exit 2); `run <alias>` resolve antes do runtime — YAML, ledger e eventos gravam o id canônico. Oracle: S2. |
| **D3** | Syntax custom = subconjunto da gramática do loader atual. Zero schema novo. | `bin/lib-oracfit-mode-loader.py` já define ALLOWED_ROOT/ALLOWED_STAGE/ROLES e valida ANTES de todo run (dispatch-mode chama o mesmo loader). | Ficha `CUSTOM-MODE-CARD.md` + 2 YAMLs de exemplo que validam e lintam no loader real (a 1ª versão dos exemplos foi REPROVADA pelo lint de claims — o gate funciona). Oracle: S3. |
| **D4** | O oráculo vive na spec da task, não no YAML. | Regra 46 (crase no `- comando:` vira exit 127 fantasma) e regra 50 (oráculo com régua de linhas induz padding) são incidentes deste repo; o YAML com `oracle: true` só declara que a spec será julgada por comando no disco. | Ensinado na ficha (regra 1); as smokes e os exemplos seguem o formato. |
| **D5** | Privacidade é localização, não campo. Público = postar o próprio YAML. | Não existe campo `private:` no schema do loader; o overlay de workdir (AD-16) já garante que `core/modes/` local nunca sai da máquina. | `oracfit mode share <id>` (saída, zero rede) + `oracfit mode add <yaml>` (entrada: validate → lint → instala no overlay; recusa sobrescrita divergente) + template de issue `share-your-break.md`. Oracle: S4. |
| **D6** | Tokens a custo: seção honesta. Sem preço, sem data, sem número de demanda anunciado. Unlock mecânico: demanda lida da lista + throughput medido no registry/ledger. | `tests/test-site-honesty.sh` já recusa número decorativo no site; `llms.txt` já diz "There is no hosted inference product here. Do not invent $/M or tok/s." | Seção `#tokens` em `site/index.html` + bloco em `llms.txt`: "no tokens for sale. a waitlist exists; a number doesn't." Mudar o texto sem mudar o mecanismo é violação registrada na spec S5. |
| **D7** | Os 17 god modes ficam no git e no CLI, saem do default da TUI. | 20 YAMLs em `core/modes/` − o trio surf (normal, unlock_plan, ui_visual_qa) = 17. `oracfit modes` continua listando tudo. | TUI constrói o trio da saída de `oracfit alias` (uma fonte só) e diz onde ficam os god modes; god mode continua rodando por id direto. Oracle: S2+S5. |
| **D8** | `docs/go-live/` é ordem de trabalho, não produto — entra no PRIVATE_DIRS antes do próximo corte. | Categoria fora do manifesto é a que vaza (incidente 2026-08-13: ~2.500 telefones de terceiros entraram porque `specs/` não era categoria de lista nenhuma). | `docs/go-live` em PRIVATE_DIRS de `bin/oracfit-publish-cut.sh` e em PRIVADO de `bin/check-publico.sh`, em sincronia. Oracle: S6. |
| **D9** | Veículo da waitlist: template de issue no GitHub. O N que destrava a venda de tokens é medido, não inventado. | Templates vivem no repo público (`.github/ISSUE_TEMPLATE/`) — a lista é sensor, não propaganda; volume de demanda vira contagem de issues, throughput vira leitura do ledger. | `.github/ISSUE_TEMPLATE/tokens-waitlist.md` com os compromissos escritos (nenhum preço antes de custo medido; nenhum N citado enquanto só existir na lista). **N decidido pelo dono em 2026-08-29: 25 contas GitHub distintas** — a custo tem margem zero, então N só compra prova de demanda de estranhos antes de construir o metering; 25 passa do alcance do círculo de amigos e não trava o flywheel. O N é dial de política, não medição — o dono pode girar; a classe do critério fica. O N não vai para copy pública antes de atingido. |
| **D10** | Ímã OSS: `bestmodel.run` fica como está. Flip de LICENSE é irreversível e não bloqueia este lançamento. | O site já diz a verdade: "LICENSE is proprietary. Do not call this open source." (`site/llms.txt`, `site/index.html` §agent-dont). O dispatcher vendido nesta landing é ESTE repo. | Nenhum código; decisão de dono registrada. Reabrir só como decisão explícita de licença, nunca como copy de marketing. |

## Confirmações do dono (2026-08-29, pós-implementação)

1. **Matriz validada por conteúdo** — sem implementação contra a qual validar na superfície revisada; nada no tree a contradiz.
2. **N da waitlist = 25** (gravado no D9 acima, com o racional).
3. **Thread "share your break" aprovada**: uma Discussion fixada no lançamento,
   semeada com os dois YAMLs da ficha (`examples/glassy.yaml`,
   `examples/outside_set.yaml` neste tree).
4. **Promote autorizado e EXECUTADO**: o incidente 2026-08-27 (3 despachos
   sobrepostos + veredito por grep cru) virou a **regra 53** — os 3 mecanismos
   (flock single-flight por workdir, `status --task` canônico, imprint sha256
   no green) declarados como dívida pendente (regra 32), interage_com 24, 31,
   42, 44. A revisão de 2026-08-29 que motivou esta sessão é a regra 53 em
   ação.
5. **S7 oferecida pelo fable** (mecanismos 1+2 na janela do go-live) — pedida.

## Frase única do anúncio (confirmada pelo dono)

> Cheap AI models do the work. A mechanical oracle proves it shipped.
> Clone it — 2 minutes, no API key.

Detalhe de copy em `COPY.md`. Jornada do estranho ao viciado em `JOURNEY-1H.md`.
Checklist de go-live (Phase A + Phase B) em `docs/SMOKE-WITH-FIRE.md`.
