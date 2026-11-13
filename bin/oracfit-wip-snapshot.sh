#!/bin/bash
# oracfit-wip-snapshot.sh — a RESET that keeps the evidence (docs/decision-supervisor.md §5.5, rung D2).
# Source me. Nothing calls these functions yet: the call belongs to the decision-model rung.
#
#   oracfit_wip_ref_name <run_id> <iter>
#     prints refs/llms-surf/wip/<run_id>/iter-<iter>
#   oracfit_wip_snapshot <workdir> <run_id> <iter>
#     saves the dirty working tree (tracked edits AND untracked files) as a commit under that ref;
#     HEAD, the real index and the working tree stay byte-identical. Prints the commit sha.
#     0 = saved, or nothing to snapshot (no ref created); 2 = refused, nothing created; 1 = git failed
#   oracfit_wip_restore <workdir> <ref> <path>...
#     restores the listed paths from <ref> with `git checkout <ref> -- <path>`; HEAD does not move.
#     All or nothing: a protected path, a path inside .dispatch/, a path that escapes the workdir or
#     a path not in <ref> refuses the whole call. Never deletes a file. Prints the restored paths.
#     0 = restored; 3 = refused, nothing restored; 2 = bad workdir or ref; 1 = git failed
#   oracfit_wip_scar_line <run_id> <iter> <ref_path>
#     formats the one-line scar for the next attempt's spec; it checks nothing and injects nothing
#
# Messages go to stderr, prefixed "wip snapshot:" / "wip restore:"; stdout carries only the data.
# Each public function that touches git runs in a subshell: it clears the repository-local
# environment (GIT_DIR, GIT_INDEX_FILE, ... from `git rev-parse --local-env-vars`), so a git hook
# or an outer git command can never point it at another repository.

# Sourcing lib-oracfit-root.sh twice resets ORACFIT_RUN_LOCK_DIR and orphans a run lock the caller holds.
if ! declare -F oracfit_resolve_root >/dev/null 2>&1; then
  # shellcheck source=bin/lib-oracfit-root.sh
  . "$(dirname "${BASH_SOURCE[0]}")/lib-oracfit-root.sh"
fi

oracfit_wip_ref_name() {
  printf 'refs/llms-surf/wip/%s/iter-%s\n' "${1:-}" "${2:-}"
}

