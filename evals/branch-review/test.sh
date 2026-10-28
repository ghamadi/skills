#!/usr/bin/env bash
# Tests for the branch-review scripts, run against throwaway repositories.
#
# Usage: test.sh [<scripts-dir>]
#
# Every script runs under the bash running this file, so `/bin/bash test.sh` checks bash 3.2 (macOS) compatibility.

set -u
here=$(cd "$(dirname "$0")" && pwd -P)
scripts=$(cd "${1:-$here/../../skills/engineering/branch-review/scripts}" && pwd -P) || exit 2

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/branch-review-test.XXXXXX") || exit 2
sandbox=$(cd "$sandbox" && pwd -P) || exit 2
trap 'rm -rf "$sandbox"' EXIT
export TMPDIR="$sandbox/tmp"
mkdir -p "$TMPDIR"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$sandbox/gitconfig"
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main
git config --global advice.detachedHead false

passed=0
failed=0

run() {
  local script=$1
  shift
  "$BASH" "$scripts/$script" "$@" 2>&1
}

expect() { # <name> <output> <substring>
  if printf '%s\n' "$2" | grep -Fq -- "$3"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf 'FAIL: %s\n  expected: %s\n' "$1" "$3"
    printf '%s\n' "$2" | sed 's/^/  | /'
  fi
}

expect_not() { # <name> <output> <substring>
  if printf '%s\n' "$2" | grep -Fq -- "$3"; then
    failed=$((failed + 1))
    printf 'FAIL: %s\n  unexpected: %s\n' "$1" "$3"
    printf '%s\n' "$2" | sed 's/^/  | /'
  else
    passed=$((passed + 1))
  fi
}

value() { # <output> <key>: print the value of a `key: value` line
  printf '%s\n' "$1" | sed -n "s/^$2: //p" | head -n 1
}

numbered() { # <count> <prefix>: print numbered lines
  local i=1
  while [ "$i" -le "$1" ]; do
    echo "$2 $i"
    i=$((i + 1))
  done
}

replace_line() { # <file> <line> <text>
  awk -v n="$2" -v t="$3" 'NR == n { print t; next } { print }' "$1" >"$1.tmp" && mv "$1.tmp" "$1"
}

commit() {
  git add -A && git commit -qm "$1"
}

# --- setup: argument and ref errors ----------------------------------------------------------------------------

mkdir -p "$sandbox/norepo"
cd "$sandbox/norepo" || exit 2
out=$(run setup.sh --base main)
expect "setup outside a repo" "$out" "error: not inside a git repository"

repo="$sandbox/basic"
mkdir -p "$repo" && cd "$repo" && git init -q || exit 2
numbered 5 line >a.txt
commit base
git checkout -qb feat

out=$(run setup.sh)
expect "setup without --base" "$out" "error: missing --base <ref>"
out=$(run setup.sh origin/main)
expect "setup with a bare ref" "$out" "error: unknown argument 'origin/main'"
out=$(run setup.sh --base nope)
expect "setup with an unknown base" "$out" "error: base ref 'nope' does not resolve to a commit"
out=$(run setup.sh --base main)
expect "setup with no changes" "$out" "status: empty"
[ -z "$(ls "$TMPDIR" | grep '^branch-review-basic\.')" ] && passed=$((passed + 1)) ||
  { failed=$((failed + 1)); echo "FAIL: setup with no changes leaves no run directory"; }

# --- working-tree review: inventory -----------------------------------------------------------------------------

repo="$sandbox/full"
mkdir -p "$repo/src" "$repo/db/migrations" "$repo/gen" "$repo/docs" && cd "$repo" && git init -q || exit 2
numbered 40 app >src/app.js
numbered 10 old >src/old.js
numbered 5 gone >src/gone.js
numbered 10 conflict >src/conflict.js
numbered 10 both >src/both.js
numbered 3 lock >pnpm-lock.yaml
printf -- '-- v1\nCREATE TABLE t (id int);\n' >db/migrations/001.sql
numbered 3 gen >gen/client.js
numbered 3 gen >"gen/é.js"
numbered 3 note >"docs/my notes.md"
printf 'gen/** linguist-generated=true\ndb/** linguist-generated=true\n' >.gitattributes
commit base

