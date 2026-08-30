#!/bin/bash
# oracfit-notify.sh — S9: o grito da praia (docs/go-live/specs/S9-ntfy-run-notify.md).
#
# Aviso push no celular quando um run termina ou pausa para pergunta do dono.
# A medição que o justifica (2026-08-29): 13 min de trabalho, descobertos
# ~2h depois — o gargalo do produto é a LATÊNCIA DE ATENÇÃO do dono.
#
# Contrato (regra 12/13 da casa):
#   - OPT-IN: ORACFIT_NTFY_TOPIC unset ⇒ silêncio absoluto, exit 0.
#   - O tópico é segredo bearer: vive em env, nunca em YAML/git/log — este
#     script NUNCA ecoa o tópico ou a URL completa.
#   - Corpo TERSO: run_id, task, status. NADA mais — texto da pergunta,
#     spec e caminhos do workdir não saem da máquina; detalhe se lê no painel.
#   - curl com teto de 5s e falha SEMPRE tolerada: notificação morta jamais
#     muda o exit code de quem chamou (advisory, nunca gate).
#   - WhatsApp VETADO como dependência (decisão do dono 2026-08-29 — falhas
#     repetidas da ponte nhermes; não reabrir).
#
# Uso: oracfit-notify.sh <run_id> <task> <status>   (chamado pelo funil de
# eventos em run_finished / owner_question; pode ser chamado à mão p/ teste)
set -uo pipefail

RUN_ID="${1:-}"
TASK="${2:-}"
STATUS="${3:-}"

# Opt-in: sem tópico configurado, não existe notificação — nem tentativa.
[ -n "${ORACFIT_NTFY_TOPIC:-}" ] || exit 0

URL="${ORACFIT_NTFY_URL:-https://ntfy.sh}/${ORACFIT_NTFY_TOPIC}"

# Corpo terso — só os três campos que o dono precisa pra decidir se abre o
# painel. --data-binary sem -v/-s verbose: nada do request vira log local.
curl -m 5 -s --data-binary "llms.surf: ${STATUS} run_id=${RUN_ID} task=${TASK}" \
  "$URL" >/dev/null 2>&1 || true

exit 0
