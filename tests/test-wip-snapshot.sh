#!/usr/bin/env bash
# tests/test-wip-snapshot.sh — mechanism test for bin/oracfit-wip-snapshot.sh (rung D2,
# docs/decision-supervisor.md §5.5): the WIP snapshot, the scoped restore and the scar line.
#
# Hermetic: every repository is a scratch repo under $TMPDIR, the global git config is a scratch
# file with no identity, and no network or model is involved. The real checkout is only read
# (core/protected-paths-default.txt is copied into a scratch checkout).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# A git hook or an outer dispatch may export GIT_DIR & co; the scratch repos must not inherit them.
# shellcheck disable=SC2046 # the variable names are meant to split
unset $(git rev-parse --local-env-vars)
unset DISPATCH_ROOT GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/test-wip-snapshot.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

# No identity and no guessing: the library must bring its own. Untracked files hidden from
# `git status`: the library must still see a tree whose only change is a new file.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"
printf '[user]\n\tuseConfigOnly = true\n[status]\n\tshowUntrackedFiles = no\n[init]\n\tdefaultBranch = main\n' \
  >"$GIT_CONFIG_GLOBAL"

# The scratch index goes to $TMPDIR; a dedicated one lets the test prove it is cleaned up.
export TMPDIR="$SCRATCH/tmp"
mkdir -p "$TMPDIR"

# The workdirs below are never the Oracfit checkout unless a case says so.
export ORACFIT_ROOT="$REPO_ROOT"

# shellcheck source=bin/oracfit-wip-snapshot.sh
. "$REPO_ROOT/bin/oracfit-wip-snapshot.sh"

passed=0
failed=0
pass() { echo "PASS: $1"; passed=$((passed + 1)); }
fail() { echo "FAIL: $1"; failed=$((failed + 1)); }
check() {  # check <description> <command...>
  local desc="$1"
  shift
  if "$@"; then pass "$desc"; else fail "$desc"; fi
}

git_t() {  # git_t <repo> <git args...> — the test's own commits carry a throwaway identity
  local repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@localhost -c core.hooksPath=/dev/null "$@"
}
new_repo() {  # new_repo <dir> — empty repository, no commit
  mkdir -p "$1"
  git -C "$1" init -q
}
commit_all() {  # commit_all <repo> <message>
  git_t "$1" add -A && git_t "$1" commit -q -m "$2"
}
wip_refs() {  # wip_refs <repo> — how many refs live under refs/llms-surf/
  git -C "$1" for-each-ref refs/llms-surf/ | wc -l | tr -d ' '
}
file_is() {  # file_is <file> <expected content>
  [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]
}
contains() {  # contains <haystack> <needle>
  case "$1" in (*"$2"*) return 0 ;; esac
  return 1
}
tmpdir_is_empty() {
  [ -z "$(ls -A "$TMPDIR")" ]
}

# ═══ snapshot captures the drift ═══
echo "=== snapshot captures the drift ==="
R1="$SCRATCH/r1"
new_repo "$R1"
echo "tracked v1" >"$R1/tracked.txt"
echo "other v1" >"$R1/other.txt"
commit_all "$R1" init
echo "tracked v2 drift" >"$R1/tracked.txt"
echo "agent new file" >"$R1/new.txt"

head_before="$(git -C "$R1" rev-parse HEAD)"
status_before="$(git -C "$R1" status --porcelain -unormal)"
index_before="$(cksum <"$R1/.git/index")"
REF1="$(oracfit_wip_ref_name run-abc 1)"

SHA1="$(oracfit_wip_snapshot "$R1" run-abc 1 2>"$SCRATCH/err")"
rc=$?
check "snapshot exits 0" [ "$rc" -eq 0 ]
check "snapshot prints a commit sha" [ "$(git -C "$R1" cat-file -t "$SHA1" 2>/dev/null)" = "commit" ]
check "snapshot tree holds the EDITED content of the tracked file" \
  [ "$(git -C "$R1" show "$REF1:tracked.txt" 2>/dev/null)" = "tracked v2 drift" ]
check "snapshot tree holds the untracked file" \
  [ "$(git -C "$R1" show "$REF1:new.txt" 2>/dev/null)" = "agent new file" ]
check "snapshot parent is the HEAD it was taken on" \
  [ "$(git -C "$R1" rev-parse "$SHA1^" 2>/dev/null)" = "$head_before" ]
check "snapshot tree does not hold the scratch index" \
  [ -z "$(git -C "$R1" ls-tree -r --name-only "$SHA1" | grep -i 'idx\|index\|oracfit-wip')" ]

