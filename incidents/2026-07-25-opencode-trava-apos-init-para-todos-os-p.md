---
id: 2026-07-25-opencode-trava-apos-init-para-todos-os-p
titulo: opencode trava após "init", para todos os providers — causa não determinada
data: 2026-07-25
recorrivel: sim
interage_com: 27 (é o "modo 2" dela, agora com ponto de parada localizado); 22 (modo (c) silêncio sem erro); 12 (só é visível porque todo comando tem teto). RISCO: enquanto não resolvido, TODO dispatch a modelo free está bloqueado — o framework inteiro depende deste runtime.
regra: 29
status: promovido
---

# opencode trava após "init", para todos os providers — causa não determinada

## Sintoma

`opencode run --model <qualquer>` pendura até o teto. Vale para Zen, OpenRouter,
groq e NVIDIA. Nenhuma sessão é criada, nenhum erro em stderr, nenhum erro no
banco. `opencode --version` e `opencode models` (que não criam sessão) respondem
normalmente.

**Regrediu durante a sessão:** às 15:30 uma varredura mediu 19 de 21 modelos free
com sucesso, em 2-6s cada. Por volta das 17:00, nem o campeão respondia.

## Causa

**Não determinada.** Ponto de parada localizado com `--log-level DEBUG`: trava
logo após a última linha

```
level=INFO message=init
```

ou seja, depois de carregar todos os configs e antes de criar sessão.

**Hipóteses testadas e ELIMINADAS** (cada uma com teste próprio):

| Hipótese | Teste | Resultado |
|---|---|---|
| Banco/estado corrompido (982MB, 120k eventos) | `XDG_DATA_HOME` novo e vazio | trava igual |
| Plugins externos | flag `--pure` | trava igual |
| Skill instalada pelo Agent Vault | movida para fora | trava igual |
| Agente concorrente / órfãos | `diagnose-hang.sh` | zero de ambos |
| Rede | `curl openrouter 200 em 0,13s` | rede boa |
| TLS / CA do proxy | `NODE_TLS_REJECT_UNAUTHORIZED=0` | trava igual |
| Credencial | curl direto ao provider com a chave | HTTP 200 |
| Lock de banco | leitura de 120k linhas em 0,3s; WAL zerado | sem lock |

## Correção aplicada

Nenhuma. Registrado sem solução, de propósito — inventar causa aqui seria repetir
o erro que este framework passou o dia inteiro corrigindo.

Contorno enquanto durar: o endpoint HTTP dos providers responde normalmente
(comprovado em NVIDIA via `agent-vault run -- curl`, HTTP 200). O que está
quebrado é o **runtime agêntico**, não o acesso aos modelos.

## Pode acontecer de novo?

**Já é recorrente** — 7 ocorrências em dois dias, sempre com o mesmo padrão:
funciona no começo da sessão, degrada com o uso, e nenhuma das causas óbvias
se confirma. É o maior bloqueio operacional do framework hoje: sem este runtime,
nenhum dispatch a modelo free acontece.
