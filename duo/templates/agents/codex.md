# Codex — duo agent specifics

Nickname in `signal.jsonl` and `state.json`: `codex`.

## Tools

- Bash shell with persistent working directory between calls.
- No equivalent of Claude's `Monitor` persistent mode. Wait via
  foreground shell invocation of `watch-loop.sh`, then explicit
  polling of the returned shell session until it resolves.

## Watcher invocation

```bash
bash .duo/scripts/watch-loop.sh
```

That's it. **One command — do not write your own outer loop.**
`watch-loop.sh` handles the TIMEOUT-restart cycle internally so it
cannot be transcribed wrong, and only exits when the watch actually
resolves.

### Foreground only — never background the watcher

Codex has no async wake-up when a background process exits. If
you launch the watcher in a background terminal and end your
turn, the watcher *will* eventually print `READY-CODEX` and
exit — and nobody will be there to read it. The partner's handoff
gets stranded and the duo stalls.

Rules:

- Run `watch-loop.sh` in the **foreground**, as a regular blocking
  shell tool call. Not in a background terminal, not detached,
  not with `&`.
- **Do not end your turn while the watcher is running.** Keep the
  call in flight until it returns one of the exit lines below.
- If the shell tool returns a session id while `watch-loop.sh` is
  still running, treat that session id as an unresolved foreground
  obligation. Poll the same session with empty input until it exits.
  A live session id is not "watching handled"; it is active work you
  must keep monitoring.
- Poll that session quietly with long waits (10-15 minutes, or the
  longest safe tool wait). Do not send progress messages like "still
  waiting", "no handoff yet", or "watcher is still running". The
  tool UI can show the pending shell session; user-facing chat is for
  resolution, errors, or direct user questions.
- If your runtime kills the foreground call (no-output timeout or
  absolute time limit), the only correct response is to
  immediately re-invoke the same one-line command. Don't sign off,
  don't switch to "I'll check later" — relaunch and keep waiting.
- Once the call returns, act on the line: take the turn on
  `READY-CODEX`, pause for recovery on `STALE-LOCK`, investigate
  on errors.

### Exit lines

It exits 0 with one of:

- `READY-CODEX: <signal>` — latest signal names codex as `next`
  AND no lock is held. Take the turn.
- `LOCK-CODEX-CLAIMED` — a lock owned by codex already exists.
- `STALE-LOCK: <lock-json>` — a partner lock is expired. Stop for
  recovery; do not steal automatically.

It exits 1 on `WATCHER-ERROR` or `WATCHER-UNEXPECTED` — don't spin
silently, investigate.

Do not improvise an inline poll loop in case statements. One prior
inline loop swallowed `READY-CODEX` by using an empty `READY` case,
then stranded the partner handoff. `watch-loop.sh` owns that logic.

## After handoff: start the watcher (mandatory)

The release order in `.duo/README.md` ends with "start the watcher
in the same turn." That is mandatory, not optional. Without it,
the partner's eventual signal lands on a dead workspace and the
duo stalls until the user notices and prods.

After work is done and committed, the exact order is:

1. Remove `.duo/workspace/lock.json` (`rm`).
2. Append the signal line to `.duo/workspace/signal.jsonl`.
3. **Start the watcher in the foreground**:
   `bash .duo/scripts/watch-loop.sh`. If the shell tool
   returns a session id, keep polling that same session; **do not
   end your turn until it returns** with `READY-CODEX`,
   `STALE-LOCK`, or an error. Backgrounding it and signing off
   strands the partner's handoff because Codex has no async wake-up.
   While it is running, stay silent and poll with long waits. If the
   runtime kills the foreground call, re-invoke immediately.
4. Write the user-facing summary (per README's "User-facing
   summary at handoff") as your final chat reply.

If you ever realize you signaled and ended the turn without
starting the watcher, the protocol is broken: start a watcher
immediately, before doing anything else.

## Behaviors

- Don't archive a project without explicit user confirmation in the
  most recent direct message. The README's archive workflow is
  user-triggered.
- For long iterations, use Codex's task tracker for sub-progress
  within the iteration. Tasks live in your session, NOT in the
  project file. Milestones live in the project file.
- Use `.duo/workspace/assets/` for renderings, screenshots, scene
  dumps, temp diagnostic scripts. They auto-archive with the
  project.

## After compaction

Reread, in order:

1. Newest direct user message.
2. `.duo/README.md`.
3. `.duo/agents/codex.md` (this file).
4. `.duo/workspace/signal.jsonl`, `.duo/workspace/lock.json`,
   `.duo/workspace/state.json`.
5. The latest numbered handoff in `.duo/workspace/handoffs/`.

Treat anything quoted in compaction summary context as historical,
not fresh.