git checkout -qb feat
replace_line src/app.js 3 "app changed 3"
replace_line src/app.js 20 "app changed 20"
git mv src/old.js src/new.js
replace_line src/new.js 5 "new 5"
git rm -q src/gone.js
replace_line pnpm-lock.yaml 2 "lock changed"
replace_line db/migrations/001.sql 1 "-- v2"
replace_line gen/client.js 1 "gen changed"
replace_line "gen/é.js" 1 "gen changed"
replace_line "docs/my notes.md" 2 "note changed"
printf '\000\001\002' >img.bin
replace_line src/conflict.js 1 "conflict from feat"
replace_line src/both.js 10 "both from feat"
commit feat

git checkout -q main
replace_line src/conflict.js 1 "conflict from main"
replace_line src/both.js 1 "both from main"
replace_line src/old.js 1 "old from main"
git mv "docs/my notes.md" docs/notes.md
numbered 2 mainonly >src/mainonly.js
commit "main moves"
git checkout -q feat

echo "app 41" >>src/app.js
numbered 3 untracked >src/untracked.js
echo "x" >foo.min.js

out=$(run setup.sh --base main)
expect "setup ok" "$out" "status: ok"
expect "setup sees uncommitted changes" "$out" "uncommitted: yes"
expect "setup counts base movement" "$out" "base_moved: 1 commits since merge-base"
expect "setup names the branch" "$out" "branch: feat ("
run_dir=$(value "$out" run_dir)
expect "setup reports repo_root" "$out" "repo_root: $repo"

touch -t 202501010000 .gitattributes
out=$(run inventory.sh "$run_dir")
expect "inventory ok" "$out" "status: ok"
expect_not "inventory skips files only touched" "$(cat "$run_dir/changed.txt")" ".gitattributes"
expect "inventory totals" "$out" "files: 8 reviewed"
expect "inventory counts untracked" "$out" "2 untracked · 4 excluded"
expect "inventory finds the conflict" "$out" "merge with base: conflicts in src/conflict.js (committed changes only)"
expect "inventory lists both-sides files, including renames on either side" "$out" \
  "changed on both sides: docs/my notes.md, src/both.js, src/conflict.js, src/old.js -> src/new.js"
expect "inventory excludes the lockfile" "$out" "pnpm-lock.yaml  lockfile  +1/-1"
expect "inventory excludes generated files" "$out" "gen/client.js  generated  +1/-1"
expect "inventory excludes generated files with non-ASCII paths" "$out" "gen/é.js  generated  +1/-1"
expect "inventory excludes untracked minified files" "$out" "foo.min.js  minified  +1/-0"
expect "inventory never excludes migrations" "$out" "db/migrations/001.sql  M +1/-1"
expect "inventory numbers three app hunks" "$out" "src/app.js  M +3/-2  H4 1-6  H5 17-23  H6 38-41"
expect "inventory shows renames" "$out" "src/old.js -> src/new.js  R +1/-1"
expect "inventory gives deleted files one id" "$out" "src/gone.js  D +0/-5  H9 (deleted, -5)"
expect "inventory handles paths with spaces" "$out" "docs/my notes.md  M +1/-1"
expect "inventory marks binary files" "$out" "img.bin  binary +0/-0"
expect "inventory numbers untracked files last" "$out" "src/untracked.js  untracked +3  H11 1-3"
expect "inventory hunk total" "$out" "hunks: 11"
expect_not "inventory skips files only the base changed" "$out" "src/mainonly.js  "
expect "hunks.txt lists ids" "$(cat "$run_dir/hunks.txt")" "$(printf 'H9\tsrc/gone.js\t(deleted, -5)')"
expect "base-changed.txt lists base files" "$(cat "$run_dir/base-changed.txt")" "src/mainonly.js"

