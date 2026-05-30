# github-repo-discovery-skill

## Skills

Each skill does one job; you do not need all of them at once. **Discovery skills** search and summarize repos from metadata and READMEs — no cloning.

The `Install name` column is the exact value you pass after `@` when installing from this repo (for example `npx skills add Uzair-akrum/github-repo-discovery-skill@<install-name>`).

| Skill (folder) | Install name | Description |
| --- | --- | --- |
| **github-repo-discovery** | `github-repo-discovery` | Find public GitHub repos by stars, language, topic, and dates. Fetches READMEs via the GitHub API (never clones). Default with no filters: top **10** repos created in the **last 7 days**, sorted by stars. Agent replies with boxed plain-language summaries. Requires `gh auth login` or `GITHUB_TOKEN`. |

## Install

```bash
npx skills add https://github.com/Uzair-akrum/github-repo-discovery-skill
```

## License

MIT — see [skills/github-repo-discovery/LICENSE](./skills/github-repo-discovery/LICENSE).