# ═══ nothing moves ═══
echo ""
echo "=== nothing moves ==="
index_after="$(cksum <"$R1/.git/index")"
check "HEAD is the same sha" [ "$(git -C "$R1" rev-parse HEAD)" = "$head_before" ]
check "git status --porcelain is identical" [ "$(git -C "$R1" status --porcelain -unormal)" = "$status_before" ]
check "real index is byte-identical" [ "$index_after" = "$index_before" ]
check "tracked file is still modified in the working tree" \
  [ "$(git -C "$R1" diff --name-only)" = "tracked.txt" ]
check "new file is still untracked" [ "$(git -C "$R1" ls-files --others --exclude-standard)" = "new.txt" ]
check "scratch index removed from TMPDIR" tmpdir_is_empty

# ═══ the ref name ═══
echo ""
echo "=== the ref name ==="
check "oracfit_wip_ref_name prints refs/llms-surf/wip/<run>/iter-<n>" \
  [ "$REF1" = "refs/llms-surf/wip/run-abc/iter-1" ]
check "the ref exists and points to the printed sha" \
  [ "$(git -C "$R1" rev-parse -q --verify refs/llms-surf/wip/run-abc/iter-1)" = "$SHA1" ]
msg1="$(git -C "$R1" log -1 --format=%B "$SHA1")"
check "commit message carries run id and iteration" contains "$msg1" "run=run-abc iter=1"
check "commit identity is llms.surf, not the user's" \
  [ "$(git -C "$R1" log -1 --format='%an <%ae>|%cn <%ce>' "$SHA1")" = "llms.surf <llms.surf@localhost>|llms.surf <llms.surf@localhost>" ]

out="$(GIT_AUTHOR_NAME=intruder GIT_COMMITTER_EMAIL=intruder@x oracfit_wip_snapshot "$R1" run-abc 2 2>/dev/null)"
check "an exported GIT_AUTHOR_NAME does not change the identity" \
  [ "$(git -C "$R1" log -1 --format='%an|%ce' "$out" 2>/dev/null)" = "llms.surf|llms.surf@localhost" ]

out="$(oracfit_wip_snapshot "$R1" run-abc 1 2>&1)"
rc=$?
check "the same run/iter again is refused with exit 2" [ "$rc" -eq 2 ]
check "the refusal says the ref already exists" contains "$out" "ref already exists"
check "the existing snapshot is not overwritten" [ "$(git -C "$R1" rev-parse "$REF1")" = "$SHA1" ]

# ═══ clean tree ═══
echo ""
echo "=== clean tree ==="
R2="$SCRATCH/r2"
new_repo "$R2"
echo "clean" >"$R2/a.txt"
commit_all "$R2" init
stdout="$(oracfit_wip_snapshot "$R2" run-clean 1 2>"$SCRATCH/err")"
rc=$?
check "clean tree exits 0" [ "$rc" -eq 0 ]
check "clean tree says nothing to snapshot" contains "$(cat "$SCRATCH/err")" "nothing to snapshot"
check "clean tree prints no sha" [ -z "$stdout" ]
check "clean tree creates no ref" [ "$(wip_refs "$R2")" = "0" ]

# ═══ not a repository ═══
echo ""
echo "=== not a repository ==="
mkdir -p "$SCRATCH/plain"
echo "x" >"$SCRATCH/plain/x.txt"
out="$(oracfit_wip_snapshot "$SCRATCH/plain" run-x 1 2>&1)"
rc=$?
check "plain directory exits 2" [ "$rc" -eq 2 ]
check "plain directory says not a git repository" contains "$out" "not a git repository"
out="$(oracfit_wip_snapshot "$SCRATCH/does-not-exist" run-x 1 2>&1)"
rc=$?
check "missing directory exits 2 as not a git repository" \
  bash -c '[ "$1" -eq 2 ] && case "$2" in (*"not a git repository"*) exit 0 ;; esac; exit 1' _ "$rc" "$out"

# ═══ workdir that is not the repository root ═══
echo ""
echo "=== workdir that is not the repository root ==="
mkdir -p "$R1/sub"
echo "in sub" >"$R1/sub/s.txt"
refs_before="$(wip_refs "$R1")"
out="$(oracfit_wip_snapshot "$R1/sub" run-sub 1 2>&1)"
rc=$?
check "subdirectory exits 2" [ "$rc" -eq 2 ]
check "subdirectory says workdir is not the repository root" contains "$out" "workdir is not the repository root"
check "subdirectory creates no ref" [ "$(wip_refs "$R1")" = "$refs_before" ]
rm -rf "$R1/sub"

