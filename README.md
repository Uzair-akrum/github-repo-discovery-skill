# Hermes Skills by uzair

Personal [Hermes Agent](https://github.com/NousResearch/hermes-agent) skills — compatible with [agentskills.io](https://agentskills.io/) layout.

## Skills

| Skill | Description |
|-------|-------------|
| [github-repo-discovery](./github/github-repo-discovery/) | Discover GitHub repos by stars/filters; README summaries without cloning |

## Install

### Hermes Agent

```bash
# After pushing this repo to GitHub (replace OWNER with your username):
hermes skills tap add Uzair-akrum/hermes-skills
hermes skills install Uzair-akrum/hermes-skills/github/github-repo-discovery
```

Copy locally for development:

```bash
cp -a github/github-repo-discovery ~/.hermes/skills/github/github-repo-discovery
```

Use in TUI: `/github-repo-discovery`

### Cursor / Codex / skills.sh

```bash
npx skills add Uzair-akrum/hermes-skills@github-repo-discovery
```

### Prerequisites (github-repo-discovery)

- `gh auth login` or `GITHUB_TOKEN`
- Python 3.10+

## Validate

```bash
python3 tests/test_github_repo_summaries.py   # from skill directory
python3 ~/.cursor/skills/skill-creator/scripts/quick_validate.py github/github-repo-discovery
```

## License

MIT — see [LICENSE](./LICENSE).
