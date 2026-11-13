# lib-oracfit-checkpoint.sh — a side-ref snapshot of tracked files (not HEAD).
# Source me. Public:
#
#   oracfit_checkpoint_ref_name <run_id> <label>
#     prints refs/llms-surf/checkpoint/<run_id>/<label>
#   oracfit_checkpoint_commit <workdir> <ref_name> [message]
#     commits the working-tree state of tracked files only, under that ref,
#     using a scratch index. HEAD, the real index and the working tree stay
#     untouched. Untracked files are not included. Prints the commit sha.
#     0 = created; 2 = refused, nothing created; 1 = git failed
#
# The checkpoint is additive: it creates a ref. Nothing is deleted, and an
# existing ref is left as it is (the call refuses rather than overwrite).
# Messages go to stderr, prefixed "checkpoint:"; stdout carries only the sha.
# Each public function that touches git runs in a subshell and clears the
# repository-local environment, so a git hook or an outer git command can
# never point it at another repository.

oracfit_checkpoint_ref_name() {
  printf 'refs/llms-surf/checkpoint/%s/%s\n' "${1:-}" "${2:-}"
}

# _oracfit_checkpoint_workdir_root <workdir> — prints the physical path of a
# workdir that is the root of its repository; otherwise explains on stderr
# and returns 2.
_oracfit_checkpoint_workdir_root() {
  local wd="$1" real top
  if ! real="$(CDPATH='' cd -P -- "$wd" 2>/dev/null && pwd -P)" \
    || [ "$(git -C "$real" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
    echo "checkpoint: not a git repository" >&2
    return 2
  fi
  top="$(git -C "$real" rev-parse --show-toplevel 2>/dev/null)"
  if [ "$top" != "$real" ]; then
    echo "checkpoint: workdir is not the repository root" >&2
    return 2
  fi
  printf '%s\n' "$real"
}

oracfit_checkpoint_commit() (
  # shellcheck disable=SC2046 # the variable names are meant to split
  unset $(git rev-parse --local-env-vars)
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "checkpoint: usage: oracfit_checkpoint_commit <workdir> <ref_name> [message]" >&2
    exit 2
  fi
  local wd ref msg base_commit base idx idx_dir out tree commit
  wd="$(_oracfit_checkpoint_workdir_root "$1")" || exit 2
  ref="$2"
  msg="${3:-llms.surf: checkpoint}"
  if ! git check-ref-format "$ref"; then
    echo "checkpoint: invalid ref name: $ref" >&2
    exit 2
  fi
  if git -C "$wd" rev-parse -q --verify "$ref" >/dev/null; then
    echo "checkpoint: ref already exists: $ref" >&2
    exit 2
  fi

  base_commit="$(git -C "$wd" rev-parse -q --verify 'HEAD^{commit}')" || base_commit=""
  if [ -n "$base_commit" ]; then
    base="$base_commit"
  else
    base="$(git -C "$wd" hash-object -t tree /dev/null)" || exit 1
  fi

  # The scratch index lives outside the workdir: inside it, a git add could
  # pick the index file itself up as a new file unless that directory happens
  # to be ignored. The target repository's .gitignore is not ours to assume.
  if ! idx="$(mktemp "${TMPDIR:-/tmp}/oracfit-ckpt.XXXXXX")"; then
    echo "checkpoint: mktemp failed" >&2
    exit 1
  fi
  trap 'rm -f "$idx" "$idx.lock"' EXIT
  # A zero-byte file is not a valid index: git refuses it.
  rm -f "$idx"
  idx_dir="$(CDPATH='' cd -P -- "$(dirname "$idx")" && pwd -P)" || exit 1
  idx="$idx_dir/$(basename "$idx")"
  case "$idx_dir/" in
    "$wd"/*)
      echo "checkpoint: the scratch index would live inside the workdir ($idx_dir); point TMPDIR outside $wd" >&2
      exit 2
      ;;
  esac

  if ! GIT_INDEX_FILE="$idx" git -C "$wd" --no-optional-locks read-tree "$base"; then
    echo "checkpoint: git read-tree $base failed" >&2
    exit 1
  fi
  # -u: tracked files only. A new file the agent created stays untracked.
  if ! out="$(GIT_INDEX_FILE="$idx" git -C "$wd" --no-optional-locks add -u -- . 2>&1)"; then
    echo "checkpoint: git add -u failed: $out" >&2
    exit 1
  fi
  if ! tree="$(GIT_INDEX_FILE="$idx" git -C "$wd" --no-optional-locks write-tree)"; then
    echo "checkpoint: git write-tree failed" >&2
    exit 1
  fi
  rm -f "$idx" "$idx.lock"

  # Explicit identity: the user may have none, and GIT_AUTHOR_* (cleared above)
  # would override -c.
  if ! commit="$(git -C "$wd" -c user.email=llms.surf@localhost -c user.name=llms.surf \
    commit-tree "$tree" ${base_commit:+-p "$base_commit"} -m "$msg")"; then
    echo "checkpoint: git commit-tree failed" >&2
    exit 1
  fi
  # The empty old value makes update-ref refuse a ref that appeared since the
  # check above. The old ref, if any other, is left as it is.
  if ! git -C "$wd" update-ref "$ref" "$commit" ""; then
    echo "checkpoint: could not create $ref (already exists?)" >&2
    exit 1
  fi
  printf '%s\n' "$commit"
)
