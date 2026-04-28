# skills

Cross-runtime skills shared between Claude Code (`~/.claude/`) and Codex (`~/.codex/`).

Each top-level directory is a single skill, structured per the runtime's expectations
(`SKILL.md` at the root, plus optional `agents/`, `scripts/`, `templates/`).

## Layout

```
skills/
├── <skill-name>/
│   ├── SKILL.md
│   ├── agents/      (optional)
│   ├── scripts/     (optional)
│   └── templates/   (optional)
```

## Wiring

Clone this repo wherever you keep your projects. Then pick one of two
symlink strategies for each runtime:

### Option A — symlink the whole skills/ directory

Best when every skill you use lives here and you don't want to add a new
symlink each time you publish a skill. The runtime's existing `skills/`
directory must be empty or moved aside first.

```sh
SKILLS_REPO=/path/to/this/repo   # wherever you cloned it

ln -s "$SKILLS_REPO" ~/.claude/skills
ln -s "$SKILLS_REPO" ~/.codex/skills
```

### Option B — symlink individual skills

Best when the runtime's `skills/` directory is a mix: some skills live
here, others are local-only or installed by another tool.

```sh
SKILLS_REPO=/path/to/this/repo

ln -s "$SKILLS_REPO/<skill-name>" ~/.claude/skills/<skill-name>
ln -s "$SKILLS_REPO/<skill-name>" ~/.codex/skills/<skill-name>
```

Editing the file in any one location edits the canonical copy in the repo.
