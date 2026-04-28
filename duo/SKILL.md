---
name: duo
description: Start, stop, or migrate a coordinated work session between two different coding-agent products in the current repo. `/duo` and `/duo start` set up `.duo/`, install a tiny AGENTS/CLAUDE bootstrap, fill project details from current context, ask only for missing essentials, and create `.duo/workspace/<project-name>.md`. `/duo stop` archives the active project and removes the bootstrap. `/duo migrate` is reserved for future schema migrations. Use only when the user explicitly invokes duo coordination.
argument-hint: "[start|stop|migrate]"
disable-model-invocation: true
---

# /duo — start or stop a duo session

Two different coding-agent products take alternating iterations.
Same-product duo is not supported because agent identity needs a
disk-backed signal that survives compaction.

## Mode Routing

Accept exactly one optional argument:

- Missing or `start` → run **Start Flow**.
- `stop` → run **Stop Flow**.
- `migrate` → run **Migrate Flow**.
- Anything else → say the valid forms are `/duo`, `/duo start`,
  `/duo stop`, and `/duo migrate`.

Do not treat the argument as the project objective. In Start Flow,
use project details already provided in the current direct user
context when they are concrete; ask only for missing or ambiguous
details.

## Start Flow

### 1. Locate Repo Root

Use `git rev-parse --show-toplevel`. If not in a git repo, fall back
to the current working directory and warn that `git commit` will not
work until `git init`.

### 2. Reject If Workspace Already Exists

Check `.duo/workspace/`. The directory's existence is the single
source of truth for "active duo session".

- `.duo/workspace/` exists → abort. Tell the user there is an active
  session and they must run `/duo stop` first (or keep working on
  the active project).
- `.duo/workspace/` does not exist → continue.

Don't read `state.json` or count handoffs for this check — directory
existence alone is the rule.

### 3. Set Up `.duo/`

Run the setup script from this skill directory:

```bash
bash <skill-dir>/scripts/setup.sh "<repo-root>"
```

The script is idempotent and never overwrites existing content. It:

- Creates `.duo/{README.md, agents/, scripts/, migrations/}`.
- Creates `.duo/workspace/{state.json, signal.jsonl, handoffs/,
  stale-locks/, assets/, .gitignore}`.
- Copies every `*.md` under this skill's `templates/agents/` into
  `.duo/agents/`. Bundled: `claude.md`, `codex.md`.
- Prepends a `DUO-BOOTSTRAP` block to `AGENTS.md` and `CLAUDE.md`,
  preserving existing content.

It does NOT create `.duo/workspace/lock.json` (iteration 1 does)
or pick an archive location (`/duo stop` does).

### 4. Read the Project Template

Read `templates/project.md` from this skill's directory. The
template's sections define the project file shape and the information
to consider in step 5. The template's own framing (e.g., milestone
goal, sub-numbering, blocker handling) is authoritative — do not
paraphrase or replace it with new framing of your own.

### 5. Guided Dialog

Walk through the template's sections in order. For each section,
first fill what you can from the current direct user context.

**One question per chat turn — wait for the answer before moving
to the next section.** Never batch multiple questions into one
free-form prompt; the user shouldn't have to pattern-match a
multi-part question and write an essay back.

For each question:

- Propose a concrete suggested answer **only when you have a real
  basis for it** — the current direct user context, the repo
  state, or sensible defaults the user can accept by replying
  "yes" / "1" / a short tweak. If you don't have that basis, do
  not invent one. Ask the question free-form and let the user
  state the answer. A made-up suggestion is worse than no
  suggestion: it pressures the user toward the agent's guess.
- If the question has discrete options, present them as a numbered
  list. The user can accept by typing the number, or override with
  their own text.
- If your runtime exposes an interactive structured-question tool
  (e.g. Claude's `AskUserQuestion` with multi-choice + free-form
  override), prefer it. If not, fall back to a plain numbered list
  in chat. The intent is the same either way: suggest, let the
  user accept or override cheaply.
- Skip the question entirely when the answer is already obvious
  from current direct context — fill it and move on. Don't ask
  just to populate optional sections; leave the template default
  or delete the section as the template instructs.
- **From the third question onward**, include an extra explicit
  option: *"Fill in the rest yourself and start working."* If
  the user picks it, stop asking. Fill remaining sections from
  context with sensible defaults (or template defaults where
  there is no signal), briefly report what you assumed, write
  the project file, and proceed to iteration 1. The user is
  signalling they trust your judgement on the remaining detail
  and want to get to work — honour that and don't backslide into
  more questions.

Notes per section:

- **Objective**: one sentence describing what done looks like. If
  already clear from current direct context, use it. If the only
  source is text after the `/duo` mode argument, ignore it — the
  argument is mode only — and ask. **Do not suggest an answer for
  this one.** The agent has no basis to guess the user's intent;
  ask plainly and let the user state it.
