# github-repo-discovery-skill

Agent skills for GitHub repository discovery — compatible with [Hermes Agent](https://github.com/NousResearch/hermes-agent), [Cursor](https://cursor.com), [Codex](https://openai.com/codex), and [skills.sh](https://skills.sh/).

## Skills

Each skill does one job; you do not need all of them at once. **Discovery skills** search and summarize repos from metadata and READMEs — no cloning.

The `Install name` column is the exact value you pass after `@` when installing from this repo (for example `npx skills add Uzair-akrum/github-repo-discovery-skill@<install-name>`).

| Skill (folder) | Install name | Description |
| --- | --- | --- |
| **github-repo-discovery** | `github-repo-discovery` | Find public GitHub repos by stars, language, topic, and dates. Fetches READMEs via the GitHub API (never clones). Default with no filters: top **10** repos created in the **last 7 days**, sorted by stars. Agent replies with boxed plain-language summaries. Requires `gh auth login` or `GITHUB_TOKEN`. |

## Install

```bash
npx skills add Uzair-akrum/github-repo-discovery-skill@github-repo-discovery
```

## Validate

```bash
cd skills/github-repo-discovery
python3 tests/test_github_repo_summaries.py
python3 ~/.cursor/skills/skill-creator/scripts/quick_validate.py .
```

## License

MIT — see [skills/github-repo-discovery/LICENSE](./skills/github-repo-discovery/LICENSE).
