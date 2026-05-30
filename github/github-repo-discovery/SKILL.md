---
name: github-repo-discovery
description: >-
  Discover public GitHub repositories by stars, language, topic, and date filters;
  fetch README content via the GitHub API without cloning; reply with boxed plain-language
  summaries. Use when the user wants weekly trending repos, niche repo search, star or
  date filtered discovery, or README-based recommendations. Default with no filters: top
  10 repos created in the last 7 days sorted by stars. Requires gh auth or GITHUB_TOKEN.
license: MIT
metadata:
  short-description: Weekly GitHub repo discovery with README summaries
  hermes:
    version: 1.4.0
    author: uzair
    tags: [GitHub, Repositories, Discovery, Search, Stars, Research]
    related_skills: [github-auth, github-repo-management]
---

# GitHub Repository Discovery

Find public GitHub repositories by stars, language, topic, and date filters. **Never clone or download repositories.**

## Default behavior

| Invocation | Script behavior |
|------------|-----------------|
| **No prompt / no filters** | Top **10** repos **created in the last 7 days**, sorted by stars, `--readme-chars 3500` |
| **With filters** (topic, language, stars, date, etc.) | Use what the user asked for; defaults `--limit 20`, `--readme-chars 10000` |

README summaries are always implied unless the user asks for metadata-only (`--no-include-readme --format table`).

## Prerequisites

- GitHub auth via `gh auth login` (preferred) or `GITHUB_TOKEN` in the environment
- See `github-auth` if auth is missing

## Helper script

```bash
python3 ${HERMES_SKILL_DIR}/scripts/github-repo-summaries.py [query] [options]
```

`HERMES_SKILL_DIR` is the directory containing this SKILL.md.

## Agent rules

### Deliverable

- Run the script to **stdout**. Read each README section, then reply with **boxed plain summaries** — 2–3 sentences per repo in everyday language.
- Never paste raw script output. No "good fit" / "skip if" labels.
- One box per repo; numbered title, summary, URL, blank line between boxes (see format below).

### Execution

1. **Use only the current user request** — do not carry keywords from earlier turns.
2. **Empty prompt** → run the script with **no arguments** (weekly top 10).
3. **Run at most twice.** First run to stdout. If output truncates (~50KB), re-run **once** with `--readme-chars 2500`; if still truncated, halve `--limit`. Never run 3+ times.
4. **No file writes** unless the user asks to save — no `-o /tmp/...`, no `python3 -c` parsing.
5. **Prefer script flags** (`--min-stars`, `--created-after`, `--pushed-after`) over hand-built query strings.
6. **Always fetch READMEs** with `--format markdown` unless user asked for metadata-only.
7. **Trust stderr** — check `# results: N` before claiming zero matches.
8. **Do not patch the script** during discovery runs unless the user asks for a code change.
9. **No clone** unless the user explicitly asks for deep codebase analysis.

### Date semantics

- `--created-after` → repos **created** after that date
- `--pushed-after` → repos with **recent pushes** (includes old popular repos)

### Output format (required)

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 1. owner/repo · 1,554 stars · HTML

 Generates carousel images from text for social posts — describe
 what you want and get graphics back, no design tool needed.

 https://github.com/owner/repo
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

### Good vs bad

**Bad:** structured labels (`What it does:`, `Good fit if:`), dense README dumps, raw script output.

**Good:** flowing 2–3 sentence prose inside each box.

## Common examples

```bash
# Default: top 10 repos created in the last 7 days (no args needed)
python3 ${HERMES_SKILL_DIR}/scripts/github-repo-summaries.py

# Standard discovery with README fetch
python3 ${HERMES_SKILL_DIR}/scripts/github-repo-summaries.py \
  --created-after 2026-05-25 --min-stars 300 --sort stars --limit 10

# Niche search
python3 ${HERMES_SKILL_DIR}/scripts/github-repo-summaries.py "agent framework" \
  --language python --min-stars 1000 --limit 8

# Longer README fetch for fewer repos
python3 ${HERMES_SKILL_DIR}/scripts/github-repo-summaries.py "rag" \
  --language python --min-stars 2000 --limit 5 --readme-chars 15000

# Metadata-only quick scan
python3 ${HERMES_SKILL_DIR}/scripts/github-repo-summaries.py "database" \
  --min-stars 5000 --no-include-readme --format table --limit 20
```

## Adjustable filters

| Flag | Purpose |
|------|---------|
| `query` | Optional free-text search terms |
| `--language`, `-l` | Primary language (one only) |
| `--topic`, `-t` | Topic filter (repeatable) |
| `--min-stars` / `--max-stars` | Star range (enforced client-side when dates used) |
| `--created-after` | Repos **created** after date (`YYYY-MM-DD`) |
| `--pushed-after` | Repos **pushed** after date (`YYYY-MM-DD`) |
| `--sort` | `stars`, `forks`, `updated`, `help-wanted-issues` |
| `--limit` | Max repos, 1–100 (default: **10** weekly / **20** custom) |
| `--include-readme` / `--no-include-readme` | Fetch README via API (default: on) |
| `--readme-chars` | Max README chars per repo (default: **3500** weekly / **10000** custom) |
| `--include-topics` / `--no-include-topics` | Repo topics via API |
| `--format` | `markdown` (default), `json`, or `table` (metadata only) |
| `-o`, `--output` | **Only when user asks** to save a report to disk |

## When to use this vs other skills

| Task | Use |
|------|-----|
| Discover repos + explain what they do | **This skill** |
| Compare many repos at a glance (metadata only) | `--no-include-readme --format table` |
| Clone, fork, or manage a repo | `github-repo-management` |
| Deep file-level analysis | `codebase-inspection` (only if user asks) |

## Notes

- README fetch = 1 API call per repo (parallelized, ~5s for 10 repos)
- Script prints `# query:`, `# results:`, and `# mode: weekly` on stderr when using defaults
- Non-404 API failures print `# warn:` on stderr
- **No auto-save.** Summaries live in the chat unless the user asks to export
