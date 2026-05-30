#!/usr/bin/env python3
"""Search GitHub repositories and emit metadata summaries (no cloning)."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from functools import partial
from typing import Any


GITHUB_API = "https://api.github.com"
SEARCH_JSON_FIELDS = (
    "fullName,description,stargazersCount,forksCount,language,createdAt,"
    "updatedAt,pushedAt,url,isArchived,isFork,license,openIssuesCount"
)
OVERFETCH_FACTOR = 5

DEFAULT_LIMIT = 20
DEFAULT_README_CHARS = 10000
DEFAULT_WEEKLY_LIMIT = 10
DEFAULT_WEEKLY_DAYS = 7
DEFAULT_WEEKLY_README_CHARS = 3500


class GitHubAPIError(RuntimeError):
    def __init__(self, path: str, code: int, body: str) -> None:
        self.path = path
        self.code = code
        self.body = body
        super().__init__(f"GitHub API {path} failed ({code}): {body}")


@dataclass(frozen=True)
class SearchPlan:
    """Single place for gh query string, fetch sizing, and client-side filters."""

    gh_query: str
    fetch_limit: int
    result_limit: int
    min_stars: int | None
    max_stars: int | None
    created_after: str | None
    pushed_after: str | None


def _run(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip() or "command failed")
    return proc.stdout


def auth_token() -> str:
    token = subprocess.run(
        ["gh", "auth", "token"],
        capture_output=True,
        text=True,
    )
    if token.returncode == 0 and token.stdout.strip():
        return token.stdout.strip()
    env_token = os.environ.get("GITHUB_TOKEN", "").strip()
    if env_token:
        return env_token
    raise RuntimeError(
        "No GitHub auth found. Run `gh auth login` or set GITHUB_TOKEN."
    )


def gh_api(path: str, token: str) -> Any:
    req = urllib.request.Request(
        f"{GITHUB_API}{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "hermes-github-repo-discovery",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise GitHubAPIError(path, exc.code, body) from exc


def _query_has_qualifier(query: str, prefix: str) -> bool:
    return bool(re.search(rf"\b{re.escape(prefix)}:", query, re.IGNORECASE))


def _parse_day(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)


def _parse_iso(value: str) -> datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value)


def _has_date_filter(args: argparse.Namespace) -> bool:
    query = (args.query or "").strip()
    return bool(
        args.created_after
        or args.pushed_after
        or _query_has_qualifier(query, "created")
        or _query_has_qualifier(query, "pushed")
    )


def _has_explicit_filters(args: argparse.Namespace) -> bool:
    return bool(
        (args.query or "").strip()
        or args.created_after
        or args.pushed_after
        or args.min_stars is not None
        or args.max_stars is not None
        or args.topic
        or args.language
    )


def _week_ago_date() -> str:
    return (datetime.now(timezone.utc).date() - timedelta(days=DEFAULT_WEEKLY_DAYS)).isoformat()


def resolve_mode_defaults(args: argparse.Namespace) -> bool:
    """Weekly mode when no search filters; otherwise custom defaults. Returns True if weekly."""
    if _has_explicit_filters(args):
        if not hasattr(args, "limit"):
            args.limit = DEFAULT_LIMIT
        if not hasattr(args, "readme_chars"):
            args.readme_chars = DEFAULT_README_CHARS
        return False

    args.created_after = _week_ago_date()
    if not hasattr(args, "limit"):
        args.limit = DEFAULT_WEEKLY_LIMIT
    if not hasattr(args, "readme_chars"):
        args.readme_chars = DEFAULT_WEEKLY_README_CHARS
    return True


def plan_search(args: argparse.Namespace) -> SearchPlan:
    """Build gh query and client filters. Date qualifiers must precede stars: or GitHub ignores them."""
    query = (args.query or "").strip()
    parts: list[str] = []
    if query:
        parts.append(query)

    if args.created_after and not _query_has_qualifier(query, "created"):
        parts.append(f"created:>{args.created_after}")
    if args.pushed_after and not _query_has_qualifier(query, "pushed"):
        parts.append(f"pushed:>{args.pushed_after}")

    has_date = _has_date_filter(args)
    # When a date filter is active, star thresholds are enforced client-side only.
    if not has_date:
        if args.min_stars is not None and not _query_has_qualifier(query, "stars"):
            parts.append(f"stars:>={args.min_stars}")
        if args.max_stars is not None and not _query_has_qualifier(query, "stars"):
            parts.append(f"stars:<={args.max_stars}")

    if args.fork is False and not _query_has_qualifier(query, "fork"):
        parts.append("fork:false")
    if args.archived is False and not _query_has_qualifier(query, "archived"):
        parts.append("archived:false")

    gh_query = " ".join(parts) or "stars:>100"
    fetch_limit = args.limit
    if has_date and args.min_stars is not None:
        fetch_limit = min(max(args.limit * OVERFETCH_FACTOR, args.limit), 100)

    return SearchPlan(
        gh_query=gh_query,
        fetch_limit=fetch_limit,
        result_limit=args.limit,
        min_stars=args.min_stars,
        max_stars=args.max_stars,
        created_after=args.created_after,
        pushed_after=args.pushed_after,
    )


def search_repos(args: argparse.Namespace, plan: SearchPlan) -> list[dict[str, Any]]:
    cmd = [
        "gh",
        "search",
        "repos",
        plan.gh_query,
        "--sort",
        args.sort,
        "--order",
        args.order,
        "--limit",
        str(plan.fetch_limit),
        "--json",
        SEARCH_JSON_FIELDS,
    ]
    if args.language:
        cmd.extend(["--language", args.language])
    for topic in args.topic:
        cmd.extend(["--topic", topic])
    raw = _run(cmd)
    return json.loads(raw)


def filter_repos(repos: list[dict[str, Any]], plan: SearchPlan) -> list[dict[str, Any]]:
    """Enforce filters client-side so summaries match GitHub web search semantics."""
    filtered = repos

    if plan.min_stars is not None:
        filtered = [
            repo
            for repo in filtered
            if int(repo.get("stargazersCount") or 0) >= plan.min_stars
        ]
    if plan.max_stars is not None:
        filtered = [
            repo
            for repo in filtered
            if int(repo.get("stargazersCount") or 0) <= plan.max_stars
        ]

    if plan.created_after:
        cutoff = _parse_day(plan.created_after)
        filtered = [
            repo
            for repo in filtered
            if (created := repo.get("createdAt")) and _parse_iso(created) > cutoff
        ]

    if plan.pushed_after:
        cutoff = _parse_day(plan.pushed_after)
        filtered = [
            repo
            for repo in filtered
            if (pushed := repo.get("pushedAt") or repo.get("updatedAt"))
            and _parse_iso(pushed) > cutoff
        ]

    return filtered


def clean_readme(text: str) -> str:
    """Drop noisy badge/HTML header lines; keep readable markdown body."""
    cleaned: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            cleaned.append("")
            continue
        if stripped.startswith("<p align") or stripped.startswith("</p>"):
            continue
        if stripped.startswith("<img") or stripped.startswith("<a href"):
            continue
        if re.fullmatch(r"!\[[^\]]*\]\([^)]+\)", stripped):
            continue
        if re.fullmatch(r"\[!\[[^\]]*\]\([^)]+\)\]\([^)]+\)", stripped):
            continue
        cleaned.append(line.rstrip())

    body = "\n".join(cleaned)
    body = re.sub(r"\n{3,}", "\n\n", body).strip()
    return body


def truncate_readme(text: str, max_chars: int) -> tuple[str, bool]:
    if len(text) <= max_chars:
        return text, False
    chunk = text[:max_chars]
    cut = chunk.rfind("\n\n")
    if cut > max_chars // 2:
        chunk = chunk[:cut]
    return chunk.rstrip() + "\n\n… (README truncated)", True


def fetch_readme(full_name: str, token: str, max_chars: int) -> tuple[str, bool]:
    try:
        data = gh_api(f"/repos/{full_name}/readme", token)
    except GitHubAPIError as exc:
        if exc.code != 404:
            print(
                f"# warn: readme fetch failed for {full_name}: HTTP {exc.code}",
                file=sys.stderr,
            )
        return "", False
    content = data.get("content")
    if not content:
        return "", False
    try:
        text = base64.b64decode(content).decode("utf-8", errors="replace")
    except (ValueError, UnicodeDecodeError):
        return "", False
    text = clean_readme(text)
    if not text:
        return "", False
    return truncate_readme(text, max_chars)


def repo_topics(full_name: str, token: str) -> list[str]:
    try:
        data = gh_api(f"/repos/{full_name}/topics", token)
    except GitHubAPIError as exc:
        if exc.code != 404:
            print(
                f"# warn: topics fetch failed for {full_name}: HTTP {exc.code}",
                file=sys.stderr,
            )
        return []
    names = data.get("names") or []
    return [str(name) for name in names]


def enrich_repo(
    repo: dict[str, Any],
    token: str,
    include_readme: bool,
    readme_chars: int,
    include_topics: bool,
) -> dict[str, Any]:
    full_name = repo.get("fullName") or ""
    enriched = dict(repo)
    if include_topics and full_name:
        enriched["topics"] = repo_topics(full_name, token)
    if include_readme and full_name:
        readme, truncated = fetch_readme(full_name, token, readme_chars)
        enriched["readme"] = readme
        enriched["readmeTruncated"] = truncated
        if not readme:
            enriched["readmeMissing"] = True
    license_info = repo.get("license") or {}
    if isinstance(license_info, dict):
        enriched["license"] = license_info.get("spdx_id") or license_info.get("key") or ""
    return enriched


def enrich_repos(
    repos: list[dict[str, Any]],
    token: str,
    include_readme: bool,
    readme_chars: int,
    include_topics: bool,
) -> list[dict[str, Any]]:
    if not repos:
        return []
    workers = min(8, len(repos))
    worker = partial(
        enrich_repo,
        token=token,
        include_readme=include_readme,
        readme_chars=readme_chars,
        include_topics=include_topics,
    )
    with ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(worker, repos))


def format_markdown(repos: list[dict[str, Any]], query: str) -> str:
    lines = [
        "# GitHub repository summaries",
        "",
        f"**{len(repos)} results** · Query: `{query}`",
        "",
    ]
    for i, repo in enumerate(repos, start=1):
        name = repo.get("fullName", "unknown")
        stars = repo.get("stargazersCount", 0)
        forks = repo.get("forksCount", 0)
        language = repo.get("language") or "—"
        url = repo.get("url", "")
        desc = repo.get("description") or "No description."
        lines.extend(
            [
                f"## {i}. [{name}]({url})",
                "",
                f"- **Stars:** {stars:,} | **Forks:** {forks:,} | **Language:** {language}",
            ]
        )
        license_name = repo.get("license")
        if license_name:
            lines.append(f"- **License:** {license_name}")
        topics = repo.get("topics") or []
        if topics:
            lines.append(f"- **Topics:** {', '.join(topics)}")
        created = repo.get("createdAt")
        if created:
            lines.append(f"- **Created:** {created[:10]}")
        updated = repo.get("pushedAt") or repo.get("updatedAt")
        if updated:
            lines.append(f"- **Last push:** {updated[:10]}")
        lines.extend(["", f"**GitHub description:** {desc}", ""])
        readme = repo.get("readme")
        if readme:
            truncated = repo.get("readmeTruncated")
            label = "**README:**"
            if truncated:
                label += " *(truncated)*"
            lines.extend([label, "", "```markdown", readme, "```", ""])
        elif repo.get("readmeMissing"):
            lines.append("*No README found via API.*")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def format_table(repos: list[dict[str, Any]], show_dates: bool) -> str:
    if show_dates:
        headers = ["#", "Repository", "Stars", "Lang", "Created", "Pushed", "Description"]
    else:
        headers = ["#", "Repository", "Stars", "Lang", "Description"]
    rows: list[list[str]] = []
    for i, repo in enumerate(repos, start=1):
        desc = (repo.get("description") or "").replace("\n", " ")
        if len(desc) > 72:
            desc = desc[:69].rstrip() + "…"
        row = [
            str(i),
            repo.get("fullName", ""),
            str(repo.get("stargazersCount", 0)),
            repo.get("language") or "",
        ]
        if show_dates:
            row.extend(
                [
                    (repo.get("createdAt") or "")[:10],
                    (repo.get("pushedAt") or repo.get("updatedAt") or "")[:10],
                ]
            )
        row.append(desc)
        rows.append(row)

    widths = [len(h) for h in headers]
    for row in rows:
        for idx, cell in enumerate(row):
            widths[idx] = max(widths[idx], len(cell))
    fmt = "  ".join(f"{{:{w}}}" for w in widths)
    lines = [fmt.format(*headers), fmt.format(*(["-" * w for w in widths]))]
    for row in rows:
        lines.append(fmt.format(*row))
    return "\n".join(lines)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Search GitHub repos and print metadata summaries (no cloning). "
            "With no filters: top 10 repos created in the last 7 days by stars."
        ),
    )
    parser.add_argument(
        "query",
        nargs="?",
        default="",
        help="Free-text search terms (optional if using date/star flags)",
    )
    parser.add_argument("--language", "-l", help="Filter by primary language")
    parser.add_argument("--topic", "-t", action="append", default=[], help="Filter by topic")
    parser.add_argument("--min-stars", type=int, help="Minimum star count")
    parser.add_argument("--max-stars", type=int, help="Maximum star count")
    parser.add_argument(
        "--created-after",
        help="Only repos created after this date (YYYY-MM-DD). Matches GitHub web created:>DATE",
    )
    parser.add_argument(
        "--pushed-after",
        help="Only repos pushed after this date (YYYY-MM-DD). Old repos with recent commits qualify",
    )
    parser.add_argument(
        "--sort",
        choices=["stars", "forks", "updated", "help-wanted-issues"],
        default="stars",
        help="Sort order (default: stars)",
    )
    parser.add_argument(
        "--order",
        choices=["asc", "desc"],
        default="desc",
        help="Sort direction (default: desc)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=argparse.SUPPRESS,
        help=f"Max repos (default: {DEFAULT_WEEKLY_LIMIT} weekly / {DEFAULT_LIMIT} custom)",
    )
    parser.add_argument(
        "--include-readme",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Fetch full README via API for agent summarization (default: on)",
    )
    parser.add_argument(
        "--readme-chars",
        type=int,
        default=argparse.SUPPRESS,
        help=(
            f"Max README characters per repo "
            f"(default: {DEFAULT_WEEKLY_README_CHARS} weekly / {DEFAULT_README_CHARS} custom)"
        ),
    )
    parser.add_argument(
        "--include-topics",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Fetch repo topics via API (default: on)",
    )
    parser.add_argument(
        "--fork",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Include forked repositories (default: exclude)",
    )
    parser.add_argument(
        "--archived",
        action=argparse.BooleanOptionalAction,
        default=False,
        help="Include archived repositories (default: exclude)",
    )
    parser.add_argument(
        "--format",
        choices=["markdown", "json", "table"],
        default="markdown",
        help="Output format (default: markdown)",
    )
    parser.add_argument("--output", "-o", help="Write output to file")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    argv = list(argv) if argv is not None else sys.argv[1:]
    args = parse_args(argv)
    weekly_mode = resolve_mode_defaults(args)
    if args.limit < 1 or args.limit > 100:
        print("error: --limit must be between 1 and 100", file=sys.stderr)
        return 2

    for label, value in (
        ("--created-after", args.created_after),
        ("--pushed-after", args.pushed_after),
    ):
        if value:
            try:
                _parse_day(value)
            except ValueError:
                print(f"error: {label} must be YYYY-MM-DD", file=sys.stderr)
                return 2

    if args.readme_chars < 500 or args.readme_chars > 50000:
        print("error: --readme-chars must be between 500 and 50000", file=sys.stderr)
        return 2

    try:
        token = auth_token()
        plan = plan_search(args)
        repos = search_repos(args, plan)
        repos = filter_repos(repos, plan)[: plan.result_limit]
        enriched = enrich_repos(
            repos,
            token,
            include_readme=args.include_readme,
            readme_chars=args.readme_chars,
            include_topics=args.include_topics,
        )
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(f"# query: {plan.gh_query}", file=sys.stderr)
    print(f"# results: {len(enriched)}", file=sys.stderr)
    if weekly_mode:
        print(
            f"# mode: weekly — top {args.limit} repos created since "
            f"{args.created_after} (last {DEFAULT_WEEKLY_DAYS} days), sorted by stars",
            file=sys.stderr,
        )

    show_dates = bool(plan.created_after or plan.pushed_after)

    if args.format == "json":
        payload = {"query": plan.gh_query, "count": len(enriched), "repos": enriched}
        output = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    elif args.format == "table":
        output = format_table(enriched, show_dates=show_dates) + "\n"
    else:
        output = format_markdown(enriched, plan.gh_query)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as handle:
            handle.write(output)
        print(f"Wrote {len(enriched)} repos to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
