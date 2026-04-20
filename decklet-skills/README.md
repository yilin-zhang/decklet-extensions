# decklet-skills

Markdown skill bundles for AI agents (Claude Code and compatible harnesses) that
automate [decklet](https://github.com/yilin-zhang/decklet) workflows. Each
subdirectory is a self-contained skill: a `SKILL.md` with YAML frontmatter plus
any reference files the skill needs.

No plugin manifest is included — drop an individual skill into whatever skill
harness you use. For Claude Code, symlink a skill directory into
`~/.claude/skills/`:

```bash
ln -s "$(pwd)/decklet-card-back" ~/.claude/skills/decklet-card-back
```

## Available skills

| Skill | Purpose |
|---|---|
| [`decklet-card-back`](./decklet-card-back/) | Generate thorough Org-mode card backs for vocabulary words by fanning out parallel LLM subagents; backs up the SQLite DB and writes results into the `cards.back` column |
