#!/bin/bash
# check-toolchain.sh — oracle mecânico do toolchain Ruby/Rails no host, ANTES do dispatch.
# Dogfood 2026-09-26: dois runs locais (GGUF Q5 via surf, Bonsai ternário via harness limpo)
# queimaram o teto inteiro em arqueologia de gems — rails meta-gem "incompleto" era
# red herring (meta-gem só tem MIT-LICENSE+README; o executável vive no railties) e o
# shim `rails` do mise falha. Este gate verifica o que a spec exige de fato, do jeito
# que funciona, e falha rápido com instrução acionável.
#
# Uso: bin/check-toolchain.sh [--fix]
# Exit: 0=GO, 1=ambiente quebrado (ver mensagens), 2=uso incorreto
#
# Verifica (na ordem da dor observada):
#   1. ruby + bundler resolvem
#   2. railties executável resolve via Gem.bin_path (o caminho que funciona)
#   3. `rails new --help` responde via esse caminho
#   4. gem ruby_llm presente (spec railschat exige)
#   5. OPENROUTER_API_KEY presente em ~/.config/zsh/secrets (spec exige sourcing)

set -uo pipefail
FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

FAIL=""
say() { echo "[$1] $2"; }

# 1. ruby + bundler (caminho que funciona: ruby -S, porque o shim `bundle` do mise
#    pode estar sem versão — armadilha observada no dogfood 2026-09-26)
ruby -v >/dev/null 2>&1 || FAIL="$FAIL ruby-ausente"
ruby -S bundle --version >/dev/null 2>&1 || FAIL="$FAIL bundler-ausente"

# 2. railties via Gem.bin_path (caminho que funciona; shim `rails` do mise é armadilha)
RAILTIES_EXE="$(ruby -e 'begin; puts Gem.bin_path("railties","rails"); rescue => e; puts ""; end' 2>/dev/null)"
if [ -z "$RAILTIES_EXE" ] || [ ! -f "$RAILTIES_EXE" ]; then
    FAIL="$FAIL railties-nao-resolve"
    say NO "railties não resolve via Gem.bin_path — rode: gem install railties -v 8.1.4 --user-install"
fi

# 3. rails responde pelo caminho certo
if [ -n "${RAILTIES_EXE:-}" ] && [ -f "$RAILTIES_EXE" ]; then
    ruby "$RAILTIES_EXE" --version 2>/dev/null | grep -q "Rails" \
        || FAIL="$FAIL rails-sem-resposta"
fi

# 4. ruby_llm (spec railschat)
gem list ^ruby_llm$ 2>/dev/null | grep -q ruby_llm || {
    FAIL="$FAIL ruby_llm-ausente"
    say NO "gem ruby_llm ausente — rode: gem install ruby_llm --user-install"
}

# 5. chave OpenRouter no arquivo de secrets (spec exige sourcing; nunca imprimir valor)
# SOFT: build/testes usam WebMock — chave real não é necessária para compilar; o modelo
# deve documentar a ausência no README em vez de caçar pelo host (visto no dogfood).
SECRETS="$HOME/.config/zsh/secrets"
if [ ! -f "$SECRETS" ] || ! grep -q "OPENROUTER_API_KEY" "$SECRETS"; then
    say AVISO "OPENROUTER_API_KEY ausente em $SECRETS — spec pede sourcing; build segue, mas o modelo deve mockar (WebMock) e documentar no README"
fi

# Aviso educativo (não falha): shim `rails` do mise é armadilha conhecida
if command -v rails >/dev/null 2>&1 && ! rails --version >/dev/null 2>&1; then
    say AVISO "shim \`rails\` do mise falha — modelos devem usar Gem.bin_path/railties exe (red herring do dogfood 2026-09-26)"
fi

if [ -n "$FAIL" ]; then
    say FAIL "toolchain quebrado:$FAIL"
    [ "$FIX" = "1" ] && say FIX "--fix ainda não automatiza este conserto (anti-invenção: mecanismo requer decisão — ver incidents/uso/2026-09-26). Corrija com os comandos acima."
    exit 1
fi
say OK "toolchain Ruby/Rails/ruby_llm/OPENROUTER pronto para despacho"
exit 0
