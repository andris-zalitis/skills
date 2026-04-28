#!/usr/bin/env bash
# One-shot watcher. No CLI arguments.
# Direct use is Claude's watcher. watch-loop.sh calls this same script
# with DUO_WATCH_AGENT=codex internally.
# Emits one line and exits:
#   READY-<AGENT>: <signal-line>
#   LOCK-<AGENT>-CLAIMED
#   STALE-LOCK: <lock-json>
#   TIMEOUT

set -euo pipefail

agent="${DUO_WATCH_AGENT:-claude}"
agent_upper=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')
deadline_seconds="${DUO_DEADLINE:-900}"
poll_interval="${DUO_POLL_INTERVAL:-3}"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
workspace="$repo_root/.duo/workspace"
signal_file="$workspace/signal.jsonl"
lock_file="$workspace/lock.json"

if [ ! -f "$signal_file" ]; then
  echo "ERROR: $signal_file does not exist" >&2
  exit 1
fi

deadline=$(( $(date +%s) + deadline_seconds ))

json_string_field_from_file() {
  local file="$1"
  local field="$2"
  sed -nE "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\\1/p" "$file" | head -n 1
}

json_string_field_from_text() {
  local text="$1"
  local field="$2"
  printf '%s' "$text" | sed -nE "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\\1/p" | head -n 1
}

epoch_from_utc() {
  local value="$1"
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$value" +%s 2>/dev/null ||
    date -u -d "$value" +%s 2>/dev/null
}

while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -f "$lock_file" ]; then
    owner="$(json_string_field_from_file "$lock_file" owner || true)"
    if [ "$owner" = "$agent" ]; then
      printf 'LOCK-%s-CLAIMED\n' "$agent_upper"
      exit 0
    fi

    expires_at="$(json_string_field_from_file "$lock_file" expiresAt || true)"
    if [ -n "$expires_at" ]; then
      expires_epoch="$(epoch_from_utc "$expires_at" || true)"
      now_epoch="$(date -u +%s)"
      if [ -n "$expires_epoch" ] && [ "$expires_epoch" -le "$now_epoch" ]; then
        printf 'STALE-LOCK: %s\n' "$(tr -d '\n' < "$lock_file")"
        exit 0
      fi
    fi
  fi

  latest=$(tail -n 1 "$signal_file" 2>/dev/null || true)
  next="$(json_string_field_from_text "$latest" next || true)"
  if [ "$next" = "$agent" ] && [ ! -f "$lock_file" ]; then
    printf 'READY-%s: %s\n' "$agent_upper" "$latest"
    exit 0
  fi

  sleep "$poll_interval"
done

printf 'TIMEOUT\n'
exit 0
