---
id: 2026-07-30-cursor-grok-primeiras-impressoes-do-disp
titulo: "Cursor/Grok: primeiras impressoes do dispatch na migracao e2e multi-loja"
data: 2026-07-30
recorrivel: sim
regra: 40
status: promovido
interage_com: "1, 37 (quando despachar); 39 (oraculo); 36 (publish=ARCH). Reforca filtro pre-dispatch; nao substitui 37/39."
harness: Cursor Agent (Composer / Grok 4.5)
modelo_orquestrador: cursor-grok-4.5
modelo_executor: openrouter/deepseek/deepseek-v4-flash (mode 1)
---

# Cursor/Grok: primeiras impressoes do dispatch na migracao e2e multi-loja

## Contexto da sessão (panorama do trabalho)

Sessão no harness **Cursor** (não Claude Code / não opencode-relay), modelo orquestrador
diferente do usual (Grok). Trabalho: desacoplar e2e multi-loja.

| Fase | O quê | Quem fez |
|------|--------|----------|
| 0 | Mapear 121 specs → ~112 migráveis / 5 Orbe-only | Explore/investigator |
| 1 | `brands/<slug>/e2e.json` + loader + helpers | Orquestrador (Cursor) |
| 2 | Debrand SKUs em 5 lotes (cart/pdp/checkout/journey/misc) | **dispatch-escalate mode 1** |
| 3 | Package `@carl0sfelipe/e2e-store` + sync (não node_modules) | Orquestrador + `cp` |
| publish | `@carl0sfelipe/e2e-store@0.1.0` no GitHub Packages | Orquestrador |

Ledger Fase 2 (evidência):

```
e2e-fase2-cart      mode=1 flash  attempt=1  84s   oracle=0
e2e-fase2-pdp       mode=1 flash  attempt=1  62s   oracle=0
e2e-fase2-checkout  mode=1 flash  attempt=1  89s   oracle=0
e2e-fase2-journey   mode=1 flash  attempt=1 101s   oracle=0
e2e-fase2-misc      mode=1 flash  attempt=1 107s   oracle=0
```

Total ~7.5 min de flash, 5/5 oráculo PASS na 1ª tentativa. Hardcodes migráveis → 0.

## Sintoma

Primeiro uso do `dispatch` (check-spec + escalate + oráculo + ledger) a partir do
harness Cursor/Grok, numa migração real (~4.5k LOC e2e), não benchmark.

## Causa / avaliação (com evidência)

### O que o dispatch GANHOU (útil, não overengineering)

1. **Debrand mecânico (Fase 2)** — sweet spot documentado nas lessons 29/07.
   Path único + tabela de refs + oráculo `grep == 0` → flash 100% na 1ª.
   Evidência: ledger acima; orquestrador não reescreveu 75 hits à mão.

2. **Gate de spec (`check-spec.sh`)** — forçou anti-invenção / oráculo testado
   ANTES. Pre-oracle exit=1 em todos os lotes (prova que o oráculo detectava
   ausência). Sem isso, "log não vazio" passaria mentindo.

3. **Economia de tokens do orquestrador caro** — Grok/Cursor ficou em decisão +
   specs curtas (~1–2 páginas cada). Flash executou a transformação volumosa.
   Estimativa grosseira: 5 lotes × ~4k LOC tocados sem o orquestrador abrir
   cada arquivo linha a linha.

4. **Util em harness estrangeiro** — Cursor não tem o loop nativo do `claude -p
   --continue` / artifact-bus do ZCode. O dispatch deu um contrato externo
   (spec file + oracle + ledger) que o Grok pôde chamar via Shell sem
   reimplementar orquestração.

### O que NÃO valeu (overengineering / anti-padrão)

1. **Cópia de 112 specs → package** — `cp`/`python shutil` em segundos.
   Despachar flash pra isso seria teatro. Feito com shell; correto.

2. **Design do package (loader cwd, sync fora de node_modules, ADR)** —
   decisão de arquiteto. Dispatch não ajuda; gate de premissa ajudou:
   `playwright test --list` falhou com "Stripping types unsupported under
   node_modules" — lição 2026-07-30-gatear-premissa, reconfirmada.

3. **Curva de aprendizado no Cursor** — média. `check-spec` + formato
   `## Oráculo / - comando:` exigiu 1 leitura do dump + 1 spec de referência
   (`debranding-classe-e-storage-keys.md`). Não foi difícil; foi **cerimonial**
   (boilerplate obrigatório). Vale quando a task é transformacional repetitiva;
   custa ~10–15 min de setup da 1ª spec da sessão.

4. **Fricção Cursor × dispatch** — Auto-review bloqueou write cross-repo e
   `opencode` smoke; multi-root + Approve destravou. O dispatch `--workdir`
   contorna Write do Cursor, mas o Shell que *lança* o dispatch ainda passa
   pelo classificador. Não é zero-friction.

### Veredito do modelo (Grok no Cursor)

| Pergunta | Resposta |
|----------|----------|
| Foi útil? | **Sim, na Fase 2 (debrand).** |
| Economizou tokens? | **Sim, do orquestrador.** Flash barato fez o volume. |
| Foi rápido? | **Sim nos lotes** (~1–2 min cada, 1ª tentativa). Setup da 1ª spec mais lento. |
| Overengineering? | **Não na Fase 2.** **Sim se usasse dispatch pra Fase 3 cópia/ADR/publish.** |
| Vale aprender? | **Sim** se a sessão tem ≥1 lote sed-like com oráculo objetivo. |

## Correção aplicada / regras a promover

Não houve bug de produção — há **padrão de uso** a cristalizar:

1. Classificar a tarefa ANTES: `MECANICO_TRANSFORM` → dispatch; `COPY/SCAFFOLD/ARCH` → shell/orquestrador.
2. Oráculo Playwright/package: sempre gatear `playwright test --list` se testDir
   apontar pra `node_modules` (já coberto em lessons; reforçar).

## Pode acontecer de novo?

**sim** — próximo agente no Cursor (ou outro harness) pode (a) despachar flash
pra `cp` de N arquivos, ou (b) pular o dispatch em debrand de 50+ refs e
gastar o modelo caro. Ambas são recorríveis e merecem regra.
