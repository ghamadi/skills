#!/usr/bin/env bash
# Run check commands in the repository, each logged to <run_dir>/logs.
#
# Usage: run-checks.sh <run_dir> <command> [<command> ...]
#
# Prints, per command: check, status (passed | failed), exit code, log path and line count, and `modified:` with the
# paths it wrote when it changed any file git does not ignore, or `modified: unknown` when git could not snapshot the
# tree.
# Every failure, a missing or non-executable command included, is left for the reviewer to classify: the branch may
# have deleted or renamed the script a check calls.
# Commands run with CI=true, so test runners that watch by default run once and exit.

set -u
here=$(cd "$(dirname "$0")" && pwd -P)
. "$here/lib.sh"

run_dir=${1-}
load_env "$run_dir"
[ $# -gt 1 ] || die "usage: run-checks.sh <run_dir> <command> [<command> ...]"
shift
mkdir -p "$run_dir/logs"

# Print a tree id for every file in the repository that git does not ignore, or `failed: <git's first error line>`.
# Built in a scratch copy of the index, so the user's staged changes are untouched; `git status` alone would miss a
# write to a file that was already modified.
snapshot() {
  (
    cd "$repo_root" || exit 1
    index="$run_dir/snapshot-index"
    cp "$(git rev-parse --git-path index)" "$index" 2>/dev/null || rm -f "$index"
    if ! err=$(GIT_INDEX_FILE="$index" git add -A 2>&1 >/dev/null); then
      echo "failed: $(printf '%s\n' "$err" | head -n 1)"
    elif ! GIT_INDEX_FILE="$index" git write-tree 2>/dev/null; then
      echo "failed: could not write the tree"
    fi
  )
}

before=$(snapshot)
for cmd in "$@"; do
  slug=$(printf '%s' "$cmd" | tr -cs 'A-Za-z0-9' '-' | cut -c1-48 | sed 's/^-//; s/-$//')
  log="$run_dir/logs/${slug:-check}.log"
  i=2
  while [ -e "$log" ]; do
    log="$run_dir/logs/${slug:-check}-$i.log"
    i=$((i + 1))
  done

  (cd "$repo_root" && CI=true bash -c "$cmd") >"$log" 2>&1 </dev/null
  code=$?
  after=$(snapshot)
  case $code in
    0) status="passed" ;;
    126 | 127) status="failed (command not found or not executable)" ;;
    *) status="failed" ;;
  esac
  echo "check: $cmd"
  echo "status: $status"
  echo "exit: $code"
  echo "log: $log ($(awk 'END { print NR }' "$log") lines)"
  unknown=""
  case "$before" in failed:*) unknown=${before#failed: } ;; esac
  case "$after" in failed:*) unknown=${after#failed: } ;; esac
  if [ -n "$unknown" ]; then
    echo "modified: unknown (could not snapshot the tree: $unknown)"
  elif [ "$before" != "$after" ]; then
    paths=$(git -C "$repo_root" -c core.quotePath=false diff-tree -r --name-only "$before" "$after" | paste -sd ',' - | sed 's/,/, /g')
    echo "modified: $paths (what it wrote: git diff-tree -p $before $after)"
  fi
  echo
  before=$after
done
exit 0