for setting in diff.mnemonicPrefix=true diff.noprefix=true color.ui=always diff.external=false; do
  git config --global "${setting%%=*}" "${setting#*=}"
  out=$(run inventory.sh "$run_dir")
  expect "inventory reads paths under $setting" "$out" "src/app.js  M +3/-2  H4 1-6  H5 17-23  H6 38-41"
  expect "inventory still excludes under $setting" "$out" "pnpm-lock.yaml  lockfile  +1/-1"
  git config --global --unset "${setting%%=*}"
done

out=$(run inventory.sh "$run_dir" 'src/both*' 'db/*')
expect "context globs exclude files" "$out" "src/both.js  context  +1/-1"
expect_not "context globs never exclude migrations" "$out" "db/migrations/001.sql  context"

# --- reconcile --------------------------------------------------------------------------------------------------

out=$(run inventory.sh "$run_dir")

ledger_rest() { # correct, closed entries for every hunk outside src/app.js (H4-H6) and src/untracked.js (H11)
  cat <<'EOF'
E1 | db/migrations/001.sql | file | H1 | lenses: correctness
E2 | docs/my notes.md | file | H2 | lenses: correctness
E3 | img.bin | file | H3 | lenses: correctness
E5 | src/both.js | file | H7 | lenses: correctness
E6 | src/conflict.js | file | H8 | lenses: correctness
E7 | src/gone.js | file | H9 | lenses: correctness
E8 | src/old.js -> src/new.js | file | H10 | lenses: correctness
closed E1 correctness
closed E2 correctness
closed E3 correctness
closed E5 correctness
closed E6 correctness
closed E7 correctness
closed E8 correctness
EOF
}

{ ledger_rest; cat <<'EOF'
E4 | src/app.js | top | H4,H5 | contract: none | consumers: - | tests: none | lenses: correctness,tests
E9 | src/app.js | tail | H6 | contract: none | consumers: - | tests: none | lenses: correctness,tests,security
E10 | src/app.js | file | H99 | lenses: correctness
closed E4 correctness,tests
closed E9 correctness,tests
closed E99 correctness
EOF
} >"$run_dir/ledger.md"
out=$(run reconcile.sh "$run_dir")
code=$?
expect "reconcile counts" "$out" "hunks: 11 (mapped 10) · entries: 10 (closed 9)"
expect "reconcile lists unmapped hunks" "$out" "unmapped: H11"
expect "reconcile lists open entries" "$out" "open: E10"
expect "reconcile lists missing lenses" "$out" "missing lenses: E9 (security)"
expect "reconcile flags unknown ids and closures without entries" "$out" "unknown: E99 H99"
expect "reconcile incomplete" "$out" "status: incomplete"
[ "$code" -eq 1 ] && passed=$((passed + 1)) || { failed=$((failed + 1)); echo "FAIL: reconcile exits 1 when incomplete"; }

{ ledger_rest; cat <<'EOF'
E4 | src/app.js | H11() | H4,H5,H6 | contract: H99 database | lenses: correctness
closed E4 correctness
EOF
} >"$run_dir/ledger.md"
out=$(run reconcile.sh "$run_dir")
expect "reconcile ignores hunk-like names outside the hunks field" "$out" "unmapped: H11"
expect_not "reconcile ignores hunk-like prose outside the hunks field" "$out" "unknown:"

{ ledger_rest; cat <<'EOF'
E4 | src/app.js | H4,H5,H6 | contract: none | lenses: correctness
E9 | src/untracked.js | file | H11 | lenses: correctness
closed E4 correctness
closed E9 correctness
EOF
} >"$run_dir/ledger.md"
out=$(run reconcile.sh "$run_dir")
expect "reconcile names an entry missing a field" "$out" "no hunk ids in field 4: E4"
expect "reconcile stays incomplete for it" "$out" "status: incomplete"

