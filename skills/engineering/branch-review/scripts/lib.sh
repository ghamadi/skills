# Shared helpers for the branch-review scripts. Sourced, not executed.
# Written for bash 3.2 (macOS /bin/bash) and BSD userland.

die() {
  echo "status: error"
  echo "error: $*"
  exit 1
}

# Load the values setup.sh recorded for this run (repo_root, merge_base, ...).
load_env() {
  if [ -z "${1-}" ] || [ ! -f "$1/env" ]; then
    die "no run directory at '${1-}'; run setup.sh first"
  fi
  . "$1/env"
}

put_env() {
  printf '%s=%q\n' "$1" "$2" >>"$run_dir/env"
}