# _oracfit_wip_workdir_root <workdir> <label> — prints the physical path of a workdir that is the
# root of its repository; otherwise explains on stderr and returns 2.
_oracfit_wip_workdir_root() {
  local wd="$1" label="$2" real top
  if ! real="$(CDPATH='' cd -P -- "$wd" 2>/dev/null && pwd -P)" \
    || [ "$(git -C "$real" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
    echo "$label: not a git repository" >&2
    return 2
  fi
  top="$(git -C "$real" rev-parse --show-toplevel 2>/dev/null)"
  if [ "$top" != "$real" ]; then
    echo "$label: workdir is not the repository root" >&2
    return 2
  fi
  printf '%s\n' "$real"
}

oracfit_wip_snapshot() (
  # shellcheck disable=SC2046 # the variable names are meant to split
  unset $(git rev-parse --local-env-vars)
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  if [ $# -ne 3 ]; then
    echo "wip snapshot: usage: oracfit_wip_snapshot <workdir> <run_id> <iter>" >&2
    exit 2
  fi
  local run_id="$2" iter="$3" wd ref status base_commit base idx idx_dir out tree commit
  wd="$(_oracfit_wip_workdir_root "$1" "wip snapshot")" || exit 2
  ref="$(oracfit_wip_ref_name "$run_id" "$iter")"
  if ! git check-ref-format "$ref"; then
    echo "wip snapshot: invalid ref name: $ref" >&2
    exit 2
  fi

  # --no-optional-locks: a plain `git status` may rewrite the real index to refresh stat data.
  # -unormal: status.showUntrackedFiles=no would hide a tree whose only change is a new file.
  if ! status="$(git -C "$wd" --no-optional-locks status --porcelain -unormal)"; then
    echo "wip snapshot: git status failed in $wd" >&2
    exit 1
  fi
  if [ -z "$status" ]; then
    echo "wip snapshot: nothing to snapshot" >&2
    exit 0
  fi
  if git -C "$wd" rev-parse -q --verify "$ref" >/dev/null; then
    echo "wip snapshot: ref already exists: $ref (snapshots are immutable)" >&2
    exit 2
  fi

  base_commit="$(git -C "$wd" rev-parse -q --verify 'HEAD^{commit}')" || base_commit=""
  if [ -n "$base_commit" ]; then
    base="$base_commit"
  else
    base="$(git -C "$wd" hash-object -t tree /dev/null)" || exit 1
  fi

  # The scratch index lives outside the workdir: inside it, `git add -A` snapshots the index file
  # itself (and its .lock) unless the target repository happens to ignore that directory.
  if ! idx="$(mktemp "${TMPDIR:-/tmp}/oracfit-wip.XXXXXX")"; then
    echo "wip snapshot: mktemp failed" >&2
    exit 1
  fi
  trap 'rm -f "$idx" "$idx.lock"' EXIT
  # A zero-byte file is not a valid index: git refuses it.
  rm -f "$idx"
  idx_dir="$(CDPATH='' cd -P -- "$(dirname "$idx")" && pwd -P)" || exit 1
  idx="$idx_dir/$(basename "$idx")"
  case "$idx_dir/" in
    "$wd"/*)
      echo "wip snapshot: the scratch index would live inside the workdir ($idx_dir); point TMPDIR outside $wd" >&2
      exit 2
      ;;
  esac

  if ! GIT_INDEX_FILE="$idx" git -C "$wd" read-tree "$base"; then
    echo "wip snapshot: git read-tree $base failed" >&2
    exit 1
  fi
  if ! out="$(GIT_INDEX_FILE="$idx" git -C "$wd" add -A 2>&1)"; then
    echo "wip snapshot: git add -A failed: $out" >&2
    exit 1
  fi
  if ! tree="$(GIT_INDEX_FILE="$idx" git -C "$wd" write-tree)"; then
    echo "wip snapshot: git write-tree failed" >&2
    exit 1
  fi
  rm -f "$idx" "$idx.lock"

  # Explicit identity: the user may have none, and GIT_AUTHOR_* (cleared above) would override -c.
  if ! commit="$(git -C "$wd" -c user.email=llms.surf@localhost -c user.name=llms.surf \
    commit-tree "$tree" ${base_commit:+-p "$base_commit"} -m "llms.surf: wip run=$run_id iter=$iter")"; then
    echo "wip snapshot: git commit-tree failed" >&2
    exit 1
  fi
  # The empty old value makes update-ref refuse a ref that appeared since the check above.
  if ! git -C "$wd" update-ref "$ref" "$commit" ""; then
    echo "wip snapshot: could not create $ref (already exists?)" >&2
    exit 1
  fi
  printf '%s\n' "$commit"
)

# _oracfit_wip_normalize_path <path> — prints the path relative to the workdir root ("." for the
# root itself); returns 1 for an absolute path or one with a "." or ".." component, which could
# step around the protected globs (src/../core/x) or out of the workdir.
_oracfit_wip_normalize_path() {
  local p="$1"
  case "$p" in '' | /*) return 1 ;; esac
  while [[ "$p" == *//* ]]; do p="${p//\/\//\/}"; done
  while [[ "$p" == ./* ]]; do p="${p#./}"; done
  while [[ "$p" == */ ]]; do p="${p%/}"; done
  [ -n "$p" ] || p="."
  if [ "$p" != "." ]; then
    case "/$p/" in */./* | */../*) return 1 ;; esac
  fi
  printf '%s\n' "$p"
}

# _oracfit_wip_protected_glob <rel_path> <globs_file> — prints the glob that protects the path and
# returns 0, or returns 1. .dispatch/ is always protected. The glob loop must stay the same fnmatch
# as the protected-paths guard in bin/dispatch-mode.sh (`*` crosses `/`).
_oracfit_wip_protected_glob() {
  local f="$1" globs="$2" g
  case "$f" in (.dispatch | .dispatch/*) printf '%s\n' ".dispatch/**"; return 0 ;; esac
  [ -n "$globs" ] && [ -f "$globs" ] || return 1
  while IFS= read -r g || [ -n "$g" ]; do
    case "$g" in ('' | '#'*) continue ;; esac
    # shellcheck disable=SC2254 # deliberate glob: case fnmatch, `*` crosses `/`
    case "$f" in ($g) printf '%s\n' "$g"; return 0 ;; esac
  done <"$globs"
  return 1
}

oracfit_wip_restore() (
  # shellcheck disable=SC2046 # the variable names are meant to split
  unset $(git rev-parse --local-env-vars)
  if [ $# -lt 3 ]; then
    echo "wip restore: usage: oracfit_wip_restore <workdir> <ref> <path> [<path> ...]" >&2
    exit 2
  fi
  local ref="$2" wd commit globs="" root p rel f g found blocked refused=0
  wd="$(_oracfit_wip_workdir_root "$1" "wip restore")" || exit 2
  shift 2
  if ! commit="$(git -C "$wd" rev-parse -q --verify "$ref^{commit}")"; then
    echo "wip restore: ref not found: $ref" >&2
    exit 2
  fi

  # Same choice as bin/dispatch-mode.sh: <workdir>/.oracfit-protected wins; the default list only
  # applies when the workdir is the Oracfit checkout itself.
  if [ -f "$wd/.oracfit-protected" ]; then
    globs="$wd/.oracfit-protected"
  else
    root="$(oracfit_resolve_root 2>/dev/null)" || root=""
    if [ -n "$root" ] && [ "$root" = "$wd" ] && [ -f "$root/core/protected-paths-default.txt" ]; then
      globs="$root/core/protected-paths-default.txt"
    fi
  fi

  local -a targets=()
  for p in "$@"; do
    if ! rel="$(_oracfit_wip_normalize_path "$p")"; then
      echo "wip restore: path must be relative and stay inside the workdir: $p" >&2
      refused=1
      continue
    fi
    if g="$(_oracfit_wip_protected_glob "$rel" "$globs")"; then
      echo "wip restore: refused protected path: $rel (glob $g)" >&2
      refused=1
      continue
    fi
    # A directory restores every file under it, so each of those files must pass the globs too.
    found=0
    blocked=0
    while IFS= read -r -d '' f; do
      found=1
      if g="$(_oracfit_wip_protected_glob "$f" "$globs")"; then
        echo "wip restore: refused protected path: $f (inside $rel, glob $g)" >&2
        blocked=1
      fi
    done < <(git -C "$wd" --literal-pathspecs ls-tree -r -z --name-only "$commit" -- "$rel")
    if [ "$found" -eq 0 ]; then
      echo "wip restore: path not in ref: $rel" >&2
      refused=1
    elif [ "$blocked" -eq 1 ]; then
      refused=1
    else
      targets+=("$rel")
    fi
  done
  if [ "$refused" -ne 0 ]; then
    echo "wip restore: nothing restored" >&2
    exit 3
  fi

  # Overlay mode (checkout's default): files absent from the ref are left alone, never deleted.
  if ! git -C "$wd" --literal-pathspecs checkout -q "$commit" -- "${targets[@]}"; then
    echo "wip restore: git checkout $ref failed" >&2
    exit 1
  fi
  printf '%s\n' "${targets[@]}"
)

# <run_id> is part of the signature for symmetry with the ref; the line names the run through
# <ref_path>. Newlines in the arguments become spaces so the scar stays one line.
oracfit_wip_scar_line() {
  local iter="${2:-}" ref_path="${3:-}"
  iter="${iter//[$'\r\n']/ }"
  ref_path="${ref_path//[$'\r\n']/ }"
  printf '[SUPERVISOR]: your attempt %s degraded the tree without reducing the errors. The state was saved in %s. The out-of-scope files were restored to the last clean checkpoint. Do not repeat this approach.\n' "$iter" "$ref_path"
}