{ ledger_rest; cat <<'EOF'
E4 | src/app.js | top | H4,H5,H6 | contract: none
E9 | src/untracked.js | file | H11 | lenses: correctness
closed E4
closed E9 correctness
EOF
} >"$run_dir/ledger.md"
out=$(run reconcile.sh "$run_dir")
expect "reconcile names an entry without lenses" "$out" "no lenses: E4"
expect "reconcile stays incomplete without lenses" "$out" "status: incomplete"

{ ledger_rest; cat <<'EOF'
E4 | src/app.js | top | H4,H5,H11 | lenses: correctness
E9 | src/untracked.js | file | H6 | lenses: correctness
closed E4 correctness
closed E9 correctness
EOF
} >"$run_dir/ledger.md"
out=$(run reconcile.sh "$run_dir")
expect "reconcile names hunks filed under another file" "$out" \
  "wrong file: H11 (src/untracked.js) in E4, H6 (src/app.js) in E9"
expect "reconcile stays incomplete for them" "$out" "status: incomplete"

{ ledger_rest; cat <<'EOF'
E4 | src/app.js | top | H4,H5,H6 | lenses: correctness,tests
E9 | src/untracked.js | file | H11 | lenses: correctness
closed E4 correctness,tests
closed E9 correctness
EOF
} >"$run_dir/ledger.md"
out=$(run reconcile.sh "$run_dir")
code=$?
expect "reconcile complete, with a rename filed as old -> new" "$out" "status: reconciled"
[ "$code" -eq 0 ] && passed=$((passed + 1)) || { failed=$((failed + 1)); echo "FAIL: reconcile exits 0 when reconciled"; }

# --- run-checks -------------------------------------------------------------------------------------------------

out=$(run run-checks.sh "$run_dir" 'true' 'echo one; echo two; exit 3' 'no-such-command-xyz' 'true')
expect "run-checks passes" "$out" "status: passed"
expect "run-checks fails" "$out" "status: failed"
expect "run-checks keeps the exit code" "$out" "exit: 3"
expect "run-checks counts log lines" "$out" "-exit-3.log (2 lines)"
expect "run-checks reports missing commands as failures" "$out" "status: failed (command not found or not executable)"
expect "run-checks keeps repeated logs apart" "$out" "true-2.log"
expect_not "run-checks reports no writes from read-only checks" "$out" "modified:"
expect "run-checks leaves the index alone" "$(git status --porcelain)" " M src/app.js"

out=$(run run-checks.sh "$run_dir" 'test "$CI" = true')
expect "run-checks runs commands with CI=true" "$out" "status: passed"

mkdir -p nested && git -C nested init -q
out=$(run run-checks.sh "$run_dir" 'echo formatted >>src/app.js')
rm -rf nested
expect "run-checks says when it cannot snapshot the tree" "$out" \
  "modified: unknown (could not snapshot the tree: error: 'nested/' does not have a commit checked out)"

out=$(run run-checks.sh "$run_dir" 'echo fixed >>src/app.js' 'mkdir -p coverage && echo x >coverage/lcov.info')
expect "run-checks spots a write to an already-modified file" "$out" "modified: src/app.js (what it wrote: git diff-tree -p "
expect "run-checks spots a new untracked file" "$out" "modified: coverage/lcov.info"
written=$(printf '%s\n' "$out" | sed -n 's/^modified: src\/app.js (what it wrote: \(git diff-tree -p [0-9a-f]* [0-9a-f]*\))$/\1/p')
git config --global diff.external false
expect "run-checks prints a diff of what it wrote that ignores diff settings" "$($written)" "+fixed"
git config --global --unset diff.external

# --- each setup gets its own run directory ----------------------------------------------------------------------

