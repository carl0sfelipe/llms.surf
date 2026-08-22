#!/bin/bash
# check-publico.sh — gate mecânico do corte público: recusa dado pessoal e
# caminho de máquina.
#
# Nasceu do incidente 2026-08-13-oracfit-soldado-no-<repo-cliente>-corte-sem-catego:
# ~2.500 telefones de terceiros chegaram ao repo do produto porque specs/
# não era categoria do manifesto do publish-cut e nenhum check olhava
# CONTEÚDO (.gitignore vigia runtime, check-spec vigia fato inventado —
# telefone de terceiro passava pelos dois). Regra 32: regra sem mecanismo
# é dívida. Este script é o mecanismo.
#
# Checa 3 coisas:
#   C1 telefone celular BR (11 dígitos com DDD, delimitado) em prosa e código
#   C2 e-mail fora da allowlist de domínios sintéticos/reservados
#   C3 caminho absoluto de máquina pessoal (/Users/<user>) em CÓDIGO
#      (sh, py, yaml, js, ts). Prosa .md com caminho é feio mas não
#      quebra máquina alheia nem vaza dado — não bloqueia.
#
# Uso:
#   bin/check-publico.sh <DIR>       varre DIR inteiro — é o gate final para
#                                    um candidato a corte público
#   bin/check-publico.sh --oficina   varre só a superfície exportável DESTE
#                                    repo (o que o publish-cut copia
#                                    automaticamente) — early warning no
#                                    check-saude da oficina
# Exit: 0 = limpo, 1 = bloqueio, 2 = uso errado

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Categorias que NUNCA saem da oficina (espelha a política do publish-cut;
# o gate final — scan cheio no destino — pega drift desta lista).
PRIVADO=(specs docs/handoffs docs/prompts incidents/uso lessons)

# Ruído sem valor de scan em qualquer modo.
RUIDO=(.git node_modules .dispatch ledger probe ring .opencode .zcode)

# Superfície que o publish-cut copia SEM curadoria humana.
# Manter em sincronia com MIRROR_FULL_DIRS + espelho-com-exceção + MIRROR_FULL_FILES
# de bin/oracfit-publish-cut.sh.
SUPERFICIE_DIRS=(adapters panel tests fluxos .github core bin)
SUPERFICIE_FILES=(AGENTS.md CLAUDE.md LICENSE NOTICE QWEN.md SKILL.md VERSION
  ZCODE.md install.sh docs/STATE_TEMPLATE.md docs/TELEMETRY.md docs/functions.md
  README.md model-registry.json)

MODO="${1:?Uso: check-publico.sh <DIR> | --oficina}"

ALVOS=()
if [ "$MODO" = "--oficina" ]; then
  cd "$REPO_ROOT" || exit 2
  for d in "${SUPERFICIE_DIRS[@]}"; do [ -d "$d" ] && ALVOS+=("$d"); done
  for f in "${SUPERFICIE_FILES[@]}"; do [ -f "$f" ] && ALVOS+=("$f"); done
else
  [ -d "$MODO" ] || { echo "ERROR: diretório não existe: $MODO" >&2; exit 2; }
  cd "$MODO" || exit 2
  ALVOS=(.)
fi

EXCL=()
for r in "${RUIDO[@]}"; do EXCL+=(--exclude-dir="$r"); done
# No scan cheio (candidato a corte), categoria privada presente é achado do
# publish-cut (assert de ausência), não deste grep — mas excluí-la aqui
# esconderia telefone se o assert for burlado. Então NÃO excluímos PRIVADO
# no scan cheio; só na oficina, onde ela mora por design.
if [ "$MODO" = "--oficina" ]; then
  for p in "${PRIVADO[@]}"; do EXCL+=(--exclude-dir="$(basename "$p")"); done
fi

FALHAS=0

# --- C1: telefone celular BR -------------------------------------------------
# 2 dígitos de DDD + 9 + 8 dígitos, delimitado por não-dígito nas pontas para
# não casar epoch/sha/run_id (runs longos de dígito).
FONE='(^|[^0-9])\(?[0-9]{2}\)?[ .-]?9[0-9]{4}[ .-]?[0-9]{4}([^0-9]|$)'
HITS=$(grep -rInE "${EXCL[@]}" \
  --include='*.md' --include='*.json' --include='*.yaml' --include='*.yml' \
  --include='*.txt' --include='*.csv' --include='*.sh' --include='*.py' \
  --include='*.js' --include='*.ts' \
  "$FONE" "${ALVOS[@]}" 2>/dev/null)
if [ -n "$HITS" ]; then
  echo "BLOQUEIO C1: telefone pessoal encontrado"
  echo "$HITS" | head -20 | sed 's/^/  /'
  echo "  ($(echo "$HITS" | wc -l | tr -d ' ') linha(s) no total)"
  FALHAS=$((FALHAS + 1))
fi

# --- C2: e-mail de terceiro --------------------------------------------------
# Allowlist: domínios reservados (RFC 2606/6761: example.*, .invalid, .local,
# .test) e endereços sintéticos usados nos testes deste repo (test.dev).
EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
ALLOW='@([A-Za-z0-9.-]*\.(local|invalid|test)|example\.(com|org|net)|test\.dev|github\.com)$'
HITS=$(grep -rInoE "${EXCL[@]}" \
  --include='*.md' --include='*.json' --include='*.yaml' --include='*.yml' \
  --include='*.txt' --include='*.csv' --include='*.sh' --include='*.py' \
  --include='*.js' --include='*.ts' \
  "$EMAIL_RE" "${ALVOS[@]}" 2>/dev/null | grep -vE "$ALLOW")
if [ -n "$HITS" ]; then
  echo "BLOQUEIO C2: e-mail fora da allowlist"
  echo "$HITS" | head -20 | sed 's/^/  /'
  echo "  (allowlist em bin/check-publico.sh — amplie SÓ com decisão humana)"
  FALHAS=$((FALHAS + 1))
fi

# --- C3: caminho de máquina pessoal em código ---------------------------------
# O padrão exige um nome de usuário logo após /Users/, então esta própria
# linha (classe entre colchetes) não casa consigo mesma.
CAMINHO='/Users/[A-Za-z0-9_.-]+'
HITS=$(grep -rInE "${EXCL[@]}" \
  --include='*.sh' --include='*.py' --include='*.yaml' --include='*.yml' \
  --include='*.js' --include='*.ts' \
  "$CAMINHO" "${ALVOS[@]}" 2>/dev/null)
if [ -n "$HITS" ]; then
  echo "BLOQUEIO C3: caminho de máquina pessoal em código"
  echo "$HITS" | head -20 | sed 's/^/  /'
  echo "  (parametrize: \$HOME, \$ORACFIT_ROOT, \$ORACFIT_WORKDIR ou fixture relativa)"
  FALHAS=$((FALHAS + 1))
fi

if [ "$FALHAS" -eq 0 ]; then
  echo "check-publico: limpo ($MODO)"
  exit 0
fi
echo "check-publico: $FALHAS bloqueio(s) — corte público RECUSADO."
exit 1
