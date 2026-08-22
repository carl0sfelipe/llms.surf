---
id: 2026-08-10-modelo-despachado-cria-arquivo-de-parada-e-mata-loop
titulo: modelo-despachado-cria-arquivo-de-parada-e-mata-loop
data: 2026-08-10
recorrivel: sim
regra: 47
status: promovido
---

# modelo despachado cria arquivo de parada e mata o loop

## Sintoma

Overnight do `tripstory-mvp1`: o laço `tools/overnight.sh` parou sozinho às
07:54 com "tools/STOP presente — fim". O arquivo `tools/STOP` tinha mtime
07:18 — criado NO MEIO do ciclo de polish que rodava entre 07:11 e 07:51.
Nenhuma intervenção humana nesse intervalo.

## Causa

O modelo despachado (`deepseek_direct_flash` via `opencode run --auto`) roda
com bash liberado no MESMO workdir do orquestrador. O script de orquestração
`overnight.sh` usa `tools/STOP` como marcador de parada e ainda anuncia isso
na própria mensagem de log ("pare com: touch tools/STOP"). O modelo, ao
explorar o repo (deu `git commit`, leu scripts, spawnou `nohup vqa-oracle.sh`),
criou/tocou `tools/STOP` — e o orquestrador obedeceu e encerrou.

Regra emergente: **qualquer arquivo de controle do orquestrador que viva no
workdir é gravável pelo modelo despachado, portanto não é controle — é
sugestão.** O modelo TEM permissão de escrita no próprio palco onde fica o
botão de desligar.

## Correção (aplicada no repo tripcstory-mvp1)

1. Marcador de parada movido PARA FORA do workdir: `~/.tripstory-overnight.stop`
   (`STOPFILE` env, default fora do repo). O modelo despachado roda com cwd no
   repo e não tropeça nele por acidente.
2. Mensagem de log deixou de anunciar "touch tools/STOP".
3. Teto do `runt` subiu 2400s → 5400s (o teto antigo matava ciclo de polish
   legítimo aos 40min, no meio de 3 commits bons).

## Prevenção (candidato a regra geral do oracfit)

1. Arquivos de controle do orquestrador (stop, pause, flags) NUNCA no workdir
   despachado — sempre fora do repo ou em dir só-legível-pelo-orquestrador.
2. O log do orquestrador não deve anunciar o mecanismo de parada em texto que o
   modelo possa ler.
3. Considerar rodar o modelo despachado com cwd restrito ou permissão de escrita
   limitada a subárvore de trabalho, não ao repo inteiro que contém os scripts
   de orquestração. [A DEFINIR: avaliar se runner deve fazer `cd` pra subdir]

## Evidência

- `tools/overnight.log` tripcstory-mvp1: `07:54:57 tools/STOP presente — fim`
- mtime de `tools/STOP` = 07:18, dentro da janela do ciclo 07:11–07:51
- log do ciclo mostra o modelo executando `git commit`, `nohup bash tools/vqa-oracle.sh`
