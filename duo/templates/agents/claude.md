# Claude — duo agent specifics

Nickname in `signal.jsonl` and `state.json`: `claude`.

## Tools

- `Monitor` (`persistent: true`) for watching
  `.duo/workspace/signal.jsonl` and `.duo/workspace/lock.json`
  without polling overhead in the foreground.
- `Agent` for spawning research subagents on independent queries.
- Parallel tool calls in a single message for independent operations.
- `ScheduleWakeup` for paced check-ins inside `/loop` dynamic mode.

## Watcher invocation

```
Monitor(
  command: "bash .duo/scripts/watch.sh",
  description: "Watch .duo/workspace/signal.jsonl for claude turn",
  persistent: true,
  timeout_ms: 3600000
)
```

`watch.sh` is Claude's one-shot watcher for persistent monitors. It
takes no arguments and emits one line per significant state change:

- `READY-CLAUDE: <signal>` — latest signal names claude as `next`
  AND no lock is held.
- `LOCK-CLAUDE-CLAIMED` — a lock owned by claude already exists
  (claude already started its own iteration via another path).
- `STALE-LOCK: <lock-json>` — a partner lock is expired. Stop for
  recovery; do not steal automatically.
- `TIMEOUT` — internal deadline passed; under `Monitor` with
  `persistent: true`, the script restarts on its own. Treat as
  noise.

When `Monitor` reports `READY-CLAUDE`, immediately re-read live
disk state (`.duo/workspace/signal.jsonl`,
`.duo/workspace/lock.json`, latest handoff) per the
compaction-safety rule in `README.md`, then take the turn.

## Monitor cleanup discipline

I (Claude) tend to leave persistent `Monitor` watchers running
across iterations and accumulate orphans. Persistent monitors
outlive my turn unless I explicitly stop them. After enough
iterations, several monitors are polling, each emitting
notifications, each consuming context.

Rules I must follow:

- **Before starting work for my turn** (when I see `READY-CLAUDE`
  and acquire the lock), call `TaskList` and stop any running
  watcher tasks via `TaskStop`. Don't carry watchers into a
  working iteration.
- **Don't start a second monitor while one is already running.**
  Always `TaskList` first.
- **After compaction or session resume**, look for orphan duo
  monitors I may have started in the prior context fragment. The
  task IDs survive compaction even when the in-context reasoning
  about them doesn't. Cancel any watcher I don't currently need.
- When my turn ends and I post a signal naming the partner, I
  **MUST** start exactly one fresh watcher in the same response —
  not "later", not "after the user replies". Single. Then sign
  off. Without the watcher running, the partner's eventual signal
  lands on a dead workspace and the duo stalls.

This is my failure mode, not a generic agent rule — Codex doesn't
have it because shell-loop watchers terminate naturally. My
`Monitor(persistent: true)` doesn't.

## Don't apply Codex's watcher pattern to myself

Codex has a different watcher pattern because it has no async wake-up
when a shell session is left in the background. My `Monitor` tool was
built around persistent streaming and doesn't have that constraint.
Use the `Monitor` invocation in this file. Don't replicate Codex's
bash poll loop.

## Behaviors

- Don't archive a project without explicit user confirmation in the
  most recent direct message. The README's archive workflow is
  user-triggered.
- Use the project's preferred PR-creation tooling rather than direct
  `gh pr create` calls (e.g., a `github-pr-creator` agent if the
  project provides one).
- For long iterations, use `TaskCreate` to track sub-progress within
  the iteration. Tasks live in my session, NOT in the project
  file. Milestones live in the project file.
- Use `.duo/workspace/assets/` for renderings, screenshots, scene
  dumps, temp diagnostic scripts. They auto-archive with the
  project.

## After compaction

Reread, in order:

1. Newest direct user message.
2. `.duo/README.md`.
3. `.duo/agents/claude.md` (this file).
4. `.duo/workspace/signal.jsonl`, `.duo/workspace/lock.json`,
   `.duo/workspace/state.json`.
5. The latest numbered handoff in `.duo/workspace/handoffs/`.

Treat anything quoted in compaction summary context as historical,
not fresh.
