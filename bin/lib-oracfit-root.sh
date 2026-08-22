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
