#!/usr/bin/env bash
# Reconcile the ledger against the inventory: every hunk mapped to an entry, every entry closed with all of
# its lenses.
#
# Usage: reconcile.sh <run_dir>
#
# Ledger (<run_dir>/ledger.md):
#   entry line:   E3 | <file> | <unit> | H1,H2 | ... | lenses: correctness,errors,tests
#   closure line: closed E3 correctness,errors,tests
# Hunk ids are read from the fourth field only, and each must belong to the file in the second, or to `new` when the
# second field is a rename's `old -> new`.
# Exits 0 and prints `status: reconciled` only when nothing is unmapped, open, missing, unknown, or in the wrong file,
# and every entry has hunk ids and lenses.

set -u
here=$(cd "$(dirname "$0")" && pwd -P)
. "$here/lib.sh"

run_dir=${1-}
load_env "$run_dir"
[ -f "$run_dir/hunks.txt" ] || die "no inventory in $run_dir; run inventory.sh first"
[ -f "$run_dir/ledger.md" ] || die "no ledger at $run_dir/ledger.md"

awk '
  function words(s, out,   t, i, k, n) {
    gsub(/[^A-Za-z0-9_]+/, " ", s)
    n = split(s, t, " "); k = 0
    for (i = 1; i <= n; i++) out[++k] = t[i]
    return k
  }
  function names_path(file, path) {
    return file == path || substr(file, length(file) - length(path) - 3) == " -> " path
  }
  FILENAME == ARGV[1] { split($0, f, "\t"); known[f[1]] = 1; hpath[f[1]] = f[2]; horder[++nh] = f[1]; next }
  /^[ \t]*E[0-9]+[ \t]*\|/ {
    line = $0; sub(/^[ \t]*/, "", line)
    match(line, /^E[0-9]+/); e = substr(line, 1, RLENGTH)
    if (!(e in entries)) { entries[e] = 1; eorder[++ne] = e }
    lens = ""
    if ((p = index(line, "lenses:")) > 0) { lens = substr(line, p + 7); sub(/\|.*/, "", lens); line = substr(line, 1, p - 1) }
    split(line, f, "|"); file = f[2]; gsub(/^[ \t]+|[ \t]+$/, "", file)
    k = words(f[4], w); found = 0
    for (i = 1; i <= k; i++) {
      h = w[i]
      if (h !~ /^H[0-9]+$/) continue
      found = 1; mapped[h] = 1
      if (!(h in known)) unknown[h] = 1
      else if (!names_path(file, hpath[h])) wf = wf (wf ? ", " : " ") h " (" hpath[h] ") in " e
    }
    if (!found) nohunks = nohunks " " e
    k = words(lens, w)
    if (k == 0) nolenses = nolenses " " e
    for (i = 1; i <= k; i++) need[e, w[i]] = 1
    next
  }
  /^[ \t]*closed[ \t]+E[0-9]+/ {
    k = words($0, w); e = w[2]; closed[e] = 1
    for (i = 3; i <= k; i++) done[e, w[i]] = 1
    next
  }
  END {
    for (i = 1; i <= nh; i++) { if (horder[i] in mapped) nm++; else um = um " " horder[i] }
    for (i = 1; i <= ne; i++) {
      e = eorder[i]
      if (!(e in closed)) { op = op " " e; continue }
      nc++; miss = ""
      for (key in need) { split(key, kk, SUBSEP); if (kk[1] == e && !((e, kk[2]) in done)) miss = miss (miss ? "," : "") kk[2] }
      if (miss != "") ml = ml " " e " (" miss ")"
    }
    for (e in closed) if (!(e in entries)) uk = uk " " e
    for (h in unknown) uk = uk " " h
    printf "hunks: %d (mapped %d) · entries: %d (closed %d)\n", nh, nm, ne, nc
    if (um != "") print "unmapped:" um
    if (op != "") print "open:" op
    if (ml != "") print "missing lenses:" ml
    if (uk != "") print "unknown:" uk
    if (nohunks != "") print "no hunk ids in field 4:" nohunks
    if (nolenses != "") print "no lenses:" nolenses
    if (wf != "") print "wrong file:" wf
    ok = ((ne > 0 || nh == 0) && um == "" && op == "" && ml == "" && uk == "" && nohunks == "" && nolenses == "" &&
      wf == "")
    print "status: " (ok ? "reconciled" : "incomplete")
    exit(ok ? 0 : 1)
  }
' "$run_dir/hunks.txt" "$run_dir/ledger.md"