# ═══ repository without a commit ═══
echo ""
echo "=== repository without a commit ==="
R3="$SCRATCH/r3"
new_repo "$R3"
echo "first file" >"$R3/first.txt"
SHA3="$(oracfit_wip_snapshot "$R3" run-unborn 1 2>"$SCRATCH/err")"
rc=$?
check "unborn repo exits 0 (untracked-only tree is not 'nothing')" [ "$rc" -eq 0 ]
check "unborn repo snapshot holds the untracked file" \
  [ "$(git -C "$R3" show "refs/llms-surf/wip/run-unborn/iter-1:first.txt" 2>/dev/null)" = "first file" ]
check "unborn repo snapshot has no parent" [ "$(git -C "$R3" rev-list --parents -n 1 "$SHA3" 2>/dev/null)" = "$SHA3" ]
check "unborn repo still has no HEAD" bash -c '! git -C "$1" rev-parse -q --verify HEAD >/dev/null' _ "$R3"

# ═══ the scratch index never lands inside the workdir ═══
echo ""
echo "=== the scratch index never lands inside the workdir ==="
mkdir -p "$R3/tmp-inside"
out="$(TMPDIR="$R3/tmp-inside" oracfit_wip_snapshot "$R3" run-inside 1 2>&1)"
rc=$?
check "TMPDIR inside the workdir is refused with exit 2" [ "$rc" -eq 2 ]
check "no ref created when TMPDIR is inside the workdir" \
  bash -c '! git -C "$1" rev-parse -q --verify refs/llms-surf/wip/run-inside/iter-1 >/dev/null' _ "$R3"
check "no scratch index left inside the workdir" [ -z "$(ls -A "$R3/tmp-inside")" ]
rm -rf "$R3/tmp-inside"

# An unreadable file makes `git add -A` fail after the scratch index already exists.
echo "secret" >"$R3/unreadable.txt"
chmod 000 "$R3/unreadable.txt"
if [ -r "$R3/unreadable.txt" ]; then
  echo "SKIP: scratch index cleanup on failure (running as a user that reads mode-000 files)"
else
  out="$(oracfit_wip_snapshot "$R3" run-fail 1 2>&1)"
  rc=$?
  check "a failing git add -A exits 1" [ "$rc" -eq 1 ]
  check "a failing git add -A creates no ref" \
    bash -c '! git -C "$1" rev-parse -q --verify refs/llms-surf/wip/run-fail/iter-1 >/dev/null' _ "$R3"
  check "the scratch index is removed on failure too" tmpdir_is_empty
fi
chmod 600 "$R3/unreadable.txt"
rm -f "$R3/unreadable.txt"

# ═══ scoped restore ═══
echo ""
echo "=== scoped restore ==="
echo "tracked v3 worse" >"$R1/tracked.txt"
echo "other v2 worse" >"$R1/other.txt"
echo "agent scratch notes" >"$R1/notes.txt"
stdout="$(oracfit_wip_restore "$R1" "$REF1" tracked.txt 2>"$SCRATCH/err")"
rc=$?
check "restore of one path exits 0" [ "$rc" -eq 0 ]
check "restore prints the restored path" [ "$stdout" = "tracked.txt" ]
check "the restored path has the ref's content" file_is "$R1/tracked.txt" "tracked v2 drift"
check "the other file is still modified" file_is "$R1/other.txt" "other v2 worse"
check "HEAD did not move" [ "$(git -C "$R1" rev-parse HEAD)" = "$head_before" ]

# ═══ nothing is deleted ═══
echo ""
echo "=== nothing is deleted ==="
check "an untracked file created by the agent survives the restore" file_is "$R1/notes.txt" "agent scratch notes"
echo "tracked after the snapshot" >"$R1/late.txt"
git -C "$R1" add late.txt
stdout="$(oracfit_wip_restore "$R1" "$REF1" . 2>"$SCRATCH/err")"
rc=$?
check "whole-tree restore exits 0" [ "$rc" -eq 0 ]
check "whole-tree restore brings back the ref's content" file_is "$R1/other.txt" "other v1"
check "untracked file survives a whole-tree restore" file_is "$R1/notes.txt" "agent scratch notes"
check "tracked file absent from the ref survives a whole-tree restore" file_is "$R1/late.txt" "tracked after the snapshot"

