#!/usr/bin/env bash
# duo setup — idempotent. Creates .duo/ infrastructure under the
# given repo root only if files don't already exist, then installs a
# small AGENTS.md / CLAUDE.md bootstrap block if missing. Never clobbers.
#
# Layout created:
#
#   .duo/                            # tracked
#     .gitignore                    # ignores workspace/ entirely
#     README.md
#     agents/<nickname>.md          # one per available agent template
#     scripts/*.sh                 # watcher/lock helpers
#     migrations/.keep
#     workspace/                    # UNTRACKED (gitignored)
#       state.json                  # initial; agent fills via dialog
#       signal.jsonl                # empty
#       <project>.md                # NOT created here — agent's job
#       handoffs/                   # empty
#       stale-locks/                # empty
#       assets/                     # empty
#
# Usage: bash setup.sh <repo-root>

set -euo pipefail

repo_root="${1:?repo root required}"

if [ ! -d "$repo_root" ]; then
  echo "ERROR: repo root '$repo_root' is not a directory" >&2
  exit 1
fi

# Locate this skill's templates/ relative to this script.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"
templates="$skill_dir/templates"

if [ ! -d "$templates" ]; then
  echo "ERROR: templates dir not found at $templates" >&2
  exit 1
fi

duo="$repo_root/.duo"
workspace="$duo/workspace"

# Top-level static dirs + workspace dirs.
mkdir -p \
  "$duo/agents" \
  "$duo/scripts" \
  "$duo/migrations" \
  "$workspace/handoffs" \
  "$workspace/stale-locks" \
  "$workspace/assets"

# .keep files for empty tracked dirs (so the empty layout survives a
# fresh clone). workspace/ is gitignored as a whole, and archive/ is
# created by /duo stop when there is a real project to archive.
for d in \
  "$duo/migrations"
do
  if [ ! -f "$d/.keep" ] && [ -z "$(ls -A "$d" 2>/dev/null)" ]; then
    : > "$d/.keep"
  fi
done

# Empty signal.jsonl in workspace.
if [ ! -f "$workspace/signal.jsonl" ]; then
  : > "$workspace/signal.jsonl"
fi

# Initial state.json in workspace.
if [ ! -f "$workspace/state.json" ]; then
  cat > "$workspace/state.json" <<'JSON'
{
  "schemaVersion": 1,
  "currentProject": null,
  "currentMilestone": null,
  "participants": null,
  "currentTurn": null,
  "lastHandoff": null,
  "phase": null,
  "setupBy": null,
  "testState": null
}
JSON
fi

copy_if_missing() {
  local src="$1"
  local dst="$2"
  if [ ! -f "$dst" ]; then
    cp "$src" "$dst"
  fi
}

# Top-level static files.
copy_if_missing "$templates/README.md"   "$duo/README.md"
copy_if_missing "$templates/gitignore"   "$duo/.gitignore"

# Repository bootstrap: make future sessions enter the durable runtime
# protocol in .duo/README.md. This is intentionally tiny; the protocol
# itself lives under .duo/. Install it in both common repo instruction
# entry points without migrating or overwriting existing content.
bootstrap_begin="<!-- DUO-BOOTSTRAP:BEGIN -->"
bootstrap_end="<!-- DUO-BOOTSTRAP:END -->"
bootstrap_line='If `.duo/README.md` exists, read it before coordination-sensitive work and after compaction/resume. Then read your product-specific file: `.duo/agents/<your-nickname>.md` (`codex.md` for Codex, `claude.md` for Claude). Follow both.'

install_bootstrap() {
  local file="$1"
  if [ ! -f "$file" ]; then
    printf '%s\n%s\n%s\n' "$bootstrap_begin" "$bootstrap_line" "$bootstrap_end" > "$file"
  elif ! grep -q "$bootstrap_begin" "$file"; then
    local tmp="$file.duo-tmp"
    {
      printf '%s\n%s\n%s\n\n' "$bootstrap_begin" "$bootstrap_line" "$bootstrap_end"
      cat "$file"
    } > "$tmp"
    mv "$tmp" "$file"
  fi
}

install_bootstrap "$repo_root/AGENTS.md"
install_bootstrap "$repo_root/CLAUDE.md"

# Per-agent files: copy every agent template that ships with the skill.
# Unused ones are harmless and ready for when a third product joins.
shopt -s nullglob
for agent_template in "$templates/agents"/*.md; do
  name="$(basename "$agent_template")"
  copy_if_missing "$agent_template" "$duo/agents/$name"
done
shopt -u nullglob

# Runtime scripts — copy every *.sh from the skill's scripts dir into
# .duo/scripts/, except this setup.sh itself. Idempotent: never
# overwrites. Future scripts get picked up automatically.
shopt -s nullglob
for script_src in "$skill_dir/scripts"/*.sh; do
  name="$(basename "$script_src")"
  if [ "$name" = "setup.sh" ]; then
    continue
  fi
  dst="$duo/scripts/$name"
  if [ ! -f "$dst" ]; then
    cp "$script_src" "$dst"
    chmod +x "$dst"
  fi
done
shopt -u nullglob

# Optional dependency check — node only required for schema migrations.
if ! command -v node >/dev/null 2>&1; then
  echo "WARN: 'node' is not on PATH. Required only for schema migrations." >&2
fi

# Print the .duo path on success (machine-readable).
echo "$duo"
