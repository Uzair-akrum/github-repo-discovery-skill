# github-repo-discovery (Hermes skill)

Discover GitHub repos by stars, language, topic, and dates; fetch READMEs via API (no clone); deliver boxed plain-language summaries.

Compatible with [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [agentskills.io](https://agentskills.io/).

## Install

### Hermes Agent

```bash
hermes skills install Uzair-akrum/github-repo-discovery-skill
```

Copy locally for development:

```bash
git clone https://github.com/Uzair-akrum/github-repo-discovery-skill.git ~/.hermes/skills/github/github-repo-discovery
```

Use in TUI: `/github-repo-discovery`

### Cursor / Codex / skills.sh

```bash
npx skills add Uzair-akrum/github-repo-discovery-skill
```

### Prerequisites

- `gh auth login` or `GITHUB_TOKEN`
- Python 3.10+

## Validate

```bash
python3 tests/test_github_repo_summaries.py
python3 ~/.cursor/skills/skill-creator/scripts/quick_validate.py .
```

## License

MIT — see [LICENSE](./LICENSE).