# ═══ path not in the ref ═══
echo ""
echo "=== path not in the ref ==="
echo "other v3 worse" >"$R1/other.txt"
out="$(oracfit_wip_restore "$R1" "$REF1" other.txt late.txt 2>&1)"
rc=$?
check "a path not in the ref exits 3" [ "$rc" -eq 3 ]
check "the message says path not in ref: <path>" contains "$out" "wip restore: path not in ref: late.txt"
check "the tracked file absent from the ref is not deleted" file_is "$R1/late.txt" "tracked after the snapshot"
check "all or nothing: the valid path alongside it is not restored" file_is "$R1/other.txt" "other v3 worse"
out="$(oracfit_wip_restore "$R1" refs/llms-surf/wip/no-such/iter-1 other.txt 2>&1)"
rc=$?
check "an unknown ref exits 2" [ "$rc" -eq 2 ]

# ═══ protected zone is refused (.oracfit-protected) ═══
echo ""
echo "=== protected zone is refused (.oracfit-protected: core/*) ==="
R4="$SCRATCH/r4"
new_repo "$R4"
mkdir -p "$R4/core" "$R4/src"
echo "engine v1" >"$R4/core/engine.sh"
echo "app v1" >"$R4/src/app.txt"
printf 'core/*\n' >"$R4/.oracfit-protected"
commit_all "$R4" init
echo "engine v2 drift" >"$R4/core/engine.sh"
echo "app v2 drift" >"$R4/src/app.txt"
oracfit_wip_snapshot "$R4" run-prot 1 >/dev/null 2>&1
REF4="$(oracfit_wip_ref_name run-prot 1)"
echo "engine v3 live" >"$R4/core/engine.sh"
echo "app v3 worse" >"$R4/src/app.txt"
out="$(oracfit_wip_restore "$R4" "$REF4" core/engine.sh 2>&1)"
rc=$?
check "core/engine.sh is refused with exit 3" [ "$rc" -eq 3 ]
check "the refused path is listed" contains "$out" "refused protected path: core/engine.sh"
check "the protected file is not touched" file_is "$R4/core/engine.sh" "engine v3 live"
out="$(oracfit_wip_restore "$R4" "$REF4" core 2>&1)"
rc=$?
check "the directory core/ is refused too (its files match core/*)" [ "$rc" -eq 3 ]
check "the directory refusal names the protected file inside it" contains "$out" "core/engine.sh"
out="$(oracfit_wip_restore "$R4" "$REF4" src/app.txt core/engine.sh 2>&1)"
rc=$?
check "a protected path refuses the whole call" [ "$rc" -eq 3 ]
check "all or nothing: the unprotected path is not restored" file_is "$R4/src/app.txt" "app v3 worse"
out="$(oracfit_wip_restore "$R4" "$REF4" src/../core/engine.sh 2>&1)"
rc=$?
check "a .. path cannot step around the globs (exit 3)" [ "$rc" -eq 3 ]
check "the .. path is refused before git sees it" contains "$out" "must be relative and stay inside the workdir: src/../core/engine.sh"
out="$(oracfit_wip_restore "$R4" "$REF4" "$R4/core/engine.sh" 2>&1)"
rc=$?
check "an absolute path is refused (exit 3)" [ "$rc" -eq 3 ]
check "the absolute path is refused before git sees it" contains "$out" "must be relative and stay inside the workdir"
check "the protected file is still untouched" file_is "$R4/core/engine.sh" "engine v3 live"
stdout="$(oracfit_wip_restore "$R4" "$REF4" ./src/app.txt 2>/dev/null)"
rc=$?
check "the unprotected path restores on its own" \
  bash -c '[ "$1" -eq 0 ] && [ "$(cat "$2")" = "app v2 drift" ]' _ "$rc" "$R4/src/app.txt"

