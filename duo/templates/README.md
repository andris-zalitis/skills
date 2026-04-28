# Duo Coordination Workspace

Two different coding-agent products take alternating iterations on
this repository. Same-product duo is not supported — agent identity
wouldn't survive compaction without an external grounding signal
that doesn't exist inside an LLM session.

The repo `AGENTS.md` / `CLAUDE.md` bootstrap points agents here.
This file is the runtime protocol; the `/duo` skill only
installs/removes the bootstrap and workspace files.

## File layout

```
.duo/                       # TRACKED
  .gitignore                # ignores workspace/
  README.md                 # this file
  agents/
    <nickname>.md           # per-product specifics
  scripts/                  # watcher/lock scripts; use the exact
                            # watcher named by your agent file
  migrations/               # JS migrations between schema versions
  archive/<project>/        # created by /duo stop for completed
                            # projects, with their
                            # handoffs/ and assets/

  workspace/                # UNTRACKED (whole subtree gitignored)
    state.json              # current project, milestone, turn,
                            # test state. schemaVersion: 1
    signal.jsonl            # append-only turn-change log
    lock.json               # active iteration owner. Created by
                            # the iterating agent
    <project>.md            # master project doc for the active
                            # session
    handoffs/               # numbered iteration handoffs
                            # (NNNN-<nickname>.md)
    stale-locks/            # explicitly-stolen locks for forensics
    assets/                 # renderings, screenshots, scene dumps,
                            # temp diagnostic scripts
```

Workspace is intentionally untracked. In a team, two devs on the
same branch can't share an active workspace — the workspace
represents one duo pair's in-flight state, not project history.
History is preserved by `/duo stop`, which moves workspace contents
into `.duo/archive/<project>/` (TRACKED) before tearing down the
workspace. Pull requests see the archive, not the live coordination.

Each agent must read its own `.duo/agents/<own-nickname>.md` for
product-specific watcher / tool details. **Required reading at
session start, after compaction, before watching, before taking a
lock, before releasing a lock, and before writing a handoff.** The
generic README is not enough because watcher behavior is
product-specific.

## Compaction safety

Sessions in this workspace span hours and many compactions. Every
compaction quotes user messages verbatim, so an instruction from
four hours ago looks identical to one from four minutes ago.

### Detect compaction

You're in a fresh post-compaction state if a summary, Codex-style
`summary` block, or "previous conversation" block sits immediately
before the current user prompt, with little or no direct dialogue,
tool calls, or tool results between the summary and the prompt.

A summary block at the START of the session followed by extensive
direct interaction (tool calls, edits, dialogue) is just historical
— not the trigger. Multiple recent tool calls, results, and
reasoning steps from this session visible directly between any
summary and the current prompt → not in compaction state. Proceed
normally; no special rereading needed.

The discriminator is what sits between the most recent summary and
the current user prompt, not the mere presence of a summary
somewhere in context.

### If compaction detected

1. Reread live state: `state.json`, `signal.jsonl`, `lock.json` if
   present, the active project file, the latest handoff, your own
   `.duo/agents/<your-nickname>.md`.
2. Compare live state against the user message you're about to act
   on. If the work was already done, the message is stale.
3. If freshness is uncertain, ask: "I see your earlier message
   asking for X. Live state shows Y. Should I still do X, or has
   the situation moved on?"

### Why this matters in duo specifically

A solo session might compact once or twice. A duo session running
pair programming compacts dozens of times over hours. The same user
message — "fix item #3" — keeps resurfacing in summary context long
after item #3 was closed. Without active verification when
compaction is detected, agents re-run done work or pressure the
user about something they moved past hours ago.

Live disk + newest direct user message wins. Always.

## Coordination protocol

### Turn ownership

The latest line in `.duo/workspace/signal.jsonl` determines who's
next. Do not edit files unless:

- The latest signal names you as `next`, AND
- You have acquired `.duo/workspace/lock.json`.

Before watching or editing, evaluate live disk state:

- Lock owner is you → continue the locked iteration; do not watch.
- Lock owner is partner and not expired → watch; do not edit.
- Lock exists and is expired → stop for recovery; do not steal.
- No lock and latest signal names you → acquire lock and work.
- No lock and latest signal names partner → watch.

While the partner agent owns the lock, **read-only answers to the
user's process questions are allowed** — explaining the protocol,
showing what's in handoffs/, summarizing the current state. Do not
edit files or run work that interferes with the locked iteration.

### Pre-work validation checklist

Before acquiring a lock and starting work, validate all of:

- The latest line in `signal.jsonl` names you as `next`.
- The named handoff in that signal line exists at
  `.duo/workspace/handoffs/`.
- No valid `lock.json` exists.
- No `*.tmp` file is pending in `.duo/workspace/handoffs/` (a
  pending `*.tmp` means a previous iteration crashed mid-write).