- **Project name**: propose a 3–5 word kebab-case name from the
  objective. If the user has already provided a concrete name, use
  it. Becomes the project filename and the archive subdirectory name.
- **Background**: optional 1–3 sentence context. Empty is fine.
- **Implementation questions**: record setup questions and user
  answers only when a real implementation choice must be clarified.
- **Acceptance criteria**: concrete checks that define done. Ask only
  if success cannot be judged from the objective and milestones.
- **Milestones**: the template's framing covers the goal (one
  milestone per iteration), sub-numbering (M1, M2, …, splitting mid-
  work as M6a, M6b), and the tasks-vs-milestones distinction. List
  the milestones you can clearly see now; let the rest emerge during
  work.
- **Blockers**: don't invent blockers at setup. Keep the template's
  "none known" text unless the user already named a real blocker.
- **Known risks and validation**: include risks or validation
  expectations already known from the user or obvious from the task;
  delete the section if there is nothing useful to record.
- **Stop conditions**: things the agent itself recognizes
  mid-iteration and pauses for. NOT user-initiated actions like
  `/duo stop` (which the user invokes to archive and tear down a
  finished session). Offer this default list and let the user
  check, edit, or add:
  - Destructive git ops (force push, branch delete, lock steal).
  - Visual inspection of rendered output if an automated vision
    check is inconclusive.
  - Research questions not answerable from local code or docs the
    project references.
  - Spec gap: "the plan does not cover X".
  - External side-effects (PR open / comment, Slack post, external
    API call).
- **Out of scope**: optional deferred work. Empty is fine.

