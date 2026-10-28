#!/usr/bin/env bash
# Resolve the review's refs and prepare a fresh run directory.
#
# Usage: setup.sh --base <ref>
#
# Run from inside the repository. Refs are used exactly as they exist locally; nothing is fetched.
# Prints `status: ok | empty | error` followed by key: value lines.

set -u
here=$(cd "$(dirname "$0")" && pwd -P)
. "$here/lib.sh"

base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base=${2-}; shift ;;
    *) die "unknown argument '$1'; usage: setup.sh --base <ref>" ;;
  esac
  [ $# -gt 0 ] && shift
done
[ -n "$base" ] || die "missing --base <ref>"

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
cd "$repo_root" || die "cannot enter $repo_root"

base_sha=$(git rev-parse --verify --quiet "$base^{commit}") || die "base ref '$base' does not resolve to a commit"
head_sha=$(git rev-parse --verify --quiet "HEAD^{commit}") || die "HEAD has no commits"
label=$(git symbolic-ref --short -q HEAD) || label="HEAD (detached)"
merge_base=$(git merge-base "$base_sha" "$head_sha") || die "'$base' and '$label' share no history"

# Plumbing, like inventory.sh, so the user's diff and status settings cannot hide a change.
git update-index -q --refresh >/dev/null 2>&1
untracked=$(git ls-files --others --exclude-standard | head -n 1)
git diff-index --quiet "$merge_base" && [ -z "$untracked" ] && empty=yes || empty=no
git diff-index --quiet HEAD && [ -z "$untracked" ] && uncommitted=no || uncommitted=yes
if [ "$empty" = yes ]; then
  echo "status: empty"
  echo "branch: $label"
  echo "base: $base"
  exit 0
fi

# One private directory per run, so two reviews of the same repository never share one.
tmp=${TMPDIR:-/tmp}
run_dir=$(mktemp -d "${tmp%/}/branch-review-$(basename "$repo_root").XXXXXX") || die "cannot create a run directory in $tmp"
run_dir=$(cd "$run_dir" && pwd -P)
mkdir -p "$run_dir/logs" || die "cannot create $run_dir/logs"

put_env repo_root "$repo_root"
put_env base "$base"
put_env base_sha "$base_sha"
put_env head_sha "$head_sha"
put_env merge_base "$merge_base"
put_env uncommitted "$uncommitted"

echo "status: ok"
echo "repo_root: $repo_root"
echo "run_dir: $run_dir"
echo "branch: $label ($(git rev-parse --short "$head_sha"))"
echo "uncommitted: $uncommitted"
echo "base: $base ($(git rev-parse --short "$base_sha"))"
echo "merge_base: $merge_base"
echo "base_moved: $(git rev-list --count "$merge_base..$base_sha") commits since merge-base"
exit 0
