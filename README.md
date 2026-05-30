# github-repo-discovery (Hermes skill)

Discover GitHub repos by stars, language, topic, and dates; fetch READMEs via API (no clone); deliver boxed plain-language summaries.

Compatible with [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [agentskills.io](https://agentskills.io/).

## Install

### Hermes Agent

```bash
hermes skills tap add Uzair-akrum/github-repo-discovery-skill
hermes skills install Uzair-akrum/github-repo-discovery-skill/github/github-repo-discovery
```

Copy locally for development:

```bash
cp -a github/github-repo-discovery ~/.hermes/skills/github/github-repo-discovery
```

Use in TUI: `/github-repo-discovery`

### Cursor / Codex / skills.sh

```bash
npx skills add Uzair-akrum/github-repo-discovery-skill@github-repo-discovery
```

### Prerequisites

- `gh auth login` or `GITHUB_TOKEN`
- Python 3.10+

## Validate

```bash
cd github/github-repo-discovery
python3 tests/test_github_repo_summaries.py
python3 ~/.cursor/skills/skill-creator/scripts/quick_validate.py .
```

## License

MIT — see [LICENSE](./LICENSE).
