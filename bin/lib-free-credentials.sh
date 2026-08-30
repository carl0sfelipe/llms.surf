#!/bin/bash
# lib-free-credentials.sh — leitor ÚNICO de credencial de provider (E5-M5/D4).
#
# Incidente-âncora (E5): 118 Bedrock + 36 Copilot viraram o default pago SEM
# NINGUÉM PEDIR — credencial herdada no ambiente redirecionava o caminho free.
# O fechamento da classe tem duas pernas:
#
#   1. Esta lib é a ÚNICA leitora de credencial da cadeia de dispatch. O gate
#      (bin/test-free-path.sh + check-saude) grepa a cadeia: zero leitura de
#      *_API_KEY/AWS_* fora daqui.
#   2. A pergunta "o provider X tem credencial?" é respondida lendo ARQUIVO
#      (auth.json do opencode + opencode.json de providers custom) — NUNCA
#      variável de ambiente. Env herdada não existe para o caminho free: é
#      exatamente o vetor do incidente. A perna envenenada do D5 (isca com
#      valor falso) prova a imunidade em runtime.
#
# Contrato:
#   free_cred_has_provider <provider>   exit 0 = tem credencial armazenada
#                                       exit 1 = não tem; exit 3 = storage
#                                       presente mas ILEGÍVEL (fail loud —
#                                       storage corrompido não é "sem chave")
#   free_cred_list                      imprime providers com credencial
#                                       (nomes apenas, NUNCA valor)
#
# NENHUMA função desta lib imprime ou retorna material de chave. Quem precisa
# do VALOR da chave é o CLI (opencode) — e ele lê os mesmos arquivos por conta
# própria. Fora do caminho de dispatch, ferramentas de API direta (cf-probe,
# vision-gauntlet) mantêm leitura própria de env — são diagnóstico fora da
# cadeia, cobradas no gate como exceção documentada.
#
# Env de teste (SÓ para fixtures): ORACFIT_AUTH_JSON e ORACFIT_OPENCODE_CONFIG
# apontam para arquivos de fixture. Em produção ficam unset e os paths reais
# são usados. Nenhuma outra env é lida por esta lib.

set -uo pipefail

FREE_CRED_AUTH_JSON="${ORACFIT_AUTH_JSON:-$HOME/.local/share/opencode/auth.json}"
FREE_CRED_OPENCODE_CONFIG="${ORACFIT_OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.json}"

free_cred_has_provider() {
  local provider="${1:?Uso: free_cred_has_provider <provider>}"
  local found=0 readable_storage=0

  # Perna 1: auth.json do opencode (`opencode auth login` grava aqui).
  if [ -e "$FREE_CRED_AUTH_JSON" ]; then
    readable_storage=1
    if [ ! -r "$FREE_CRED_AUTH_JSON" ]; then
      echo "free-credentials: auth.json presente mas ilegível: $FREE_CRED_AUTH_JSON" >&2
      return 3
    fi
    if python3 - "$FREE_CRED_AUTH_JSON" "$provider" <<'PYAUTH'
import json, sys
try:
    auth = json.load(open(sys.argv[1], encoding="utf-8"))
except (json.JSONDecodeError, OSError):
    sys.exit(3)
sys.exit(0 if isinstance(auth, dict) and sys.argv[2] in auth else 1)
PYAUTH
    then
      found=1
    elif [ $? -eq 3 ]; then
      echo "free-credentials: auth.json corrompido: $FREE_CRED_AUTH_JSON" >&2
      return 3
    fi
  fi

  # Perna 2: provider custom em opencode.json (rigs locais com baseURL).
  if [ "$found" -eq 0 ] && [ -e "$FREE_CRED_OPENCODE_CONFIG" ]; then
    readable_storage=1
    if [ ! -r "$FREE_CRED_OPENCODE_CONFIG" ]; then
      echo "free-credentials: opencode.json presente mas ilegível: $FREE_CRED_OPENCODE_CONFIG" >&2
      return 3
    fi
    if python3 - "$FREE_CRED_OPENCODE_CONFIG" "$provider" <<'PYCFG'
import json, sys
try:
    cfg = json.load(open(sys.argv[1], encoding="utf-8"))
except (json.JSONDecodeError, OSError):
    sys.exit(3)
prov = (cfg.get("provider") or {}).get(sys.argv[2]) if isinstance(cfg, dict) else None
has_base = bool(prov and isinstance(prov, dict) and (prov.get("options") or {}).get("baseURL"))
sys.exit(0 if has_base else 1)
PYCFG
    then
      found=1
    elif [ $? -eq 3 ]; then
      echo "free-credentials: opencode.json corrompido: $FREE_CRED_OPENCODE_CONFIG" >&2
      return 3
    fi
  fi

  [ "$found" -eq 1 ] && return 0
  return 1
}

free_cred_list() {
  # Providers com credencial armazenada — NOMES apenas, nunca valor.
  python3 - "$FREE_CRED_AUTH_JSON" "$FREE_CRED_OPENCODE_CONFIG" <<'PYLIST'
import json, sys

names = []
auth_p, cfg_p = sys.argv[1], sys.argv[2]
try:
    auth = json.load(open(auth_p, encoding="utf-8"))
    names += [k for k in auth if isinstance(auth, dict)]
except (json.JSONDecodeError, OSError, TypeError):
    pass
try:
    cfg = json.load(open(cfg_p, encoding="utf-8"))
    provs = cfg.get("provider") or {}
    names += [k for k, v in provs.items()
              if isinstance(v, dict) and (v.get("options") or {}).get("baseURL")]
except (json.JSONDecodeError, OSError, AttributeError):
    pass
for n in sorted(set(names)):
    print(n)
PYLIST
}
