# S13 — máquina do The Lineup: medidor $0 auditável (sem backend)

> Implementa a seção "Porta de entrada e medidor" de
> PLANO-LINEUP-2-GOLIVES.md. Dials do dono (tabela de pontos, naming,
> cadência) vivem em ARQUIVO DE DADOS versionado — a máquina não muda
> quando o dial gira. Copy do site NÃO é desta story (espera dials).

## Verified data (dados verificados)

- Template da waitlist existe: `.github/ISSUE_TEMPLATE/tokens-waitlist.md`
  (porta atual, já usada pelo botão do site).
- Tabela v0 proposta no plano: entrar=1, indicação convertida=3,
  run assinada=2, reprodução=3, fake pego=5, custom mode=2
  (PROPOSTA — dial do dono pendente; entra como dado, não como código).
- Export por-contribuidor do bestmodel: JSON com
  `{"generated_at", "contributors": [{"handle", "points", "validated_runs"}]}`
  — contrato congelado AQUI (o lado bestmodel que produz esse arquivo é
  story própria, backlog B-L01).
- GitHub Actions com `on: schedule` disponível no repo público, $0.

Do not invent (nao invente) campos, tiers ou números além dos listados
(alem destes). NUNCA use declare const como workaround — o script lê os
JSON reais ou falha alto.

## Work

1. `data/lineup-points.json` (novo): a tabela v0 do plano como DADO,
   cada linha com campo `"dial": "pending-owner"` — girar o dial é editar
   este arquivo, nunca o código.
2. `bin/lineup-build.sh` (novo, executável): monta `data/lineup.json`.
   Entradas: issues da waitlist (`--issues <json>` no formato do
   `gh api repos/.../issues?labels=waitlist` — array com number,
   user.login, created_at, body) + export por-contribuidor
   (`--export <json>`, contrato acima) + `--points` (default
   `data/lineup-points.json`) + `--out` (default `data/lineup.json`).
   Regras: (a) cada issue vira UMA entrada, ordenada por created_at;
   (b) `referred by: @handle` extraído do corpo por regex; (c) pontos de
   indicação SÓ quando o handle indicado existe na lista E tem
   contribution_points > 0 (anti-sockpuppet do plano); (d) contribution
   points vêm do export (0 quando ausente); (e) tier derivado dos pontos
   totais pela tabela de dados; (f) saída determinística — mesmas
   entradas, mesmo byte.
3. `data/lineup.json` inicial: `{"entries": [], "generated_at": null,
   "machine": "bin/lineup-build.sh"}` — commitado vazio; a Action o
   povoa. NENHUMA posição real existe sem issue real.
4. `.github/workflows/lineup.yml` (novo): cron a cada 6h + workflow
   dispatch; roda `bin/lineup-build.sh` buscando issues via `gh api` e o
   export do bestmodel via URL raw, commita com pathspec explícito.
5. `.github/ISSUE_TEMPLATE/tokens-waitlist.md`: ganha o campo
   `referred by: @handle` (opcional) e o checkbox A3 (`consent`).
6. `tests/test-lineup-machine.sh` (novo): fixtures de issues (com
   referred-by válido, inválido, sem referral) + export fixture; prova:
   ordenação por created_at, anti-sockpuppet (indicado sem contribuição
   não converte), determinismo byte-a-byte, e entrada de issue única.

## Do not touch

A copy pública do site (espera dials), core/modes/, o ledger de dispatch,
LICENSE. O export do bestmodel é OUTRA story (contrato já congelado aqui).

## Verificação

VERIFICACAO: grep -q "lineup" .github/workflows/lineup.yml && grep -q "referred by" .github/ISSUE_TEMPLATE/tokens-waitlist.md

## Barra

Girar um dial (data/lineup-points.json) sem tocar código e ver o
lineup.json refletir — a barra sobe quando o primeiro export real chegar.

## Oráculo

- comando: bash tests/test-lineup-machine.sh && test -f data/lineup.json
- exit esperado: 0 — máquina provada em fixtures, saída determinística,
  anti-sockpuppet ativo. Antes da implementação: 127 (script não existe) =
  vermelho por design.
