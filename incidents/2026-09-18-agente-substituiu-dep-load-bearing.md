---
id: 2026-09-18-agente-substituiu-dep-load-bearing
titulo: agente substituiu dep load-bearing
data: 2026-09-18
recorrivel: sim
regra: nao — virou passo fluxos/dispatch/step-02-prepare.md (nao substitui regra numerada; 16/23/32 ja cobrem o ciclo incidente→protecao)
status: aberto
interage_com: reforca 16 e 23 (falha recorrente vira protecao); reforca 32 (passo declara mecanismo); reforca 26 (ausencia do tree argos-opt so depois de busca em VM+GitHub+crates.io); nao supera 4.6 (decisao de produto: manter argos-opt)
---

# agente substituiu dep load-bearing

## Sintoma

Checkout publico de https://github.com/carl0sfelipe/bestmodel nao builda
`cli/benchmark-probe`: o manifesto pede `argos-opt = { path = "../../../argos-opt" }`
e esse diretorio nao viaja com o git. Um agente (commit Manus Agent,
sha e94e662e4b3a997fcc478cd4500590629f9b61df) abriu
https://github.com/carl0sfelipe/bestmodel/pull/2 alegando correcao.

O PR troca argos-opt pelo crate publico optimizer 1.0.1 (crates.io,
raimannma/rust-optimizer), recoloca o probe em `members`, e reescreve
`tuning_search.rs`. CI rust-cli do PR ficou verde (~2 min) e
`tpe_beats_random_baseline` passou. Nao mergear o PR 2.

## Causa

Duas causas distintas — nao misturar.

1. Buraco de produto (real): argos-opt vive so em `~/Work/argos-opt`
   (main `31feea6`, sem remote, `publish = false`). Evidencia:
   `docs/go-live/ESTADO-SESSAO.md` e `docs/go-live/UNLOCK-FABLE-2026-08-31.md`
   neste repo; `cli/benchmark-probe/Cargo.toml` no bestmodel main. O
   unlock de 2026-08-31 tirou o probe do workspace (`exclude`) para o
   CI do canirunit nao morrer; o CLI de captura continua inbuildavel
   num clone limpo.

2. Correcao errada (PR 2): o agente tratou "nao consigo usar o produto"
   como licenca para trocar o otimizador do dono. Decisao 4.6 em
   `docs/go-live/DECISIONS-E6-FABLE-FECHAMENTO.md` e manter argos-opt.
   Evidencia no diff do PR (arquivo `cli/benchmark-probe/src/tuning_search.rs`):
   `unique_params` move duplicata para vizinho threads/ctx, mas
   `study.tell` recebe o trial original — o TPE aprende ponto A com
   perda de B. Stub TPE caiu de 406.8 para 395.6275 tok/s (seed 42 /
   60 trials); random de 329.4 para 309.2427 (RNG trocado). Barra 355.0
   nao foi re-pinnada ao midpoint. Comentario de
   `.github/workflows/ci.yml` ainda descreve o exclude depois de o
   probe voltar a `members`.

Busca pelo tree argos-opt neste VM (regra 26): nao encontrado em
/home/ubuntu/Work, /workspace, /opt, /tmp; `gh api users/carl0sfelipe/repos`
nao lista argos-opt; crates.io `/api/v1/crates/argos-opt` HTTP 404.
Nao determinada a existencia de copia privada nao listavel por esta
integracao.

## Correção aplicada

Neste repo (llms.surf), nao no bestmodel:

- Recusar o merge do PR 2. Nao rebasear em cima dele.
- Passo em `fluxos/dispatch/step-02-prepare.md`: dependencia load-bearing
  fora da arvore nao substitui a biblioteca do dono por crate homonimo.
- Caminho A quando o tree `31feea6` existir: git-dep pinada
  `argos-opt = { git = "https://github.com/carl0sfelipe/argos-opt", rev = "31feea6" }`,
  probe de volta a `members`, comentario do CI honesto, L03A/TPE intocados
  (406.8 / 329.4 / 355.0). Vendor so se o dono recusar remote.
- Git-dep NAO aplicado nesta sessao: source ausente. Reconstruir a API
  a partir do probe seria um terceiro otimizador, nao manter argos-opt.

## Pode acontecer de novo?

Sim — qualquer agente que clone um produto com path dep privada e tenha
permissao de abrir PR vai preferir o crate publico que "compila" ao
caminho (a)/(b) do dono. O passo no prepare cobre o orquestrador
llms.surf; nao impede um agente de outro harness (Manus, Cursor cloud
no repo bestmodel) de repetir. Protecao no bestmodel = git-dep ou
vendor do tree original, ainda bloqueada neste host.
