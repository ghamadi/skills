#!/usr/bin/env bash
# List what the branch changed: files with numbered hunks, excluded files, merge conflicts with the base, and
# files changed on both sides since the merge-base.
#
# Usage: inventory.sh <run_dir> [<exclude-glob> ...]
#
# Exclude globs come from the review's context; `*` matches across directories. Migrations are never excluded.
# Writes <run_dir>/hunks.txt (id, path, range) for reconcile.sh and <run_dir>/base-changed.txt.

set -u
here=$(cd "$(dirname "$0")" && pwd -P)
. "$here/lib.sh"

run_dir=${1-}
load_env "$run_dir"
shift
cd "$repo_root" || die "cannot enter $repo_root"

# The working tree against the merge-base, so uncommitted changes count. Plumbing rather than `git diff`, so the
# user's diff settings (prefixes, colour, submodule format, textconv, rename detection, external tools) cannot change
# what is parsed. Plumbing does not refresh stale file timestamps the way `git diff` does, so the index is refreshed
# first.
branch_diff() {
  git -c core.quotePath=false diff-index -M "$@" "$merge_base"
}
git update-index -q --refresh >/dev/null 2>&1

changed="$run_dir/changed.txt"
untracked="$run_dir/untracked.txt"
generated="$run_dir/generated.txt"
excluded="$run_dir/excluded.txt"
hunks="$run_dir/hunks.txt"
rows="$run_dir/rows.txt"
excluded_rows="$run_dir/excluded-rows.txt"
renames="$run_dir/renames.txt"

branch_diff --name-only >"$changed" || die "git diff failed"
branch_diff --name-status | awk -F '\t' '$1 ~ /^R/ { print $2 "\t" $3 }' >"$renames"
git -c core.quotePath=false ls-files --others --exclude-standard >"$untracked"
cat "$changed" "$untracked" | git -c core.quotePath=false check-attr --stdin linguist-generated |
  sed -nE 's/: linguist-generated: (set|true)$//p' >"$generated"

