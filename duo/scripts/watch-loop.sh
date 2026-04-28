#!/usr/bin/env bash
# Blocking watcher loop for Codex. No arguments.
# Calls watch.sh and re-runs it on TIMEOUT. Exits only when the watch
# resolves to Codex's turn/lock/stale-lock, or on an error.

set -eu

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
watch="$script_dir/watch.sh"

if [ ! -x "$watch" ] && [ ! -f "$watch" ]; then
  echo "WATCHER-ERROR: $watch not found" >&2
  exit 1
fi

while true; do
  if ! result=$(DUO_WATCH_AGENT=codex bash "$watch" 2>&1); then
    printf 'WATCHER-ERROR: %s\n' "$result"
    exit 1
  fi

  case "$result" in
    READY-CODEX*|LOCK-CODEX-CLAIMED|STALE-LOCK*)
      printf '%s\n' "$result"
      exit 0
      ;;
    TIMEOUT)
      continue
      ;;
    *)
      printf 'WATCHER-UNEXPECTED: %s\n' "$result"
      exit 1
      ;;
  esac
done
