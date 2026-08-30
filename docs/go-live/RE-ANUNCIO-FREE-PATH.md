# RE-ANÚNCIO: caminho free íntegro (E5 fechado) — 2026-08-31

> Requisito da definição de pronto (DECISIONS-E5): o re-anúncio cita o
> número do audit ANTES e DEPOIS — a mesma régua que abriu o incidente
> o fecha. Tudo aqui medido nesta máquina, nunca estimado.

## A régua

- **ANTES**: `bin/audit-registry-ids.sh` → **46/69 ids mortos**
  (21 NAO-ENCONTRADO + 25 FANTASMA). Era essa a podridão que o caminho
  free servia em silêncio — o default `tier:cheap` apontava para um id
  com hint morto.
- **DEPOIS**: **0/23 mortos** (19 EXISTE + 4 PROVAVEL). Os 46 saíram em
  um commit (afeb8ed); o git history é a lista retired (D1).

## Os 6 mecanismos (todos com gate, todos commitados)

| Mecanismo | O que faz | Commit |
|---|---|---|
| M4 | `tier:cheap` = lista fallback ordenada do catálogo carimbado (keyless primeiro); `run-with-fallback` expande `tier:*` na cadeia | 2662211 |
| M2 | `audit-registry-ids.sh --stamp` grava `id_status` no registry; consumidores recusam morto na porta | 2662211 |
| M3 | 46 mortos fora; consumidores (modos, defaults, escada, docs) migrados; B2 pago | afeb8ed |
| M5 | `lib-free-credentials.sh` = leitora ÚNICA de credencial, POR ARQUIVO (env herdada não existe para o caminho free); gate de exclusividade em 3 anéis | b7100af |
| M6 | `provider_efetivo` + `allowlist_status` na linha do ledger; allowlist = dial do dono | 06b1a86 |
| M1 | `sync-free-catalog.sh`: feed JSON estruturado → valida → move atômico; falha mantém snapshot (R2) | 05371c3 |

Gate que fecha: `bin/test-free-path.sh` (710683d) — 13 pernas, incluindo
**dispatch com envs pagas ENVENENADAS** (isca em AWS_*/OpenRouter/Groq/
NVIDIA/DeepSeek: run fecha pela perna keyless, allowlist ok, zero isca
vazada) e **allowlist adulterada → violado**. Saúde: 20/20.

## R1 — a promessa "sem chave", medida antes de re-anunciar

- **Perna zero-key**: os 2 primeiros da fila (`mimo-v2.5-free`,
  `nemotron-3-ultra-free`) são genuinamente keyless — tier bundled do
  opencode autenticado. **Chamada real medida em 2026-08-31: ambas
  responderam em ~15-16s, sem criar chave nenhuma, custo zero.**
- **Perna free-key**: 9 refs OpenRouter `:free` vivos (pricing 0 MEDIDO
  no feed em 2026-08-31, incluindo ctx 1M do nemotron-550b e o
  free-router). Exigem credencial OpenRouter armazenada; sem ela a cadeia
  pula com aviso alto — nunca tenta sem chave.
- A claim do README ("Try it in 2 minutes — no API key") é sobre o STUB
  e segue verdadeira sem mudanças; a claim nova permitida é a perna
  zero-key medida acima.

## Copy pública (R3 — regra que fica)

- É **limit-aware dirigido por evento real** (exit 2/4 observado pela
  cadeia RF-08 → usage-hub), NÃO "quota-aware": nada contabiliza saldo
  consumido. A palavra "quota" NUNCA entra em copy pública enquanto não
  existir contador de consumo.
- Providers free do feed podem treinar sobre o tráfego (R4): a allowlist
  default (`data/free-provider-allowlist.json`: opencode + openrouter) é
  dial do dono — editar o arquivo é a decisão explícita, nunca efeito
  colateral da ordem do feed.

## Como usar (o que muda para quem despacha)

```bash
bin/dispatch.sh tier:cheap spec.md minha-task          # cadeia free inteira
python3 bin/lib-oracfit-mode-loader.py resolve-tier tier:cheap   # a fila, em ordem
bin/sync-free-catalog.sh                               # regenera o catálogo (atômico)
bin/test-free-path.sh                                  # prova de integridade
```

Modos YAML podem voltar a usar `tier:cheap`/`tier:mid` em `model_ref` —
nenhum tier cru chega mais a runner (B2 fechado pelo mesmo mecanismo).
