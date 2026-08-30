# Backlog — automação (ordem de trabalho, não produto)

> Itens que NÃO estão na fila ativa do go-live. Prioridade de um item só
> sobe quando o gatilho escrito nele acontece de verdade (custo de
> wall-clock medido, não antecipação).

---

## B1 — controle remoto dos runs/sessões pelo celular do dono

- **Status:** backlog · **Pedido do dono:** 2026-08-29 ("achei que ia
  implementar também uma forma de eu controlar vocês pelo WhatsApp").
- **Gatilho de prioridade:** um modo "vai vai vai" (autônomo, sem parar)
  TRAVAR de verdade com o dono longe do terminal e o tempo morto custar
  wall-clock — como a medição de 2026-08-29 (13 min de trabalho, ~2h até
  ser descoberto) que motivou a S9, mas na direção COMANDO, não aviso.
- **O que falta hoje:** a S9 deu o PUSH (run terminou/pausou → celular).
  Falta o PULL-COMANDO: despachar de longe um "retoma", "interrompe",
  "responde a pergunta da S8" ou "mata a sessão travada". O painel
  autenticado (`oracfit gui-tunnel`) já cobre parte pelo navegador do
  celular (interrupt via POST /api/message + `oracfit resume`), mas exige
  o túnel no ar e não é um botão de bolso.
- **⚠️ Tensão registrada — WhatsApp está VETADO como dependência**
  (decisão do PRÓPRIO dono, 2026-08-29, gravada na spec S9 "para ninguém
  reabrir"): a ponte nhermes falhou de forma repetida e medida. O dono
  reabrindo o próprio veto é legítimo — mas quem implementar TEM de
  responder antes: o que mudou desde as falhas medidas? Sem resposta para
  isso, os candidatos abaixo vêm primeiro.
- **Candidatos (ordem de preferência atual):**
  1. **Tópico ntfy de COMANDO** — mesma ferramenta que a S9 já shipa, zero
     dependência nova: dono posta no tópico, um watcher local traduz em
     `oracfit resume` / arquivo de interrupt. Piso de segurança: tópico é
     bearer secret — para COMANDO isso é mais fraco que para aviso (quem
     adivinhar o tópico controla o agente); exige tópico longo exclusivo,
     auditoria de cada comando no ledger e denylist de comandos destrutivos.
  2. **Webhook autenticado no túnel existente** (`gui-tunnel` já tem token)
     — comando vira POST /api/message, caminho que já existe.
  3. **Telegram bot** — NÃO vetado (o veto é WhatsApp), API estável,
     mas dependência nova.
  4. **WhatsApp** — só depois de resolvida a tensão do veto acima.
- **Piso de segurança inegociável (regra 47 e família 53):** arquivos de
  controle FORA do workdir do modelo; comando remoto nunca ensina/remete
  mecanismo de parada em texto legível pelo agente; todo comando remoto
  gravado no ledger (quem, quando, o quê); single-flight da S7 vale para
  comando remoto também — ele é um dispatcher como outro qualquer.
- **Escala:** começa pelo dispatcher (runs); sessão de agente interativa
  (ZCode/Cursor) é camada seguinte, com mecanismo próprio de interrupt.

---

*(novos itens: mesmo formato — status, gatilho medido, tensões, piso de
segurança. Item sem gatilho é desejo, não backlog.)*

---

## B2 — dispatch passa `tier:*` cru ao runner (incidente 2026-08-30, sem promote)

- **Status:** backlog · **Incidente:**
  `incidents/2026-08-30-unlock-plan-passa-tier-ao-runner-sem-res.md`
  (aberto, recorrível, halt pedido pelo dono — sem correção no turno).
- **Sintoma medido:** `llms-surf run tow` (S25 do bestmodel) não rodou —
  `dispatch-stages.sh` e `dispatch-mode.sh` passam `model_ref` cru
  (`tier:cheap`, `tier:expensive`…) ao runner, que espera ID do registry.
  O stub-proof do smoke já mostrava `model_id=tier:cheap` (sinal visível
  desde a S1, ignorado porque stub não liga).
- **Gatilho de prioridade:** qualquer dispatch com runner REAL em modo com
  tiers (stub esconde; production expõe).
- **Mecanismo proposto:** resolver tier→id no ENTRYPOINT (os dois), via
  `lib-oracfit-mode-loader.py resolve-tier` (existe e não é chamado);
  irredutível → exit 3 falha-fechada (contrato do runner: quem chama passa
  id válido). Teste: dispatch stub com assert de id resolvido no proof.


---

## D11 — Dono decide as pendências cross-produto (2026-08-30)

1. **Whitelist: DUAS LISTAS, uma por produto** (llms-surf e bestmodel cada
   uma com a sua) — decisão do dono, revertendo a recomendação de lista
   única. Consequência assumida: dois sinais de demanda separados; o N=25
   destravante passa a valer POR LISTA.
2. **Gamificação do giveaway**: quem registra/compartilha ganha PONTOS no
   rank de giveaway de free tokens do llms-surf no lançamento. Fonte de
   pontos (decisão mesma data, lado bestmodel): contribuição registrada —
   começa com o opt-out transparente do Local Lab (A3 do backlog de lá);
   runs assinadas (S23) e modos compartilhados já contam no espírito da
   fórmula de tiers. O rank é público quando a fórmula "ships with the
   cloud" — número antes de medição, não.


---

## Decisão do dono 2026-08-30 — duas listas, um rank

- **Whitelists SEPARADAS**: bestmodel e llms.surf têm listas próprias (cada
  produto mede o próprio sinal de demanda; o N=25 deste produto continua
  valendo só pra cá).
- **O rank de contribuição ATRAVESSA**: contribuir no bestmodel (runs
  assinadas via S23, benchmarks, opt-out transparente com checkbox visível)
  gera PONTOS que alimentam o **giveaway de free tokens do llms-surf** no
  lançamento — a ponte cruzada dos produtos, decidida pelo dono.
- Efeito na fórmula de tiers: "capacidade de contribuição" ganha fonte
  mecânica mensurável desde já (pontos do rank); pesos seguem "ships with
  the cloud".