# ═══ .dispatch/ is refused ═══
echo ""
echo "=== .dispatch/ is refused (no protected list at all) ==="
R5="$SCRATCH/r5"
new_repo "$R5"
mkdir -p "$R5/.dispatch" "$R5/core"
echo "state v1" >"$R5/.dispatch/state.txt"
echo "engine v1" >"$R5/core/engine.sh"
commit_all "$R5" init
echo "state v2" >"$R5/.dispatch/state.txt"
echo "engine v2 drift" >"$R5/core/engine.sh"
oracfit_wip_snapshot "$R5" run-disp 1 >/dev/null 2>&1
REF5="$(oracfit_wip_ref_name run-disp 1)"
echo "state v3 live" >"$R5/.dispatch/state.txt"
echo "engine v3 worse" >"$R5/core/engine.sh"
out="$(oracfit_wip_restore "$R5" "$REF5" .dispatch/state.txt 2>&1)"
rc=$?
check ".dispatch/state.txt is refused with exit 3" [ "$rc" -eq 3 ]
check "the refusal has the same output as a protected glob" contains "$out" "refused protected path: .dispatch/state.txt"
check "the .dispatch file is not touched" file_is "$R5/.dispatch/state.txt" "state v3 live"
out="$(oracfit_wip_restore "$R5" "$REF5" . 2>&1)"
rc=$?
check "a whole-tree restore that would write into .dispatch/ is refused" [ "$rc" -eq 3 ]
stdout="$(oracfit_wip_restore "$R5" "$REF5" core/engine.sh 2>/dev/null)"
rc=$?
check "with no list, core/ is not protected: nothing but .dispatch/ is" \
  bash -c '[ "$1" -eq 0 ] && [ "$(cat "$2")" = "engine v2 drift" ]' _ "$rc" "$R5/core/engine.sh"

# ═══ the default list applies when the workdir is the Oracfit checkout ═══
echo ""
echo "=== default list when the workdir is the Oracfit checkout ==="
R6="$SCRATCH/r6"
new_repo "$R6"
mkdir -p "$R6/core" "$R6/bin" "$R6/src"
cp "$REPO_ROOT/core/protected-paths-default.txt" "$R6/core/protected-paths-default.txt"
echo "tool v1" >"$R6/bin/tool.sh"
echo "x v1" >"$R6/src/x.txt"
commit_all "$R6" init
echo "tool v2 drift" >"$R6/bin/tool.sh"
echo "x v2 drift" >"$R6/src/x.txt"
oracfit_wip_snapshot "$R6" run-def 1 >/dev/null 2>&1
REF6="$(oracfit_wip_ref_name run-def 1)"
echo "tool v3 live" >"$R6/bin/tool.sh"
echo "x v3 worse" >"$R6/src/x.txt"
export ORACFIT_ROOT="$R6"
out="$(oracfit_wip_restore "$R6" "$REF6" bin/tool.sh 2>&1)"
rc=$?
check "bin/tool.sh is refused by core/protected-paths-default.txt (exit 3)" [ "$rc" -eq 3 ]
check "the running script is not touched" file_is "$R6/bin/tool.sh" "tool v3 live"
stdout="$(oracfit_wip_restore "$R6" "$REF6" src/x.txt 2>/dev/null)"
rc=$?
check "src/x.txt is outside the default list and restores" \
  bash -c '[ "$1" -eq 0 ] && [ "$(cat "$2")" = "x v2 drift" ]' _ "$rc" "$R6/src/x.txt"
printf 'src/*\n' >"$R6/.oracfit-protected"
echo "x v4 worse" >"$R6/src/x.txt"
out="$(oracfit_wip_restore "$R6" "$REF6" src/x.txt 2>&1)"
rc=$?
check "<workdir>/.oracfit-protected wins over the default list (src/* refused)" [ "$rc" -eq 3 ]
stdout="$(oracfit_wip_restore "$R6" "$REF6" bin/tool.sh 2>/dev/null)"
rc=$?
check "with .oracfit-protected present, the default list no longer applies" [ "$rc" -eq 0 ]
export ORACFIT_ROOT="$REPO_ROOT"

# ═══ the scar ═══
echo ""
echo "=== the scar ==="
scar="$(oracfit_wip_scar_line run-abc 2 refs/llms-surf/wip/run-abc/iter-2)"
check "scar is exactly one line" [ "$(oracfit_wip_scar_line run-abc 2 refs/llms-surf/wip/run-abc/iter-2 | wc -l | tr -d ' ')" = "1" ]
check "scar starts with [SUPERVISOR]:" contains "$scar" "[SUPERVISOR]:"
check "scar names the ref" contains "$scar" "refs/llms-surf/wip/run-abc/iter-2"
check "scar has the contract text" [ "$scar" = "[SUPERVISOR]: your attempt 2 degraded the tree without reducing the errors. The state was saved in refs/llms-surf/wip/run-abc/iter-2. The out-of-scope files were restored to the last clean checkpoint. Do not repeat this approach." ]
check "a newline in the arguments does not break the line" \
  [ "$(oracfit_wip_scar_line run-abc 2 "$(printf 'refs/a\nrefs/b')" | wc -l | tr -d ' ')" = "1" ]

echo ""
echo "test-wip-snapshot: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