out=$(run setup.sh --base main)
second_run_dir=$(value "$out" run_dir)
[ -n "$second_run_dir" ] && [ "$second_run_dir" != "$run_dir" ] && passed=$((passed + 1)) ||
  { failed=$((failed + 1)); echo "FAIL: setup makes a new run directory"; }
[ -e "$run_dir/ledger.md" ] && passed=$((passed + 1)) || { failed=$((failed + 1)); echo "FAIL: setup leaves an earlier run alone"; }
expect "run directory is private" "$(ls -ld "$second_run_dir")" "drwx------"

# --- inventory: files with no hunks -----------------------------------------------------------------------------

repo="$sandbox/nohunks"
mkdir -p "$repo" && cd "$repo" && git init -q || exit 2
numbered 3 plain >plain.txt
numbered 2 tool >tool.sh
commit base
git checkout -qb feat
git mv plain.txt renamed.txt
: >empty.txt
chmod +x tool.sh
commit feat

out=$(run setup.sh --base main)
out=$(run inventory.sh "$(value "$out" run_dir)")
expect "inventory gives empty new files one id" "$out" "empty.txt  A +0/-0  H1 (new, empty)"
expect "inventory gives pure renames one id" "$out" "plain.txt -> renamed.txt  R +0/-0  H2 (renamed, content unchanged)"
expect "inventory gives mode changes one id" "$out" "tool.sh  M +0/-0  H3 (mode change)"

echo new >untracked.txt
git config --global status.showUntrackedFiles no
out=$(run setup.sh --base main)
git config --global --unset status.showUntrackedFiles
rm untracked.txt
expect "setup counts untracked files as uncommitted under status.showUntrackedFiles=no" "$out" "uncommitted: yes"

for name in a_first.txt k=v.txt -dash.txt z_last.txt; do numbered 2 line >"./$name"; done
out=$(run setup.sh --base main)
out=$(run inventory.sh "$(value "$out" run_dir)")
rm -f ./a_first.txt ./k=v.txt ./-dash.txt ./z_last.txt
expect "inventory counts untracked files whatever their names" "$out" "4 untracked"
expect "inventory reads an untracked file named like an option" "$out" "-dash.txt  untracked +2  H4 1-2"
expect "inventory reads an untracked file named like an assignment" "$out" "k=v.txt  untracked +2  H6 1-2"
expect "inventory keeps the untracked files after it" "$out" "z_last.txt  untracked +2  H7 1-2"

# --- inventory: submodules -------------------------------------------------------------------------------------

mkdir -p "$sandbox/libsrc" && cd "$sandbox/libsrc" && git init -q || exit 2
echo lib >lib.txt
commit lib
repo="$sandbox/withsub"
mkdir -p "$repo" && cd "$repo" && git init -q || exit 2
numbered 3 line >a.txt
git -c protocol.file.allow=always submodule add -q "$sandbox/libsrc" lib >/dev/null 2>&1 || exit 2
commit base
git checkout -qb feat
replace_line a.txt 2 "line changed"
(cd lib && echo more >>lib.txt && git commit -qam more)
commit feat

for format in log diff; do
  git config --global diff.submodule "$format"
  out=$(run setup.sh --base main)
  out=$(run inventory.sh "$(value "$out" run_dir)")
  expect "inventory gives a submodule change one id under diff.submodule=$format" "$out" "lib  M +1/-1  H2 1"
  expect_not "inventory keeps submodule files out under diff.submodule=$format" "$out" "lib/lib.txt"
  git config --global --unset diff.submodule
done

git checkout -q main
git checkout -qb bump
(cd lib && echo again >>lib.txt && git commit -qam again)
commit bump
git config --global diff.ignoreSubmodules all
out=$(run setup.sh --base main)
git config --global --unset diff.ignoreSubmodules
expect "setup sees a submodule-only change under diff.ignoreSubmodules=all" "$out" "status: ok"

echo
echo "bash $BASH_VERSION: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
