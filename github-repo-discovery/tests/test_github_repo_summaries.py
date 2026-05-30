"""Tests for github-repo-summaries pure functions (no network)."""

from __future__ import annotations

import argparse
import importlib.util
import sys
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "github-repo-summaries.py"
_spec = importlib.util.spec_from_file_location("github_repo_summaries", _SCRIPT)
assert _spec and _spec.loader
_mod = importlib.util.module_from_spec(_spec)
sys.modules["github_repo_summaries"] = _mod
_spec.loader.exec_module(_mod)

SearchPlan = _mod.SearchPlan
clean_readme = _mod.clean_readme
filter_repos = _mod.filter_repos
plan_search = _mod.plan_search
resolve_mode_defaults = _mod.resolve_mode_defaults
truncate_readme = _mod.truncate_readme


def _args(**kwargs: object) -> argparse.Namespace:
    defaults: dict[str, object] = {
        "query": "",
        "created_after": None,
        "pushed_after": None,
        "min_stars": None,
        "max_stars": None,
        "topic": [],
        "language": None,
        "fork": False,
        "archived": False,
        "sort": "stars",
        "order": "desc",
    }
    defaults.update(kwargs)
    return argparse.Namespace(**defaults)


class ResolveModeDefaultsTests(unittest.TestCase):
    def test_weekly_mode_applies_defaults(self) -> None:
        args = _args()
        weekly = resolve_mode_defaults(args)
        self.assertTrue(weekly)
        self.assertEqual(args.limit, 10)
        self.assertEqual(args.readme_chars, 3500)
        self.assertIsNotNone(args.created_after)

    def test_weekly_mode_respects_explicit_limit(self) -> None:
        args = _args(limit=5)
        weekly = resolve_mode_defaults(args)
        self.assertTrue(weekly)
        self.assertEqual(args.limit, 5)
        self.assertEqual(args.readme_chars, 3500)

    def test_custom_mode_with_query(self) -> None:
        args = _args(query="rag")
        weekly = resolve_mode_defaults(args)
        self.assertFalse(weekly)
        self.assertEqual(args.limit, 20)
        self.assertEqual(args.readme_chars, 10000)


class PlanSearchTests(unittest.TestCase):
    def test_date_filter_omits_stars_from_gh_query(self) -> None:
        args = _args(created_after="2026-05-01", min_stars=100, limit=10)
        plan = plan_search(args)
        self.assertIn("created:>2026-05-01", plan.gh_query)
        self.assertNotIn("stars:", plan.gh_query)
        self.assertEqual(plan.fetch_limit, 50)

    def test_no_date_includes_stars_in_gh_query(self) -> None:
        args = _args(min_stars=500, limit=10)
        plan = plan_search(args)
        self.assertIn("stars:>=500", plan.gh_query)
        self.assertEqual(plan.fetch_limit, 10)


class FilterReposTests(unittest.TestCase):
    def test_min_stars_filter(self) -> None:
        plan = SearchPlan("q", 20, 10, 100, None, None, None)
        repos = [{"stargazersCount": 50}, {"stargazersCount": 200}]
        filtered = filter_repos(repos, plan)
        self.assertEqual(len(filtered), 1)
        self.assertEqual(filtered[0]["stargazersCount"], 200)


class ReadmeUtilsTests(unittest.TestCase):
    def test_clean_readme_strips_badges(self) -> None:
        text = "![badge](x.png)\n\n# Title\n\nBody"
        cleaned = clean_readme(text)
        self.assertIn("# Title", cleaned)
        self.assertNotIn("badge", cleaned)

    def test_truncate_readme(self) -> None:
        text = "a" * 100
        chunk, truncated = truncate_readme(text, 50)
        self.assertTrue(truncated)
        self.assertLessEqual(len(chunk), 80)


if __name__ == "__main__":
    unittest.main()
