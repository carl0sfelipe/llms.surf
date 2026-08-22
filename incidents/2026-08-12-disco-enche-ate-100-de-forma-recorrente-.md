---
id: 2026-08-12-disco-enche-ate-100-de-forma-recorrente-
titulo: Disco enche até 100% de forma recorrente e a limpeza de emergência destrói estado
data: 2026-08-12
recorrivel: sim
regra: 51
status: promovido
interage_com: "incidents/2026-08-11-migracao-zerou-catalogo-medusa-produto-fora-do-seed-perdido.md"
---

# Disco enche até 100% de forma recorrente e a limpeza de emergência destrói estado

## Sintoma

Segunda ocorrência em 24h:

- **2026-08-11**: disco 100% cheio → limpeza de emergência (`colima delete` +
  datadisk órfão de 60 GB + caches npm) → 59 GB livres. Efeito colateral: o
  volume `infra_postgres_data` foi recriado e o **catálogo Medusa de produção
  foi zerado** (seed recuperou 19 produtos; <host-local> cadastrado fora do seed,
  perdido). Registrado no incidente de 2026-08-11 (interage_com).
- **2026-08-12 ~14:40**: disco de novo em ~116 MiB livres durante operação de
  commits em massa (10 agentes paralelos) — commits chegaram a falhar com
  "no space left on device". O macOS liberou espaço purgeable sozinho e o
  nível estabilizou em ~23 GB livres. Ou seja: de 59 GB livres para o teto
  em menos de 24h.

## Causa

Com evidência (medições de 2026-08-12, `du`/`df`):

1. **Baseline cronicamente alto num disco de 228 GB**: modelos de IA locais
   31 GB (gemma-4 9.1G, qwen25-vl 6.4G, flux1-schnell 6.4G, minicpm 6.3G,
   flux2-klein 2.4G — todos de julho, estáticos), ~/Library 23 GB,
   Downloads 6.9 GB, VM Colima (produção) 13 GB **e crescendo** — foi
   recriada ontem e já acumulou 13 GB de imagens/layers/logs Docker.
2. **Rajadas simultâneas**: múltiplas sessões de agente em paralelo
   (dispatch de modelos, builds Next.js, npm installs, enriquecimento de
   fornecedores) somadas ao purgeable do APFS fazem o "livre" oscilar de
   dezenas de GB para MiB em minutos.
3. **A resposta de emergência é o dano real**: sem regra, a limpeza sob
   pressão escolheu `colima delete` — destruiu volume de banco de produção
   sem dump prévio. O custo do incidente não foi o disco cheio; foi a
   limpeza sem backup.

## Correção aplicada

1. Este incidente + regra promovida (backup como gate de qualquer limpeza
   destrutiva; limiares de alerta).
2. Diagnóstico documentado acima (mapa de consumo) para a próxima limpeza
   ser cirúrgica, não de pânico: alvos seguros primeiro (caches npm 1.6G,
   ~/Library/Caches 1.6G, imagens Docker dangling, Downloads antigos).
3. Pendente (mecanismo): watchdog launchd com `df` periódico e alerta via
   canal Hermes/rádio quando livre < 25 GB — marcador externo visível,
   porque a percepção gradual de "está enchendo" é exatamente o que falha
   (mesmo padrão do time blindness já documentado no tdah-loops).

Interações revisadas (aviso do promote): regras 42/48/49 compartilham só
vocabulário (watchdog/limpeza = gestão de processos, não disco) — sem
conflito real. A regra 51 fecha a dívida do incidente de 2026-08-11
(recorrivel: sim que estava sem regra de proteção do estado).

## Pode acontecer de novo?

**SIM** — o baseline continua alto e a VM de produção cresce todo dia.
Sem watchdog e sem a regra do dump-antes-de-destruir, a próxima rajada
repete o ciclo, e a próxima "limpeza de emergência" pode custar outro
banco. DEVE virar regra: `bin/incident.sh promote`.
