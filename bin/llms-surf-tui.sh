#!/usr/bin/env bash
# llms-surf-tui.sh — bash wizard for the basic journey (hypothesis HA, owner '1a').
#
# The §3.1 journey: one command → menu → task → budget → result with
# accounting. Zero dependencies (plain bash, reads stdin — works over raw
# SSH and is pipe-testable). A full-screen TUI (HB) can land later behind
# the same command. All NEW user-facing copy is English (owner '5');
# recommended modes per owner '6': normal, unlock_plan, ui_visual_qa.
#
# Usage: llms-surf            (no args → this menu)
# Env: ORACFIT_ROOT (default: this script's tree)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Exporta o root ANTES de despachar: a fachada bin/llms-surf sabe onde o tree
# está, mas o dispatcher embaixo (oracfit_resolve_root) só lê env ou
# ~/.oracfit/current — sem isto, o wizard num shell LIMPO (leigo que não
# exportou nada) morre em "cannot resolve Oracfit root" no primeiro dispatch.
export ORACFIT_ROOT="${ORACFIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
ORACFIT="$ORACFIT_ROOT/bin/oracfit"

bold() { [ -t 1 ] && printf '\033[1m%s\033[0m\n' "$1" || printf '%s\n' "$1"; }
sep()  { printf '%s\n' "──────────────────────────────────────────"; }

usage_hoje() {  # today's accounting (usage-hub is the sensor; this is the view)
  "$ORACFIT" usage status 2>&1 || echo "  (no usage data yet — run a task first)"
}

# Surf aliases (go-live D2/D7, 2026-08-29): the home shows the wave names —
# one source of truth is `oracfit alias` (paddle=normal tow=unlock_plan
# surfcheck=ui_visual_qa). The 17 god modes stay in git and in the CLI
# (`llms-surf modes` lists all); they are not the default menu here.

surf_lines() {  # prints "★ alias (tree_id)" lines from the alias map
  local pair
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    printf '  ★ %-10s (%s)\n' "${pair%%=*}" "${pair#*=}"
  done < <("$ORACFIT" alias 2>/dev/null)
}

modes_ids() { "$ORACFIT" modes 2>/dev/null | grep -oE '^\s+[a-z0-9_]+$' | tr -d ' '; }

# ── flow: new task (task → mode → adapter → budget → dispatch) ──────────────
nova_tarefa() {
  sep
  read -r -p "Spec path (.md file with ## Oracle): " SPEC
  [ -f "$SPEC" ] || { echo "✗ spec not found: $SPEC"; return 1; }
  read -r -p "Task id [task-$(date +%H%M)]: " TASK
  TASK="${TASK:-task-$(date +%H%M)}"

  echo "Modes (★ surf aliases — paddle out with one; any mode id also works):"
  surf_lines
  echo "    … or type any other mode id (bin/llms-surf modes lists all)"
  read -r -p "Mode [paddle]: " MODO
  MODO="${MODO:-paddle}"
  case "$MODO" in
    *[!a-z0-9_]*) echo "✗ invalid mode (only [a-z0-9_])"; return 1 ;;
  esac

  echo "Adapters (sources env.sh before the run):"
  local ADAPTERS=() a
  for e in "$ORACFIT"/../adapters/*/env.sh; do
    [ -f "$e" ] && ADAPTERS+=("$(basename "$(dirname "$e")")")
  done
  for a in "${ADAPTERS[@]}"; do echo "  - $a"; done
  read -r -p "Adapter [stub — proves the path, zero tokens]: " AD
  AD="${AD:-stub}"

  sep
  bold "Today's budget (before dispatch):"
  usage_hoje
  sep
  read -r -p "Dispatch '$TASK' (mode $MODO, adapter $AD)? [y/N]: " OK
  case "$OK" in y|Y|yes|YES) ;; *) echo "— cancelled"; return 0 ;; esac

  # $ORACFIT é o ARQUIVO bin/oracfit — $ORACFIT/.. resolve para bin/, e
  # bin/adapters/ não existe: o adapter nunca era sourced e o dispatch morria
  # com DISPATCH_RUNNER unset em shell limpo (bug do caminho do leigo; só era
  # invisível quando o operador exportava o env à mão). Path certo: $ORACFIT_ROOT.
  # shellcheck disable=SC1091
  [ -f "$ORACFIT_ROOT/adapters/$AD/env.sh" ] && . "$ORACFIT_ROOT/adapters/$AD/env.sh"
  echo "— dispatching (live log; the oracle decides at the end)…"
  "$ORACFIT" run "$MODO" "$SPEC" "$TASK"
  local rc=$?
  sep
  bold "Post-run accounting:"
  usage_hoje
  sep
  [ "$rc" -eq 0 ] && echo "✓ task $TASK: oracle green" \
                   || echo "✗ task $TASK: exit $rc (see events above)"
  return "$rc"
}

# ── main menu ────────────────────────────────────────────────────────────────
while :; do
  sep
  bold "llms.surf — the budget leads, the oracle decides"
  echo "  1) New task (dispatch)"
  echo "  2) Today's spend"
  echo "  3) Available modes"
  echo "  0) Quit"
  read -r -p "> " OP || break   # EOF (closed pipe) = clean exit
  case "$OP" in
    1) nova_tarefa ;;
    2) sep; bold "Today's spend:"; usage_hoje ;;
    3) echo "Modes (★ surf aliases — the home trio):"
       surf_lines
       echo "  god modes stay in git & CLI — bin/llms-surf modes lists everything." ;;
    0|q|quit) break ;;
    *) echo "? $OP is not an option" ;;
  esac
done
echo "see you — the oracle is still watching."
