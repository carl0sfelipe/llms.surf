#!/bin/bash
# check-spec.sh — mecanismo do incidente incidents/2026-07-26-spec-sem-clausula-anti-invencao-gera-num.md: spec sem cláusula anti-invenção reprova.
# Uso: bin/check-spec.sh <spec_file>
#
# Por que existe: medição de 2026-07-26 sobre 14 despachos — TODO refinamento
# teve pelo menos um número inventado para corrigir (limiar de 5.000, "abaixo de
# 60%", "2 GB de RAM", prazos em meses). As duas únicas specs que saíram sem
# refinamento foram as que listavam os dados verificados e proibiam acrescentar
# outros. A causa é lacuna de spec, não qualidade do modelo — campo em branco
# dentro de estrutura pedida é preenchido por invenção, por qualquer redator.
# Incidente: incidents/2026-07-26-spec-sem-clausula-anti-invencao-gera-num.md
#
# LIMITE CONHECIDO (regra 32 — declare o mecanismo, não o exagere): este script
# detecta AUSÊNCIA de defesa, não defesa FRACA. A spec `docs-plano-e-adr.md`
# passava no check 1 com "nao invente numeros de mercado, prazos em meses, nem
# nomes de concorrentes" — e mesmo assim o modelo inventou limiar de 5.000
# anúncios e "2 GB de RAM", porque a cláusula era estreita demais. Conferir o
# ESCOPO da cláusula exige ler prosa e continua sendo trabalho do orquestrador.
#
# Exit: 0=ok, 1=spec sem defesa, 3=erro de uso

set -uo pipefail

SPEC="${1:?Uso: check-spec.sh <spec_file>}"
[ -f "$SPEC" ] || { echo "check-spec.sh: spec não encontrada: $SPEC" >&2; exit 3; }

faltando=()

# 1. Cláusula anti-invenção. Aceita as formulações já usadas no repo.
# ATENÇÃO: acento vai em ALTERNAÇÃO `(a|ã)`, nunca em conjunto `[aã]`. O grep do
# macOS é BSD e trata o conjunto byte a byte: `n[aã]o` NÃO casa "não", porque o
# ã ocupa dois bytes. O efeito era falso negativo silencioso — spec que já
# trazia a cláusula com acento era reprovada, e o autor era mandado acrescentar
# o que já estava lá. Descoberto em 2026-07-28 ao escrever as specs SEP-01..03.
grep -qiE 'n(a|ã)o invente|n(a|ã)o acrescente|sem inventar|nenhum n(u|ú)mero al(e|é)m|al(e|é)m destes' "$SPEC" \
  || faltando+=("cláusula anti-invenção (ex.: 'Nao invente numero, prazo ou fonte alem dos listados')")

# 2. Bloco de dados verificados.
grep -qiE 'dados verificados|contexto real|verificado\)|\(verificado' "$SPEC" \
  || faltando+=("bloco de dados verificados (o que o modelo PODE usar)")

# 3. Verificação semântica, não só existência de arquivo.
#    `ls arquivo.md` não prova nada sobre o conteúdo.
#
#    Aceita duas formas, porque exigir só a linha `VERIFICACAO:` reprovava spec
#    bem defendida que usava seção `## Verificação` com bloco de comandos
#    (falso positivo observado em 2026-07-26 na spec do Épico 8):
#      a) linha `VERIFICACAO: <comando>`
#      b) seção cujo título contenha "verifica"
#    Em qualquer das duas, tem de haver comando que prove propriedade do
#    CONTEÚDO, não apenas existência de arquivo.
COMANDO_SEMANTICO='grep|python3|node |npx|npm run|curl|test |diff|wc |psql|jq'

if grep -qiE '^VERIFICA(C|Ç)(A|Ã)O:' "$SPEC"; then
  LINHA=$(grep -iE '^VERIFICA(C|Ç)(A|Ã)O:' "$SPEC" | head -1)
  echo "$LINHA" | grep -qE "$COMANDO_SEMANTICO" \
    || faltando+=("verificação semântica — '$LINHA' só checa existência; use grep/python3/etc")
elif grep -qiE '^#{1,6}[[:space:]].*verifica' "$SPEC"; then
  grep -qE "$COMANDO_SEMANTICO" "$SPEC" \
    || faltando+=("comando de verificação que prove propriedade do conteúdo (só há 'ls' ou nada)")
else
  faltando+=("linha VERIFICACAO: ou seção de verificação com comando que prove a propriedade pedida")
fi

# 4. Seção ## Oráculo — o gate que fecha o dispatch, não a verificação de UMA
# afirmação (item 3 acima). bin/ledger-finalize.sh procura por ela para
# calcular oracle_exit; sem a seção, o ledger continua cego a ponto de "log
# não vazio" ser a única evidência de sucesso (dispatch d-07 alucinou e
# registrou "ok" — ver plan_dispatch_2.0_fixed.md).
if grep -qiE '^#{1,6}[[:space:]]*or(a|á)culo' "$SPEC"; then
  grep -qiE '^[-*][[:space:]]*comando:' "$SPEC" \
    || faltando+=("seção ## Oráculo sem linha 'comando:' com o teste executável")
  # Incidente 2026-08-10-backtick-no-comando-do-oraculo: crase na linha `- comando:`
  # vira SUBSTITUIÇÃO de comando no eval (lib-oracfit-gauntlet.sh + check-oracle.py):
  # o bash executa o backtick, captura o stdout, tenta rodar ESSE stdout como comando
  # → '{"ok":true...}: command not found' → exit 127 fantasma. O oráculo "falha"
  # pelo motivo errado e o check-oracle.py pode classificar como "fails-correctly"
  # liberando dispatch quebrado. A linha de comando tem que ser TEXTO CRU, sem crase.
  if grep -qE '^[-*][[:space:]]*comando:.*`' "$SPEC"; then
    faltando+=("linha 'comando:' do oráculo contém CRASE (backtick) — vira substituição no eval e gera exit 127 fantasma. Use texto cru sem crase (incidente 2026-08-10-backtick-no-comando-do-oraculo)")
  fi
else
  faltando+=("seção ## Oráculo (comando + exit esperado que prova o resultado, não so que o modelo rodou)")
fi

# Soft hint (não falha): ## Barra melhora o gauntlet (referência nomeada/fetchable).
if ! grep -qiE '^#{1,6}[[:space:]]*barra' "$SPEC"; then
  echo "HINT: spec sem ## Barra — gauntlet usa só o oráculo como metric (ok). Template: fluxos/_comum/artefato-template.md" >&2
fi

# 5. Cláusula anti-fantasma (incidente 2026-07-29-declare-fantasma-formatBrlAmount.md).
# declare const é TypeScript legal mas RUNTIME inexistente. O flash usa como
# workaround quando não resolve import — compila, oráculo de tsc passa, produção quebra.
grep -qiE 'n(a|ã)o use declare|sem declare const|proibido declare|NUNCA.*declare' "$SPEC" \
  || faltando+=("cláusula anti-fantasma (ex.: 'NUNCA use declare const como workaround — importe de verdade')")
if [ ${#faltando[@]} -eq 0 ]; then
  echo "✅ spec OK (declara dados verificados e proíbe invenção): $SPEC"
  exit 0
fi

echo "❌ spec sem defesa contra invenção — ver incidents/2026-07-26-spec-sem-clausula-anti-invencao-gera-num.md: $SPEC" >&2
for f in "${faltando[@]}"; do echo "   - falta $f" >&2; done
echo "   Campo não decidido vai marcado [A DEFINIR], nunca em branco." >&2
exit 1
