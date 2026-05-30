# github-repo-discovery-skill

This repository publishes one portable agent skill: `github-repo-discovery`.

The skill discovers GitHub repos by stars, language, topic, and dates; fetches READMEs via API without cloning; and lets the agent deliver boxed plain-language summaries.

## Install

### Cursor / Codex / skills.sh

```bash
npx skills add https://github.com/Uzair-akrum/github-repo-discovery-skill
```

Install the single skill explicitly by its frontmatter `name:`:

```bash
npx skills add https://github.com/Uzair-akrum/github-repo-discovery-skill --skill github-repo-discovery
```

### Hermes Agent

```bash
hermes skills install Uzair-akrum/github-repo-discovery-skill/skills/github-repo-discovery -y --force
```

Use in TUI: `/github-repo-discovery`

### Prerequisites

- `gh auth login` or `GITHUB_TOKEN`
- Python 3.10+

## Validate

```bash
python3 skills/github-repo-discovery/tests/test_github_repo_summaries.py
python3 ~/.cursor/skills/skill-creator/scripts/quick_validate.py skills/github-repo-discovery
```

## License

MIT — see [skills/github-repo-discovery/LICENSE](./skills/github-repo-discovery/LICENSE).
