# decklet-skills

Agent skills for [decklet](https://github.com/yilin-zhang/decklet), for Claude
Code and compatible harnesses. Each subdirectory is one skill with its own
`SKILL.md`.

To install a skill in Claude Code, symlink its directory into
`~/.claude/skills/`:

```bash
ln -s "$(pwd)/decklet-card-back" ~/.claude/skills/decklet-card-back
```

## Available skills

| Skill | Purpose |
|---|---|
| [`decklet-card-back`](./decklet-card-back/) | Write Org-mode card backs for your words, after backing up the database |
| [`decklet-card-image`](./decklet-card-image/) | Draw consistent square pen-and-watercolor illustrations for your words, and optionally install them through `decklet-images` |
