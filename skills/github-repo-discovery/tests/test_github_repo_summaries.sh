#!/usr/bin/env bash
# Offline tests for github-repo-summaries.sh helpers (no network).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../scripts/github-repo-summaries.sh"

pass=0
fail=0

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass=$((pass + 1))
    echo "ok - ${label}"
  else
    fail=$((fail + 1))
    echo "fail - ${label}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
  fi
}

QUERY=""
CREATED_AFTER=""
PUSHED_AFTER=""
MIN_STARS=""
MAX_STARS=""
LANGUAGE=""
TOPICS=()
LIMIT=""
README_CHARS=""

resolve_mode_defaults
assert_eq "weekly limit default" "10" "$LIMIT"
assert_eq "weekly readme chars default" "3500" "$README_CHARS"
assert_eq "weekly created-after set" "1" "$([[ -n "$CREATED_AFTER" ]] && echo 1 || echo 0)"

QUERY="rag"
CREATED_AFTER=""
LIMIT=""
README_CHARS=""
resolve_mode_defaults
assert_eq "custom limit default" "20" "$LIMIT"
assert_eq "custom readme chars default" "10000" "$README_CHARS"

QUERY=""
CREATED_AFTER="2026-05-01"
PUSHED_AFTER=""
MIN_STARS="100"
LIMIT="10"
build_query="$(build_search_query)"
assert_eq "date filter omits stars in query" "1" "$([[ "$build_query" == *"created:"* && "$build_query" != *"stars:"* ]] && echo 1 || echo 0)"

MIN_STARS="500"
CREATED_AFTER=""
build_query="$(build_search_query)"
assert_eq "no date includes stars in query" "1" "$([[ "$build_query" == *"stars:>=500"* ]] && echo 1 || echo 0)"

truncated="$(truncate_readme "$(printf 'a%.0s' {1..100})" 50)"
assert_eq "truncate readme adds marker" "1" "$([[ "$truncated" == *"README truncated"* ]] && echo 1 || echo 0)"

echo
echo "${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
