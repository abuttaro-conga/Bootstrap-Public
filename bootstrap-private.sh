#!/usr/bin/env sh
# bootstrap-private.sh — generic private repo clone dispatcher
#
# Clones a private repository (or pulls if already cloned) and executes
# a named script inside it. Accepts extra arguments after -- that are
# forwarded to the target script.
#
# Usage:
#   sh bootstrap-private.sh --repo <ssh-url> --dest <parent-dir> --run <script> [-- extra args...]
#
# Example one-liner:
#   curl -fsSL https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap-private.sh \
#     | sh -s -- --repo git@github.com:congaengr/Bootstrap-Private.git \
#                --dest ~/src/github/congaengr \
#                --run bootstrap.sh

set -eu

say() {
  printf '%s\n' "$*"
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

repo_url=""
dest_dir=""
run_script=""
extra_args=""
past_sep=0

while [ $# -gt 0 ]; do
  if [ "$past_sep" -eq 1 ]; then
    extra_args="$extra_args $1"
    shift
    continue
  fi
  case "$1" in
    --repo)
      repo_url="$2"
      shift 2
      ;;
    --dest)
      dest_dir="$2"
      shift 2
      ;;
    --run)
      run_script="$2"
      shift 2
      ;;
    --)
      past_sep=1
      shift
      ;;
    -h|--help)
      say "Usage: clone-and-run.sh --repo <ssh-url> --dest <parent-dir> --run <script> [-- extra args...]"
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[ -n "$repo_url" ]   || fail "error: --repo is required"
[ -n "$dest_dir" ]   || fail "error: --dest is required"
[ -n "$run_script" ] || fail "error: --run is required"

case "$run_script" in
  *..*)  fail "error: --run must be a relative path with no '..'"
         ;;
esac

repo_name=$(basename "$repo_url" .git)
clone_target="$dest_dir/$repo_name"

mkdir -p "$dest_dir"

if [ -d "$clone_target/.git" ]; then
  say "Updating $clone_target"
  git -C "$clone_target" pull --ff-only
else
  say "Cloning $repo_url"
  git clone "$repo_url" "$clone_target"
fi

target_script="$clone_target/$run_script"
[ -f "$target_script" ] || fail "error: script not found: $target_script"

# shellcheck disable=SC2086
exec "$target_script" $extra_args
