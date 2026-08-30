# ESCALADA 2 → FABLE: o modelo certo por task é o produto (e a GPU vem aí)

> Cole isto numa sessão **nova** do Fable. Não é implementação — é direção +
> as decisões que só você congela. O dono pediu explicitamente esta escalada
> ("quero escalar para o fable mais uma vez com esse insight").

---

## LEMBRETE PERMANENTE (o mesmo da primeira)

Você é caro. **Não escreva código. Não rode testes. Não faça deploy. Não
toque `bestmodel-prod`, Vast, nem rig alugada.** Seu trabalho: estratégia,
honestidade e specs executáveis com oráculo congelado. GLM/hand implementa
depois.

## Estado de onde viemos (fatos, 2026-08-30)

- S1–S9 implementadas à mão e mergeadas no main (`7ee51d3`); gate local
  39/39, bateria 17/17, 40/40 suítes. Pré-deploy verificado
  (`docs/go-live/PRE-DEPLOY-VERIFY.md`).
- Superfície de teste humanamente viva:
  `https://carl0sfelipe.github.io/llms.surf` (Pages, espelho de `site/`).
- DNS de llms.surf ainda em parking — Pages é a superfície de teste, não o
  destino final.

## O insight do dono (na boca dele)

> otimizamos e finetunamos, escolhemos sempre o melhor modelo para cada tipo
> de tarefa e modo do llms-surf, incluindo sob demanda por custom modes com
> domínios específicos. Vou rodar uma 3090 na nuvem (Vast.ai) para servir
> isso.

Tradução de produto: **a seleção de modelo É o produto** — não "tokens
genéricos a custo". Cada task/mode anda no modelo certo para o shape dela;
custom modes trazem o domínio deles; e o "sob demanda" é o domínio do dono
virar modelo servido na GPU dele, a custo.

## O que já é FATO no tree (pode ser dito publicamente sem gate novo)

- Escolha por task/modo/stage: registry + tiers (`tier:cheap/mid/expensive/
  vision`) + `usage-hub pick` (mais barato viável por subagent) + fallbacks.
- Custom mode com domínio: o overlay de workdir + `model_ref` por stage —
  o modo do usuário já escolhe o motor; a ficha ensina.
- Medição: ledger por run (modelo, custo estimado, oráculo) — o pick é
  auditável.

## O que NÃO é fato ainda (e por isso a copy segura a mão)

- **"Finetunamos" não tem mecanismo no tree.** Precedente existente: endpoint
  local vast3090 (flashnext+ornith) no dogfooding 2026-08-27 — servir modelo
  próprio já aconteceu; *tunar* ainda não está registrado/mediado.
- A copy nova (`7ee51d3`) diz: pick por task como fato, **"domain-tuned
  models served on demand, at cost, from our own GPU" como NEXT**, gated
  pela waitlist e pelos números no tree. A palavra "fine-tune" NÃO é claim
  presente.

## As 5 decisões que só você congela

1. **O gate da palavra "fine-tune".** Proposta: o claim destrava quando
   existir no tree (a) um modelo tunado de verdade servido pela GPU do dono,
   (b) medição before/after em N tasks reais gravada no registry/ledger, e
   (c) a spec S-whatever correspondente com oráculo verde. Alternativa:
   "tuning" fica para sempre como roadmap. Você decide o N e o formato.
2. **Binding custom mode → modelo tunado.** Campo novo no YAML (`model_ref:
   tuned:<domínio>`?), tier novo, ou convenção de id no registry? É extensão
   de schema do loader — terreno seu por direito (você registrou isso na
   Phase A do SMOKE).
3. **Plano de serving na 3090/Vast.** Um llama-server por domínio? endpoint
  por modo? O que o adapter `llamacpp` já cobre e o que falta? (O dono tem
   skill de Vast com lições de custo medidas: canário obrigatório,
   `inet_down_cost` no olho, instância zumbi bilando, host doente — o
   runbook precisa nascer dessas lições, não do otimismo.)
4. **Dogfood antes da venda.** Servir o modelo tunado para o PRÓPRIO dono e
   modos dele, na GPU dele, ANTES do N=25 da waitlist — é medição ou é
   venda? Proposta: é medição (e obrigatória — não se anuncia número de
   tuning sem tuning medido).
5. **Sequência.** Proposta: S10 = registro+medição do modelo tunado
   (registry entry + harness before/after, oracle congelado) → S11 = binding
   no loader (sua spec) → S12 = runbook Vast (canário, kill de zumbi, teto
   de custo por dia). Você escreve as specs como escreveu S7/S9; a casa
   implementa com oráculo congelado primeiro.

## Não-negociáveis que continuam valendo

- Nenhum preço, tps ou número de tuning em copy antes de existir no tree.
- N=25 da waitlist continua o gate de VENDA (D6/D9) — nada disso muda o
  mecanismo, muda o que se constrói atrás dele.
- A 3090 é dinheiro do dono saindo por hora: nenhum dispatch da casa toca a
  instância sem teto de custo e canário (skill vast do dono tem o playbook).

## Done when (desta escalada)

Você devolve: as 5 decisões congeladas + as specs S10..S12 com check-spec
verde, no formato das S7/S9 (oráculo de 1 linha, congelado antes do código).
