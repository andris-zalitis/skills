#!/usr/bin/env bash
# Atomic lock acquisition for a duo iteration.
#
# Usage:   .duo/scripts/lock.sh <owner-nickname> <handoff-filename>
# Example: .duo/scripts/lock.sh claude 0003-claude.md
#
# Exits 0 on lock acquired (prints the new lock.json to stdout).
# Exits 1 if another agent already holds the lock (prints existing
# lock contents to stderr so the caller sees who owns it).
#
# Run from the repo root — paths are relative to .duo/workspace/.

set -eu

owner="${1:?owner nickname required}"
handoff="${2:?handoff filename required}"

startedAt="$(date -u +%FT%TZ)"
if expiresAt="$(date -u -v+6H +%FT%TZ 2>/dev/null)"; then
  :
else
  expiresAt="$(date -u -d '+6 hours' +%FT%TZ)"
fi

mkdir -p .duo/workspace/handoffs .duo/workspace/stale-locks
lock=".duo/workspace/lock.json"

# Atomic create-or-fail via noclobber (`set -C`). The subshell scopes
# the option locally; 2>/dev/null suppresses bash's own "cannot
# overwrite" message so we can emit our own clearer one below.
if (set -C; printf '{"owner":"%s","startedAt":"%s","expiresAt":"%s","handoff":"handoffs/%s"}\n' \
      "$owner" "$startedAt" "$expiresAt" "$handoff" > "$lock") 2>/dev/null; then
  cat "$lock"
  exit 0
fi

echo "ERROR: lock.json already exists — another agent holds the turn." >&2
echo "Existing lock contents:" >&2
cat "$lock" >&2 || true
exit 1