After the template is filled in, identify the partner. Both
nicknames go into `state.json` as the `participants` array — that
is the source of truth either agent reads to find "the other".
The partner is the OTHER `.md` file in `.duo/agents/` (yours
matches your own nickname). One other → use it. Multiple → ask
which. None → ask the user to add one. Don't treat non-`.md`
files (e.g. the skill's own `agents/openai.yaml`) as partner
templates.

You (the setup agent) run iteration 1. No iteration-1-owner
question — if the user wanted the partner to start, they'd have
invoked `/duo` from the partner side.

### 6. Write Project State

Fill in the project template with the dialog answers and write the
result to `.duo/workspace/<project-name>.md`. Remove unused optional
sections (delete the section header rather than leave it blank).
Don't leave any `<placeholder>` strings in the final file.

Update `.duo/workspace/state.json`. Identify yourself by your
product nickname (the lowercase product family name — same string
the partner would use to refer to you). Don't use model names or
version variants — the product family is the stable identifier
across model upgrades.

```json
{
  "schemaVersion": 1,
  "currentProject": "<project-name>",
  "currentMilestone": "<M1 title>",
  "participants": ["<your nickname>", "<partner nickname>"],
  "currentTurn": "<your nickname>",
  "lastHandoff": null,
  "phase": {
    "name": "<project-name>",
    "startedAt": "<ISO 8601 UTC now>"
  },
  "setupBy": "<your nickname>",
  "testState": null
}
```

`participants` is the canonical pair list. To find the partner,
read it and remove your own nickname — don't re-derive from
`.duo/agents/*.md` at iteration time, since that directory may
contain unused agent templates.

`state.json` does NOT carry an archive location — `/duo stop` picks
that based on what already exists at archive time.

### 7. Report, then confirm, then lock + invite partner

Don't run `git add` or `git commit` during `/duo start` — create
files on disk only and let the user decide what to track. Also
do not tell the user to launch the partner yet: that comes only
*after* you hold the iteration-1 lock, so the partner can't race
or misread an empty workspace.

#### 7a. Report and ask for go-ahead

Briefly tell the user:
- Project name and objective.
- Path to `.duo/README.md` (protocol) and the project file.
- Files written or modified on disk:
  - New: `.duo/{.gitignore, README.md, agents/, scripts/,
    migrations/}`.
  - Modified (only if they were already tracked): `AGENTS.md`,
    `CLAUDE.md` — bootstrap block prepended.
- That you're ready to begin iteration 1 but waiting for their
  go-ahead. Invite a one- or two-word confirmation
  ("yes" / "start") or an opportunity to tweak the project file
  first.

Then **wait** for the user. Do not acquire the lock, do not start
work, do not invite the partner. The user may want to adjust
milestones, edit the project file, or discuss anything before
kickoff.

#### 7b. On confirmation: lock first, then invite partner, then work

When the user confirms, do these in order in a single response:

1. **Acquire the iteration-1 lock** with the helper script:
   ```bash
   .duo/scripts/lock.sh <your-nickname> 0001-<your-nickname>.md
   ```
   This is the disk signal that you own this turn. Without it,
   the partner agent — once launched — could read an empty
   `signal.jsonl` plus no lock, get confused about whose turn it
   is, or even race to take the lock itself.
2. **Now** tell the user the partner agent (`<partner nickname>`)
   can be launched safely. With your lock held, the partner reads
   the workspace and goes straight into watch mode. If the duo
   skill isn't installed on the partner side yet, they should
   symlink the skill's source-of-truth directory into the
   partner's skill path before launching.
3. Begin iteration 1 work.

The user can `git add` and commit any of the on-disk files
whenever they like. `/duo stop` later removes the bootstrap block.

## Stop Flow

`/duo stop` is the user's fresh confirmation to archive and tear down
the active duo session. Do not ask for a second confirmation unless
the live state is unsafe.

### 1. Read Live State

Locate the repo root. Check:

- `.duo/workspace/` — if missing, there is no active session. Remove
  any `DUO-BOOTSTRAP` blocks from `AGENTS.md` and `CLAUDE.md` if
  present, then report "no active duo session" and stop.

If `.duo/workspace/` exists, read:

- `.duo/README.md`
- `.duo/workspace/state.json`
- `.duo/workspace/lock.json` if present
- the active project file `.duo/workspace/<currentProject>.md` and
  latest handoff in `.duo/workspace/handoffs/`

If `state.json:currentProject` is `null`, treat this as incomplete
setup or a damaged workspace. Do not archive blindly. Tell the user
what files exist under `.duo/workspace/` and ask whether to remove
the workspace/bootstrap or leave it for manual recovery.

### 2. Lock Safety

If `.duo/workspace/lock.json` exists:

- Lock owner is the partner agent and not expired → abort. Tell the
  user which agent owns it and that the iteration must finish (or
  the lock must expire) before stop is safe.
- Lock is expired → follow `.duo/README.md` § Crash recovery
  (don't auto-steal). Resolve before archiving.
- Lock owner is you → continue (this happens if the agent running
  `/duo stop` was the one with the active iteration).

### 3. Choose Archive Location

This is when archive location is actually picked, because this is
when it's used.

- If `.duo/archive/` exists and contains archived project entries
  other than `.keep` → use it.
- Else if `docs/duo/archive/` exists → use it.
- Else → ask the user:

  > Where should the completed project be archived?
  > 1. `.duo/archive/<project-name>/` (default — stays under `.duo/`)
  > 2. `docs/duo/archive/<project-name>/` (publishes to `docs/`)

If both archive locations already contain archived project entries,
the workspace is inconsistent — flag it to the user and stop.

### 4. Archive

Read `currentProject` from `state.json` (call it `<name>`).

1. Create `<archive-location>/<name>/`.
2. Move `.duo/workspace/<name>.md` → `<archive-location>/<name>/<name>.md`.
3. Move every file under `.duo/workspace/handoffs/` →
   `<archive-location>/<name>/handoffs/`.
4. Move every file under `.duo/workspace/assets/` →
   `<archive-location>/<name>/assets/`.
5. Remove the entire `.duo/workspace/` directory. It was gitignored,
   so no git changes result from the removal — purely filesystem.
6. Remove the `DUO-BOOTSTRAP` block from both `AGENTS.md` and
   `CLAUDE.md`, leaving all other content untouched. If a file
   becomes empty as a result, delete it; otherwise leave it.

### 5. Report Stop (no auto-commit)

Don't run `git add` or `git commit` during `/duo stop`. Move files
on disk only; let the user decide what to track.

Briefly tell the user:
- Archive path: `<archive-location>/<name>/` (project doc,
  handoffs/, assets/).
- Workspace removed: `.duo/workspace/` (was gitignored — purely
  filesystem, no git change).
- Bootstrap removed from `AGENTS.md` and `CLAUDE.md` (or `CLAUDE.md`
  deleted if it became empty).
- The user can `git add` and commit whichever of these they want
  tracked.

## Don't

- Don't create `.duo/workspace/lock.json` during setup. The first
  real iteration creates it.
- Don't treat `/duo <text>` as the objective; the argument is mode
  only. Infer concrete project details from current direct context;
  ask only for missing or ambiguous essentials.
- Don't take iteration-style actions (writing handoffs, posting
  signal lines beyond the kickoff). That's iteration agents' work.
- Don't commit `signal.jsonl`, `lock.json`, or `stale-locks/`.
- Don't overwrite existing `AGENTS.md` or `CLAUDE.md` content. The
  bootstrap block is prepended; everything else is preserved.
- Don't bake project-specific names, test frameworks, or branch
  names into anything. All of it comes from the dialog.
- Don't offer same-product handoff for iteration 1.
- Don't dictate commit message format — follow the repo's
  conventions.
- Don't archive from stale summary context; `/duo stop` must be a
  newest direct user request or equivalent explicit instruction.

## Migrate Flow

`/duo migrate` is reserved for future `.duo/workspace/state.json`
schema migrations. It is not implemented yet. Future migrations
should be deterministic Node.js scripts stored under
`.duo/migrations/` and run in version order. For now, report that no
migration runner exists and do not modify files.
