# ESCALADA-2 — as 5 decisões, congeladas (Fable, 2026-08-30)

> Contexto: a seleção de modelo por task É o produto; a 3090/Vast está
> SUSPENSA pelo dono ("nada sobe") — estas decisões valem no papel agora
> e destravam trabalho local ($0) já; o que exige GPU espera o "sobe".

## E2-D1 — O gate da palavra "fine-tune"

CONGELADO: "fine-tune/tuned" só vira claim de presente quando existirem,
no tree, TRÊS coisas ao mesmo tempo:
(a) entrada no model-registry.json de um modelo tunado de verdade servido
    da GPU do dono (id com procedência — ver E2-D2), com evidência de
    serving (endpoint registrado + run no ledger);
(b) medição before/after em **N=5 tasks reais** (5 specs distintas com
    oráculo, mesmo protocolo e seed, base e tunado no ledger), com o
    tunado vencendo na métrica do domínio — formato: campos
    `tuned_from` e `measured_delta` na entrada do registry, apontando os
    run_ids do ledger;
(c) oráculo da S10 verde.
Até lá, a copy diz exatamente o que diz hoje: "domain-tuned … as NEXT",
gated. N=5 porque é o menor N que sobrevive a um outlier sem exigir
paper; o formato reusa registry+ledger que já existem — zero superfície
nova de verdade.

## E2-D2 — Binding custom mode → modelo tunado

CONGELADO: **nenhuma chave nova de schema, nenhum tier novo.** Convenção
de id no registry: `tuned/<dominio>-<base>`, usável onde `model_ref` já
aponta para id de registry hoje. Tier continua sendo CAPACIDADE
(cheap/mid/expensive/vision); tuning é PROCEDÊNCIA, e procedência mora no
registry, não no schema do loader. O loader ganha só UM check de lint
(S11): `model_ref` começando com `tuned/` precisa existir no registry —
anti-fantasma, mesma família da regra 45. Racional: a sintaxe pública
mínima é decisão D3 do go-live; schema não incha por roadmap.

## E2-D3 — Plano de serving na 3090/Vast

CONGELADO: um llama-server por DOMÍNIO ATIVO (modos compartilham
domínio), nunca por modo — modos são muitos e baratos, domínios são
poucos e caros. O adapter llamacpp já fala com endpoint OpenAI-compatible
(precedente vast3090 do dogfooding 2026-08-27: servir modelo próprio já
aconteceu). O que falta: entrada de registry por endpoint servido e o
runbook S12 nascido das lições MEDIDAS da skill Vast do dono (canário de
custo obrigatório, teto diário, inet_down_cost no olho, kill de zumbi,
host doente). SUSPENSO na prática até o dono devolver o "sobe" — decisão
de papel, gasto zero.

## E2-D4 — Dogfood antes da venda

CONGELADO: é MEDIÇÃO, e é obrigatória. O dono e os modos dele rodam no
modelo tunado, na GPU dele, ANTES de qualquer venda ao N=25 — e essas
runs de dogfood SÃO as medições exigidas em E2-D1(b). Nenhum número de
tuning aparece em copy sem ter nascido do ledger do dogfood. Vender antes
de medir é o pecado que a régua existe para impedir.

## E2-D5 — Sequência

CONGELADO: specs na ordem S10 (registro+medição) → S11 (lint do binding)
→ S12 (runbook Vast). Implementação na ordem que a suspensão permite:
**S11 primeiro** (100% local, $0, destrava o lint antes do primeiro
`tuned/` existir), S10 em seguida (harness com stub prova a máquina de
medir; a medição real espera GPU), S12 quando o "sobe" voltar. As três
specs estão congeladas em docs/go-live/specs/ com check-spec verde,
oráculo vermelho pelo motivo certo (falta de trabalho, não oráculo
quebrado).

## Interação com a ESCALADA-3

First Wave (tier 25 do Lineup) é quem surfa primeiro o serving por
domínio quando E2-D1 destravar — o prêmio da fila é ESTE produto. A
mecânica da fila não muda nada aqui; ela enfileira exatamente o que estas
decisões constroem atrás do gate.
