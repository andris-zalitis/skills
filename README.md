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

Clone this repo wherever you keep your projects, then symlink each skill
into the runtime directories that should see it:

```sh
SKILLS_REPO=/path/to/this/repo   # wherever you cloned it

ln -s "$SKILLS_REPO/<skill-name>" ~/.claude/skills/<skill-name>
ln -s "$SKILLS_REPO/<skill-name>" ~/.codex/skills/<skill-name>
```

Editing the file in any one location edits the canonical copy in the repo.