- Your handoff number will be the previous number + 1, OR `0001`
  if the workspace was just freshly set up after `/duo stop`.
- `git status` is understood (no uncommitted changes you don't own).

If any check fails, do not proceed. Resolve or wait.

### Lock acquisition (atomic)

Run the helper script:

```bash
.duo/scripts/lock.sh <your-nickname> NNNN-<your-nickname>.md
```

The script atomically creates `lock.json` (exits 0, prints the new
lock) or refuses if one already exists (exits non-zero, prints the
existing owner to stderr). It uses `set -C` (noclobber) so two
agents cannot both succeed.

The handoff filename is named after **you** — the lock owner —
because `lock.json` records the handoff *this iteration will
produce*, not the partner's previous one. Pick `NNNN` as
previous-handoff-number + 1 (or `0001` if the workspace is fresh
after `/duo stop`).

If the script exits non-zero, another agent owns the turn. Do not
edit.

### Release order (after work + handoff)

1. Write handoff at `.duo/workspace/handoffs/NNNN-<you>.md.tmp`.
2. Atomically rename to `.md`.
3. Update `.duo/workspace/state.json`.
4. Commit work changes (everything OUTSIDE `.duo/workspace/`,
   which is the project files you actually changed). Workspace
   contents are gitignored — handoff and state stay local.
5. Remove `.duo/workspace/lock.json`.
6. Append one signal line to `.duo/workspace/signal.jsonl` naming
   the next owner.
7. If the next signal names the OTHER agent, start the watcher in
   the same turn. Don't stop until the user explicitly releases you
   or the next signal names you again.

If any step before the signal append fails, keep the lock. A
missing or invalid handoff must not wake the partner agent.

Concrete failure example: **if `git commit` fails, do not unlock
and do not signal**. Resolve the commit failure first (fix the hook
that rejected, fix the file that wasn't formatted, etc.). Only then
proceed with steps 5–7. Unlocking before the commit succeeds leaves
the partner agent acting on uncommitted state.

### Documentation changes are iteration deliverables

Even a docs-only change (updating the project file, fixing typos
in handoffs, refactoring the README of a sub-component) counts as
an iteration. Write a numbered handoff for it. Don't accumulate
docs work into a "next agent picks it up" pile.

### Keep the running project file current

The project file at `.duo/workspace/<project>.md` is the living
record of the work, not a one-shot setup artifact. It must reflect
what's true *now*, not just what was true at iteration 1.

**When the user gives a new direction, decision, scope change, or
stop condition during work, fold it into the project file in the
same iteration that picks it up.** Specifically capture:

- **New milestones or scope expansions.** "We also need to fix X"
  → add an M-section.
- **Decisions made.** "We're not using HDR env" / "wood colour goes
  cooler" → record the decision and the reason in the relevant
  milestone or in Acceptance criteria.
- **New stop conditions or constraints.** "Don't ever auto-commit
  Y" / "always verify with Gemini before merging" → add to Stop
  conditions or Known risks.
- **Directional changes that supersede earlier plans.** "Forget
  M3, do M2c first" → mark the superseded section and add the new
  one with date.
- **Open user-direction items collected mid-work** that are not
  formal milestones yet (e.g., "we need an end-grain texture")
  → capture in an "Open user-direction items" section so the next
  agent doesn't lose them.

Do **not** capture every line of chat, intermediate diagnostic
states, debugging chatter, or tone — those belong in the per-
iteration handoff. The project file is the curated trunk; handoffs
are branches recording how each iteration got there.

If you finish an iteration and realise you took user direction but
didn't update the project file, that's a handoff defect. Fix it
in the same iteration before signalling the partner.

### User-facing summary at handoff

After signaling the partner agent, your final chat reply to the
user must include a short summary so they can follow along without
opening the handoff file. Cover:

- **What was done** in this iteration. One or two sentences. Name
  the milestone or sub-milestone if applicable.
- **What the partner is expected to do next.** Mirror the "next
  recommended step" from your handoff.
- **Any context or blockers** the user should know about — open
  questions, deferred decisions, partial state, things that didn't
  land.
- **Anything else the user genuinely needs to see** — test result
  delta (e.g. "631 → 632 passed"), file paths the user might want
  to review, render artifacts under `.duo/workspace/assets/`, etc.

Keep it tight. The handoff file is the canonical record; the
summary is the courtesy.

### Handoff format

Each numbered handoff includes:

- Current objective.
- Files changed.
- Tests run + exact results.
- Known failures or risks.
- Next recommended step.
- Explicit warnings about approaches already tried and rejected.

### Splitting milestones during work

If you start an iteration and find the milestone is too big to
complete:

1. Split it in the project file: replace `M6` with `M6a`, `M6b`,
   `M6c` (or sub-numbering as appropriate).
2. Note the split in your handoff.
3. Take only the first sub-milestone in this iteration.
4. Hand off the next sub-milestone to the partner.

Don't stretch one milestone across multiple iterations silently.

### Watcher invocation

Watcher scripts are product-specific. Do not choose a watcher script
from this generic README. Read `.duo/agents/<your-nickname>.md` and
use the exact invocation it documents.

The watcher is the load-bearing mechanism that keeps the duo alive.
If the user goes away while you are the designated watching agent,
keep watching until the next direct user instruction or signal
change — not until some arbitrary polling deadline passes. The
TIMEOUT-restart obligation applies regardless of mechanism (Claude's
persistent monitor, Codex's outer poll loop, future products' own
shapes).

Watching should be quiet. Do not send periodic chat updates just to
say the watcher is still running. Report only when the watcher
resolves, hits a recovery/error condition, or the user explicitly
asks for status.

Don't apply another product's watcher workaround to yourself. Read
your own `.duo/agents/<your-nickname>.md` and use the invocation it
documents.

### Pause for external research or visual confirmation

Some iterations need outside knowledge or human visual confirmation
that can't be resolved from local code, tests, docs, or any
auto-vision check the project provides. When pausing for the user:

1. Keep `lock.json` in place. The iteration isn't done.
2. Do NOT append a signal line. The partner agent must not wake.
3. Write and commit the numbered handoff and state.json update so
   the live record matches the pause.
4. Tell the user exactly what decision or visual confirmation is
   needed.

Not external research: finding files, tracing code, reproducing
failures, reading local docs, or checking prior handoffs. Those are
the agent's job.

External research examples: a canonical algorithm not in the
project's docs, behavior of a third-party kernel in a topological
edge case, a mathematical question not answerable from the repo.

### Crash recovery

**A FOREIGN LOCK (ONE OWNED BY THE PARTNER AGENT) MUST NEVER BE
MODIFIED, MOVED, OR REMOVED. NOT EVEN AFTER THE PARTNER PROCESS IS
DEAD. NOT EVEN IF THE LOCK IS EXPIRED. NOT EVEN IF THE USER SAYS "I
STOPPED HIM" OR DESCRIBES STOPPING THE PARTNER — THAT IS A STATUS
UPDATE, NOT AUTHORIZATION. ASK THE USER EXPLICITLY AND WAIT FOR A
DIRECT INSTRUCTION TO PROCEED BEFORE TOUCHING THE LOCK FILE.**

- If `.duo/workspace/lock.json` exists and `expiresAt` is in the
  future, wait.
- If the lock is expired, do **not** steal automatically. Ask the
  user or write a recovery note.
- If the partner's process is known to be dead but the lock has not
  yet expired (orphan lock), treat it the same as expired: do not
  steal automatically — ask first.
- Only with explicit user approval — a direct instruction to take
  over, not a status update — move the foreign lock into
  `.duo/workspace/stale-locks/`, then acquire a fresh lock.

## Archive workflow

The `/duo stop` skill drives this workflow. Manual archives must
follow the same steps.

When the user confirms the active project is complete:

1. Read `currentProject` from `.duo/workspace/state.json` (call it
   `<name>`).
2. Pick the archive location at archive time, not earlier:
   - If `.duo/archive/` exists and contains archived project entries
     other than `.keep` → use it.
   - Else if `docs/duo/archive/` exists → use it.
   - Else → ask the user. Default `.duo/archive/`.
3. Create `<archive-location>/<name>/`.
4. Move `.duo/workspace/<name>.md` →
   `<archive-location>/<name>/<name>.md`.
5. Move every file in `.duo/workspace/handoffs/` (except `.keep`)
   → `<archive-location>/<name>/handoffs/`.
6. Move every file in `.duo/workspace/assets/` (except `.keep`)
   → `<archive-location>/<name>/assets/`.
7. Remove the entire `.duo/workspace/` directory. The next
   `/duo start` recreates it from scratch.
8. Remove the `DUO-BOOTSTRAP` block from `AGENTS.md` and
   `CLAUDE.md`. Leave other existing content untouched.
9. Do NOT auto-commit. Tell the user what moved on disk (archive
   path, workspace removal, bootstrap removal) and let them stage
   and commit whichever pieces they want tracked.

After this, the repo is ready for the next `/duo start`.

Phase archive/reset is allowed only when the newest direct user
message confirms closure. Do not archive from stale summary context.

## Schema versioning

`.duo/workspace/state.json:schemaVersion` indicates the workspace
schema. On session start, read it:

- Missing → treat as v1.
- Matches what your agent's skill version expects → proceed.
- Older → `/duo migrate` is the reserved future command for running
  Node.js migration scripts from `.duo/migrations/` in version order.
  It is not implemented yet; stop and update the skill before
  modifying the workspace.
- Newer than expected → refuse to act. Tell the user: "this
  workspace is at schema N; this skill expects schema M. Update the
  skill before continuing."