# Print why <path> is excluded from reading, or fail when it is reviewed. Remaining args are context globs.
exclusion_reason() {
  local p=$1 lc glob
  shift
  lc=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    *migrat* | *alembic/*) return 1 ;;
  esac
  case "${p##*/}" in
    pnpm-lock.yaml | package-lock.json | npm-shrinkwrap.json | yarn.lock | bun.lock | bun.lockb | deno.lock | \
      Cargo.lock | poetry.lock | uv.lock | Pipfile.lock | Gemfile.lock | composer.lock | go.sum | flake.lock | \
      mix.lock | pubspec.lock | Podfile.lock | packages.lock.json | gradle.lockfile)
      echo "lockfile"; return 0 ;;
    *.snap) echo "snapshot"; return 0 ;;
    *.min.js | *.min.mjs | *.min.css) echo "minified"; return 0 ;;
    *.js.map | *.mjs.map | *.css.map) echo "source map"; return 0 ;;
  esac
  case "/$p" in
    */__snapshots__/*) echo "snapshot"; return 0 ;;
    */dist/*) echo "build output"; return 0 ;;
  esac
  if grep -Fxq -- "$p" "$generated"; then
    echo "generated"; return 0
  fi
  for glob in "$@"; do
    if [[ $p == $glob ]]; then
      echo "context"; return 0
    fi
  done
  return 1
}

: >"$excluded"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if reason=$(exclusion_reason "$p" "$@"); then
    printf '%s\t%s\n' "$p" "$reason" >>"$excluded"
  fi
done < <(cat "$changed" "$untracked")

# Number the hunks of every reviewed tracked file and count lines per file. Files without hunks (binary,
# pure rename, mode change, empty) get one id; a deleted file gets one id for the whole file.
totals=$(branch_diff -p |
  awk -v excl="$excluded" -v hunks="$hunks" -v rows="$rows" -v exrows="$excluded_rows" '
    BEGIN {
      while ((getline line < excl) > 0) { split(line, f, "\t"); ex[f[1]] = f[2] }
      close(excl)
      printf "" > hunks; printf "" > rows; printf "" > exrows
      id = 0
    }
    function new_id(range) {
      id++
      printf "H%d\t%s\t%s\n", id, path, range >> hunks
      return sprintf("H%d %s", id, range)
    }
    function flush(   name, ids) {
      if (path == "") return
      name = (old != "" && old != path) ? old " -> " path : path
      if (path in ex) {
        printf "  %s  %s  +%d/-%d\n", name, ex[path], add, del >> exrows
        nex++
      } else {
        ids = hl
        if (status == "D") ids = new_id(sprintf("(deleted, -%d)", del))
        else if (nh == 0 && binary) ids = new_id("(binary)")
        else if (nh == 0 && status == "R") ids = new_id("(renamed, content unchanged)")
        else if (nh == 0 && status == "A") ids = new_id("(new, empty)")
        else if (nh == 0) ids = new_id("(mode change)")
        printf "  %s  %s +%d/-%d  %s\n", name, (binary ? "binary" : status), add, del, ids >> rows
        nfiles++; tadd += add; tdel += del
      }
      path = ""
    }
    /^diff --git / {
      flush()
      s = substr($0, 12); half = int((length(s) - 1) / 2)
      a = substr(s, 1, half); b = substr(s, half + 2)
      path = (substr(a, 1, 2) == "a/" && substr(b, 1, 2) == "b/" && substr(a, 3) == substr(b, 3)) ? substr(b, 3) : "?"
      old = ""; status = "M"; binary = 0; add = 0; del = 0; nh = 0; hl = ""; inhunk = 0
      next
    }
    !inhunk && /^new file mode/ { status = "A"; next }
    !inhunk && /^deleted file mode/ { status = "D"; next }
    !inhunk && /^rename from / { old = substr($0, 13); status = "R"; next }
    !inhunk && /^rename to / { path = substr($0, 11); next }
    !inhunk && /^Binary files / { binary = 1; next }
    !inhunk && /^--- a\// { if (path == "?") path = substr($0, 7); next }
    !inhunk && /^\+\+\+ b\// { if (path == "?") path = substr($0, 7); next }
    /^@@ / {
      inhunk = 1
      match($0, /-[0-9]+(,[0-9]+)?/); split(substr($0, RSTART + 1, RLENGTH - 1), o, ",")
      match($0, /\+[0-9]+(,[0-9]+)?/); split(substr($0, RSTART + 1, RLENGTH - 1), n, ",")
      ob = (o[2] == "") ? 1 : o[2] + 0
      c = n[1] + 0; d = (n[2] == "") ? 1 : n[2] + 0
      if (status == "D" || (path in ex)) next
      if (d == 0) r = sprintf("%d (-%d)", c, ob)
      else if (d == 1) r = sprintf("%d", c)
      else r = sprintf("%d-%d", c, c + d - 1)
      hl = hl (nh ? "  " : "") new_id(r)
      nh++
      next
    }
    inhunk && /^\+/ { add++; next }
    inhunk && /^-/ { del++; next }
    END { flush(); printf "%d %d %d %d\n", nfiles, tadd, tdel, nex }
  ')
read -r nfiles tadd tdel nex <<EOF
$totals
EOF

nuntracked=0
next_id=$(awk 'END { print NR }' "$hunks")
# Files are read by redirect: as an operand, a name like `k=v.txt` is an awk assignment and `-x.txt` a grep option.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  nuntracked=$((nuntracked + 1))
  lines=0
  [ -f "$p" ] && lines=$(awk 'END { print NR }' <"$p")
  reason=$(awk -F '\t' -v p="$p" '$1 == p { print $2; exit }' "$excluded")
  if [ -n "$reason" ]; then
    printf '  %s  %s  +%d/-0\n' "$p" "$reason" "$lines" >>"$excluded_rows"
    nex=$((nex + 1))
    continue
  fi
  next_id=$((next_id + 1))
  if [ -s "$p" ] && ! grep -Iq . <"$p" 2>/dev/null; then
    r="(binary)"
  elif [ "$lines" -eq 0 ]; then
    r="(new, empty)"
  elif [ "$lines" -eq 1 ]; then
    r="1"
  else
    r="1-$lines"
  fi
  printf 'H%d\t%s\t%s\n' "$next_id" "$p" "$r" >>"$hunks"
  printf '  %s  untracked +%d  H%d %s\n' "$p" "$lines" "$next_id" "$r" >>"$rows"
done <"$untracked"

base_moved=$(git -C "$repo_root" rev-list --count "$merge_base..$base_sha")
git -C "$repo_root" -c core.quotePath=false diff-tree -r --name-only "$merge_base" "$base_sha" >"$run_dir/base-changed.txt"

if [ "$base_moved" -eq 0 ]; then
  merge="clean (base has not moved)"
else
  out=$(git -C "$repo_root" -c core.quotePath=false merge-tree --write-tree --name-only --no-messages "$base_sha" "$head_sha" 2>&1)
  case $? in
    0) merge="clean" ;;
    1) merge="conflicts in $(printf '%s\n' "$out" | sed '1d' | sed '/^$/,$d' | paste -sd ',' - | sed 's/,/, /g')" ;;
    *) merge="could not check ($(printf '%s\n' "$out" | head -n 1))" ;;
  esac
  if [ "$uncommitted" = "yes" ]; then
    merge="$merge (committed changes only)"
  fi
fi

echo "status: ok"
echo "files: $nfiles reviewed (+$tadd/-$tdel) · $nuntracked untracked · $nex excluded"
echo "merge with base: $merge"
if [ "$base_moved" -gt 0 ]; then
  nbase=$(awk 'END { print NR }' "$run_dir/base-changed.txt")
  both=$({
    cat "$changed" "$untracked" | grep -Fx -f "$run_dir/base-changed.txt"
    awk -F '\t' 'NR == FNR { base[$0] = 1; next } $1 in base { print $1 " -> " $2 }' "$run_dir/base-changed.txt" "$renames"
  } | sort -u | paste -sd ',' - | sed 's/,/, /g')
  echo "base moved: $base_moved commits since merge-base, $nbase files changed there (list: $run_dir/base-changed.txt)"
  echo "changed on both sides: ${both:-none}"
fi
if [ -s "$excluded_rows" ]; then
  echo "excluded (not read):"
  cat "$excluded_rows"
fi
echo "hunks: $(awk 'END { print NR }' "$hunks") (ids in $hunks)"
cat "$rows"
exit 0
