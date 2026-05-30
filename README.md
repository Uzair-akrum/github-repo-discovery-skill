# github-repo-discovery-skill

This repository publishes one Hermes skill: `github-repo-discovery`.

The skill discovers GitHub repos by stars, language, topic, and dates; fetches READMEs via API without cloning; and lets the agent deliver boxed plain-language summaries.

## Install

### Hermes Agent

```bash
hermes skills install Uzair-akrum/github-repo-discovery-skill/github-repo-discovery --force
```

Copy locally for development:

```bash
git clone https://github.com/Uzair-akrum/github-repo-discovery-skill.git
cp -R github-repo-discovery-skill/github-repo-discovery ~/.hermes/skills/github-repo-discovery
```

Use in TUI: `/github-repo-discovery`

### Cursor / Codex / skills.sh

```bash
npx skills add https://github.com/Uzair-akrum/github-repo-discovery-skill --skill github-repo-discovery
```

### Prerequisites

- `gh auth login` or `GITHUB_TOKEN`
- Python 3.10+

## Validate

```bash
python3 github-repo-discovery/tests/test_github_repo_summaries.py
python3 ~/.cursor/skills/skill-creator/scripts/quick_validate.py github-repo-discovery
```

## License

MIT — see [github-repo-discovery/LICENSE](./github-repo-discovery/LICENSE).
