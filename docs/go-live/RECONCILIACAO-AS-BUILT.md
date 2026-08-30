# Reconciliação as-built (2026-08-29) — ponte plan → implementação

> Os docs canônicos do Fable (`DECISIONS-D1-D10.md`, `CUSTOM-MODE-CARD.md`,
> `JOURNEY-1H.md`, `COPY.md`, `docs/SMOKE-WITH-FIRE.md`) entram **verbatim**,
> como escritos. Este arquivo é só o mapa entre o que eles citam pelo nome do
> PLANO e onde a cobertura vive AS-BUILT — para quem seguir uma referência
> não bater em arquivo que não existe.

## Specs: numeração do plano × numeração as-built

O pack original (specs S1–S6 do Fable, árvore dele) foi implementado à mão
com specs as-built de nomes diferentes, que ficaram (o gate lê esses
filenames — decisão de merge registrada):

| spec do plano (Fable) | as-built no main | cobertura real |
|---|---|---|
| S1-first-wave-clean-clone | `S1-promessa-2min.md` + residual | `tests/test-first-wave.sh` (clone virgem) |
| S2-tui-first-wave-default | `S2-aliases-surf.md` | seções D2/TUI do gate local |
| S3-mode-init-surf-scaffold | `S3-ficha-syntax-custom.md` | `examples/` + validate/lint no gate |
| S4-mode-share-add | `S4-mode-share-add.md` (mesmo nome) | `mode add/share` + round-trip no gate |
| S5-site-v4-home | `S5-god-modes-tokens.md` | `tests/test-site-honesty.sh` + seção tokens |
| S6-go-live-local-gate | `S6-higiene-corte.md` | o gate em si: `tests/test-go-live-local.sh` |

Suítes citadas na matriz que não existem como arquivo próprio (a cobertura
está em seções do gate local, não em suítes separadas):
`tests/test-mode-init-scaffold.sh`, `tests/test-mode-share-add.sh`,
`tests/test-tui-first-wave.sh`.

## Numeração viva das stories pendentes

- **S7** (`S7-single-flight-status.md`) e **S9** (`S9-ntfy-run-notify.md`)
  são do Fable, congeladas, aguardando implementação na ordem do SMOKE
  (S9 → S7).
- **S8** (`S8-owner-question.md`) é as-built (implementada, mergeada).
- A ordem oficial é a do `docs/SMOKE-WITH-FIRE.md` canônico.

## Ordem de fogo do gate local (noção de spec congelada)

`tests/test-go-live-local.sh` distingue: specs **implementadas** (oráculo
deve estar VERDE) e specs **congeladas** (oráculo VERMELHO é o estado
correto até implementar — dogfood do fluxo: spec congelada antes do código).
S7 e S9 estão congeladas; ao implementar, movem para o conjunto verde.

## Arquivado

`ESCALACAO-FABLE-GO-LIVE.md` — a escalação original da manhã (origem do
pack), arquivada AQUI (docs/go-live, categoria privada do corte) em vez de
`docs/` raiz, que é superfície pública.
