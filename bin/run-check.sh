#!/bin/bash
# run-check.sh — mede exit code/stdout/stderr de um comando SEM cair na armadilha do incidente incidents/2026-07-25-captura-de-resultado-mentiu-3x.md.
#
# Incidente incidents/2026-07-25-captura-de-resultado-mentiu-3x.md: `$?` depois de `$(...)` ou de pipe NÃO é do comando —
# é do último comando da substituição/pipeline. Mesmo com a regra escrita, ela
# foi violada duas vezes escrevendo `cmd | cut ...; echo "exit=$?"` (reportou
# exit=0 para comandos que na verdade voltaram 1 e 3). Regra em documento não
# impede erro de digitação; helper que captura certo por padrão, impede.
#
# Uso: run-check.sh [--expect <n>] [--quiet] <comando> [args...]

set -uo pipefail

TIMEOUT_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/with-timeout.sh"
TIMEOUT_SECS="${RUN_CHECK_TIMEOUT:-120}"

EXPECT=""
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --expect)
            EXPECT="${2:?Uso: run-check.sh [--expect <n>] [--quiet] <comando> [args...]}"
            shift 2
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

[ $# -gt 0 ] || { echo "Uso: run-check.sh [--expect <n>] [--quiet] <comando> [args...]" >&2; exit 3; }

OUT_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT

"$TIMEOUT_SH" "$TIMEOUT_SECS" "$@" >"$OUT_FILE" 2>"$ERR_FILE"
REAL_EXIT=$?

TIMED_OUT=0
if [ "$REAL_EXIT" -eq 124 ]; then
    TIMED_OUT=1
fi

if [ "$QUIET" -eq 1 ] && [ -z "$EXPECT" ]; then
    echo "exit=$REAL_EXIT"
    [ "$TIMED_OUT" -eq 1 ] && echo "(timeout apos ${TIMEOUT_SECS}s)" >&2
    exit "$REAL_EXIT"
fi

if [ "$QUIET" -eq 0 ]; then
    echo "exit=$REAL_EXIT"
    if [ "$TIMED_OUT" -eq 1 ]; then
        echo "(timeout apos ${TIMEOUT_SECS}s — comando morto)"
    fi

    if [ -s "$OUT_FILE" ]; then
        echo "stdout:"
        head -n 5 "$OUT_FILE"
    else
        echo "stdout: (vazio)"
    fi

    if [ -s "$ERR_FILE" ]; then
        echo "stderr:"
        head -n 3 "$ERR_FILE"
    else
        echo "stderr: (vazio)"
    fi
fi

if [ -n "$EXPECT" ]; then
    if [ "$REAL_EXIT" -eq "$EXPECT" ]; then
        echo "✅ exit=$REAL_EXIT como esperado"
        exit 0
    else
        echo "❌ exit=$REAL_EXIT, esperado $EXPECT"
        exit 1
    fi
fi

exit "$REAL_EXIT"
