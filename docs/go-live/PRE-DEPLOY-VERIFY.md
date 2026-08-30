# Verificação pré-deploy — 2026-08-29

> Tudo o que dá para provar ANTES do host público, provado e registrado
> contra um commit. O que só dá no host está listado no fim — é a Phase A
> do fable (docs/SMOKE-WITH-FIRE.md §A2), que roda contra a origem real.

## Commit verificado

`main` pós-merge de tudo (S1–S9 + backlog) **+ fix de portabilidade do
vision QA** (ver abaixo) — hash no commit que carrega este arquivo.

## Resultados (todos exit 0, medidos nesta máquina)

| prova | resultado |
|---|---|
| **A1 — gate local** (`tests/test-go-live-local.sh`) | **39/39 pass, exit 0** |
| **Bateria completa** (`bin/check-saude.sh`) | **17/17 checagens, exit 0** |
| **Todas as suítes** (34 em `tests/` + 6 em `bin/test-*`) | **40/40 verdes, zero falhas** |
| **Clone do ORIGIN real + quickstart** (cronometrado) | **3,3 s** até `status: pass` com `stub_ok` no disco (promessa do anúncio: <120 s) |
| **Caminho custom E2E no clone virgem** (A2.4) | `mode init` → `validate` OK → `lint` OK → `run` (stub) `pass` → `mode share` imprime YAML pronto p/ postar → `status --task` devolve o JSON canônico |
| **Onda 1 e 2 no stub** (A2.3) | `run normal` e `run unlock_plan` fecham `pass` (gate + suítes owner-question/single-flight) |
| **Onda 3 — vision QA** (A2.3) | script path **roda em Linux** (exit 0, findings JSONL); pernas de modelo exigem provider real — sem chave, `FALHOU_5_TENTATIVAS` registrado honesto (dívida YAML-vs-script documentada no SMOKE) |
| **Site servido local** | **11/11 recursos HTTP 200** (`/`, index, readme, incidents, v4-plan, llms.txt, css, app.js, journey.js, logo.svg, og.png) |
| **Copy-button** | carrega a URL real de clone (`github.com/carl0sfelipe/llms.surf.git`) |
| **TUI wizard completo** (pipe) | spec → task → paddle → stub → dispatch → **"✓ task task-tui: oracle green"** → `status --task` = `pass` com run_id |
| **S9 notify** | 7/7 contra fake server local (suíte) — sem rede externa |
| **S7 single-flight** | 11/11 (recusa exit 6, takeover de órfão, veredito canônico) |
| **S8 pergunta do dono** | 8/8 (pausa exit 7 → resume → pass; 1 pergunta/run) |

## Fix de portabilidade (achado DESTE pré-deploy)

`bin/dispatch-vision-ui-qa.sh` e `bin/dispatch-vision-map.sh` usavam
`base64 -b 0 -i` — sintaxe BSD/macOS. Em Linux (GNU coreutils) `-b` não
existe: **o vision QA nunca rodaria em máquina Linux nenhuma.** Corrigido
para a forma portátil (`base64 < f | tr -d '\n'`: stdin funciona nos dois,
`tr` normaliza o wrap de 76 colunas do GNU). É exatamente o caso que a
A2.3 existe para pegar — honestidade sobre cobertura.

## O que SÓ dá para provar com o host público (resta)

1. `curl` 200 em `/` e `/llms.txt` na origem pública, com
   `test-site-honesty.sh` verde no commit deployado.
2. Clone fresco numa máquina que NUNCA viu o repo (aqui simulei da minha
   máquina, do origin real — 3,3 s).
3. Clique real em nav/copy no browser; primeiro scroll = anúncio.
4. O log `docs/v1-smoke-log.md` — a Phase A do fable.

## Veredito local

**Verde para deploy.** Nenhum vermelho em nenhuma superfície local; o único
achado (portabilidade do vision) foi consertado e provado nesta sessão. O
risco restante mora no deploy/DNS, não no tree.
