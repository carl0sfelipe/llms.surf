# lib-oracfit-root.sh — resolve ORACFIT_ROOT / DISPATCH_ROOT (AD-3)
# Source me: source lib-oracfit-root.sh; oracfit_resolve_root
#
# Precedence: ORACFIT_ROOT > DISPATCH_ROOT > $HOME/.oracfit/current
# Both set and differ => error to stderr, return 1.

oracfit_resolve_root() {
  local _oracfit="${ORACFIT_ROOT:-}"
  local _dispatch="${DISPATCH_ROOT:-}"

  if [ -n "$_oracfit" ] && [ -n "$_dispatch" ]; then
    local _abs_o _abs_d
    _abs_o="$(_oracfit_abspath "$_oracfit")" || return 1
    _abs_d="$(_oracfit_abspath "$_dispatch")" || return 1
    if [ "$_abs_o" != "$_abs_d" ]; then
      echo "ERROR: ORACFIT_ROOT and DISPATCH_ROOT both set but point to different paths:" >&2
      echo "  ORACFIT_ROOT -> $_abs_o" >&2
      echo "  DISPATCH_ROOT -> $_abs_d" >&2
      echo "Unset one of them or align to the same directory." >&2
      return 1
    fi
  fi

  local _root=""
  if [ -n "$_oracfit" ]; then
    _root="$_oracfit"
  elif [ -n "$_dispatch" ]; then
    _root="$_dispatch"
  elif [ -d "$HOME/.oracfit/current" ]; then
    _root="$HOME/.oracfit/current"
  else
    echo "ERROR: cannot resolve Oracfit root. Set ORACFIT_ROOT, DISPATCH_ROOT, or ensure ~/.oracfit/current exists." >&2
    return 1
  fi

  _root="$(_oracfit_abspath "$_root")" || return 1
  echo "$_root"
  return 0
}

_oracfit_abspath() {
  case "$1" in
    /*)
      if [ -d "$1" ]; then
        cd -P "$1" && pwd -P
      else
        echo "$1"
      fi
      ;;
    *)
      if [ -d "$1" ]; then
        cd -P "$1" && pwd -P
      else
        local _parent
        _parent="$(cd -P "$(dirname "$1")" 2>/dev/null && pwd -P)" || {
          echo "ERROR: cannot resolve path: $1" >&2
          return 1
        }
        echo "$_parent/$(basename "$1")"
      fi
      ;;
  esac
}

# ── S7 (regra 53, mecanismo 1): single-flight por workdir ────────────────────
# mkdir atômico + pid file — PORTÁTIL de propósito: hosts incluem macOS com
# bash 3.2 e SEM flock(1) (ver comentário bash 3.2 em bin/oracfit cmd_modes);
# mkdir é atômico em qualquer POSIX. O lock cobre o run INTEIRO nos DOIS
# entrypoints (dispatch-mode.sh e dispatch-stages.sh — um lock só no cmd_run
# não sobreviveria ao exec) e é liberado em todo caminho de saída via trap.
# O lock fica FORA do inbox (é estado do workdir, não mensagem) e a mensagem
# de recusa NUNCA ensina como forçar remoção (espírito da regra 47: o botão
# de desligar não é gravável por acidente, e não se anuncia em texto).
ORACFIT_RUN_LOCK_DIR=""

oracfit_run_lock_acquire() {  # 0 = adquirido; 6 = recusado (run vivo no workdir)
  local lock owner
  lock="$(oracfit_workdir)/.dispatch/.run-lock"
  # Pai primeiro: workdir fresco ainda nao tem .dispatch/ — mkdir do lock sem
  # o pai falha como "no such directory", que NAO e lock existente (o erro
  # exato do primeiro run do teste: recusado por lock fantasma).
  mkdir -p "$(dirname "$lock")"
  if mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "$$" >"$lock/pid"
    ORACFIT_RUN_LOCK_DIR="$lock"
    return 0
  fi
  owner="$(cat "$lock/pid" 2>/dev/null || true)"
  if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
    echo "ERROR: dispatch recusado — já existe um run vivo neste workdir (pid dono $owner; lock em $lock). Espere o run acabar; o veredito dele sai em: oracfit status --task <task>" >&2
    return 6
  fi
  # pid morto ou sem pid file: lock órfão — assumir, não recusar (run morto
  # não pode segurar o workdir para sempre; incidente 2026-08-27).
  echo "aviso: lock órfão (pid ${owner:-ausente} morto) — assumindo o workdir: $lock" >&2
  rm -rf "$lock"
  if ! mkdir "$lock" 2>/dev/null; then
    echo "ERROR: não consegui assumir o lock $lock (concorrência no takeover) — recusado" >&2
    return 6
  fi
  printf '%s\n' "$$" >"$lock/pid"
  ORACFIT_RUN_LOCK_DIR="$lock"
  return 0
}

oracfit_run_lock_release() {
  [ -n "${ORACFIT_RUN_LOCK_DIR:-}" ] || return 0
  rm -rf "$ORACFIT_RUN_LOCK_DIR" 2>/dev/null || true
  ORACFIT_RUN_LOCK_DIR=""
}
