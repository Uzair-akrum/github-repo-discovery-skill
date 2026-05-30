#!/usr/bin/env bash
# Search GitHub repositories and emit metadata summaries (no cloning).
# Requires: curl and GITHUB_TOKEN (or gh auth token when gh is installed).

set -euo pipefail

FIELD_SEP=$'\x1e'

GITHUB_API="https://api.github.com"
OVERFETCH_FACTOR=5
DEFAULT_LIMIT=20
DEFAULT_README_CHARS=10000
DEFAULT_WEEKLY_LIMIT=10
DEFAULT_WEEKLY_DAYS=7
DEFAULT_WEEKLY_README_CHARS=3500

QUERY=""
CREATED_AFTER=""
PUSHED_AFTER=""
MIN_STARS=""
MAX_STARS=""
LANGUAGE=""
SORT="stars"
ORDER="desc"
LIMIT=""
README_CHARS=""
INCLUDE_README=1
INCLUDE_TOPICS=1
INCLUDE_FORK=0
INCLUDE_ARCHIVED=0
FORMAT="markdown"
OUTPUT=""
TOPICS=()
WEEKLY_MODE=0

usage() {
  cat <<'EOF'
Search GitHub repos and print metadata summaries (no cloning).
With no filters: top 10 repos created in the last 7 days by stars.

Usage:
  github-repo-summaries.sh [query] [options]

Options:
  --language, -l LANG          Filter by primary language
  --topic, -t TOPIC            Filter by topic (repeatable)
  --min-stars N                Minimum star count
  --max-stars N                Maximum star count
  --created-after YYYY-MM-DD   Repos created after date
  --pushed-after YYYY-MM-DD    Repos pushed after date
  --sort ORDER                 stars|forks|updated|help-wanted-issues (default: stars)
  --order DIR                  asc|desc (default: desc)
  --limit N                    Max repos, 1-100 (default: 10 weekly / 20 custom)
  --include-readme             Fetch README via API (default: on)
  --no-include-readme          Skip README fetch
  --readme-chars N             Max README chars per repo
  --include-topics             Fetch repo topics (default: on)
  --no-include-topics          Skip topics fetch
  --fork                       Include forks (default: exclude)
  --no-fork                    Exclude forks
  --archived                   Include archived repos (default: exclude)
  --no-archived                Exclude archived repos
  --format FMT                 markdown|json|table (default: markdown)
  -o, --output FILE            Write output to file
  -h, --help                   Show this help
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

week_ago_date() {
  if date -v-1d >/dev/null 2>&1; then
    date -v-"${DEFAULT_WEEKLY_DAYS}"d +%Y-%m-%d
  else
    date -d "${DEFAULT_WEEKLY_DAYS} days ago" +%Y-%m-%d
  fi
}

query_has_qualifier() {
  local query="$1"
  local prefix="$2"
  [[ "$query" =~ (^|[[:space:]])${prefix}: ]]
}

has_date_filter() {
  [[ -n "$CREATED_AFTER" || -n "$PUSHED_AFTER" ]] && return 0
  query_has_qualifier "$QUERY" "created" && return 0
  query_has_qualifier "$QUERY" "pushed" && return 0
  return 1
}

has_explicit_filters() {
  [[ -n "$QUERY" || -n "$CREATED_AFTER" || -n "$PUSHED_AFTER" || -n "$MIN_STARS" || -n "$MAX_STARS" || ${#TOPICS[@]} -gt 0 || -n "$LANGUAGE" ]]
}

resolve_mode_defaults() {
  if has_explicit_filters; then
    WEEKLY_MODE=0
    LIMIT="${LIMIT:-$DEFAULT_LIMIT}"
    README_CHARS="${README_CHARS:-$DEFAULT_README_CHARS}"
    return
  fi
  WEEKLY_MODE=1
  CREATED_AFTER="$(week_ago_date)"
  LIMIT="${LIMIT:-$DEFAULT_WEEKLY_LIMIT}"
  README_CHARS="${README_CHARS:-$DEFAULT_WEEKLY_README_CHARS}"
}

auth_token() {
  local token=""
  for var in GITHUB_TOKEN GITHUB_ACCESS_TOKEN GH_TOKEN; do
    token="${!var:-}"
    if [[ -n "$token" ]]; then
      printf '%s' "$token"
      return 0
    fi
  done
  if command -v gh >/dev/null 2>&1; then
    token="$(gh auth token 2>/dev/null || true)"
    if [[ -n "$token" ]]; then
      printf '%s' "$token"
      return 0
    fi
  fi
  die "No GitHub auth found. Set GITHUB_TOKEN or run \`gh auth login\`."
}

json_string() {
  local blob="$1"
  local key="$2"
  local match
  match="$(printf '%s' "$blob" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"\\]\\|\\.\)*\"" | head -1 || true)"
  [[ -n "$match" ]] || return 1
  sed -n 's/.*"'"${key}"'"[[:space:]]*:[[:space:]]*"\(.*\)"/\1/p' <<<"$match" | sed 's/\\"/"/g; s/\\n/\n/g; s/\\\\/\\/g'
}

json_number() {
  local blob="$1"
  local key="$2"
  local match
  match="$(printf '%s' "$blob" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[0-9][0-9]*" | head -1 || true)"
  [[ -n "$match" ]] || return 1
  sed -n 's/.*"'"${key}"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' <<<"$match"
}

json_nullable_string() {
  local blob="$1"
  local key="$2"
  local match
  match="$(printf '%s' "$blob" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\\(null\\|\"\\([^\"\\]\\|\\.\)*\"\\)" | head -1 || true)"
  [[ -n "$match" ]] || return 1
  grep -q 'null' <<<"$match" && return 1
  json_string "$blob" "$key"
}

gh_api() {
  local path="$1"
  local token="$2"
  local tmp
  tmp="$(mktemp)"
  local code
  code="$(curl -sS -o "$tmp" -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "User-Agent: hermes-github-repo-discovery" \
    "${GITHUB_API}${path}")"
  if [[ "$code" == "200" || "$code" == "201" ]]; then
    cat "$tmp"
    rm -f "$tmp"
    return 0
  fi
  if [[ "$code" != "404" ]]; then
    echo "# warn: GitHub API ${path} failed (HTTP ${code})" >&2
  fi
  rm -f "$tmp"
  return 1
}

build_search_query() {
  local parts=()
  local q="$QUERY"
  if [[ -n "$q" ]]; then
    parts+=("$q")
  fi
  if [[ -n "$CREATED_AFTER" ]] && ! query_has_qualifier "$q" "created"; then
    parts+=("created:>${CREATED_AFTER}")
  fi
  if [[ -n "$PUSHED_AFTER" ]] && ! query_has_qualifier "$q" "pushed"; then
    parts+=("pushed:>${PUSHED_AFTER}")
  fi
  if has_date_filter; then
    :
  else
    if [[ -n "$MIN_STARS" ]] && ! query_has_qualifier "$q" "stars"; then
      parts+=("stars:>=${MIN_STARS}")
    fi
    if [[ -n "$MAX_STARS" ]] && ! query_has_qualifier "$q" "stars"; then
      parts+=("stars:<=${MAX_STARS}")
    fi
  fi
  if [[ "$INCLUDE_FORK" -eq 0 ]] && ! query_has_qualifier "$q" "fork"; then
    parts+=("fork:false")
  fi
  if [[ "$INCLUDE_ARCHIVED" -eq 0 ]] && ! query_has_qualifier "$q" "archived"; then
    parts+=("archived:false")
  fi
  if [[ -n "$LANGUAGE" ]]; then
    parts+=("language:${LANGUAGE}")
  fi
  for topic in "${TOPICS[@]}"; do
    parts+=("topic:${topic}")
  done
  if [[ ${#parts[@]} -eq 0 ]]; then
    printf '%s' "stars:>100"
  else
    local IFS=' '
    printf '%s' "${parts[*]}"
  fi
}

search_repos() {
  local gh_query="$1"
  local fetch_limit="$2"
  local token="$3"
  curl -sS -G "${GITHUB_API}/search/repositories" \
    --data-urlencode "q=${gh_query}" \
    --data-urlencode "sort=${SORT}" \
    --data-urlencode "order=${ORDER}" \
    --data-urlencode "per_page=${fetch_limit}" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "User-Agent: hermes-github-repo-discovery"
}

search_repo_names() {
  local json="$1"
  printf '%s' "$json" | grep -o '"full_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/'
}

fetch_repo_item() {
  local full_name="$1"
  local token="$2"
  gh_api "/repos/${full_name}" "$token" || true
}

passes_filters() {
  local item="$1"
  local stars created pushed
  stars="$(json_number "$item" stargazers_count || echo 0)"
  if [[ -n "$MIN_STARS" && "$stars" -lt "$MIN_STARS" ]]; then
    return 1
  fi
  if [[ -n "$MAX_STARS" && "$stars" -gt "$MAX_STARS" ]]; then
    return 1
  fi
  if [[ -n "$CREATED_AFTER" ]]; then
    created="$(json_string "$item" created_at || true)"
    [[ -n "$created" && "$created" > "${CREATED_AFTER}T00:00:00Z" ]] || return 1
  fi
  if [[ -n "$PUSHED_AFTER" ]]; then
    pushed="$(json_nullable_string "$item" pushed_at || json_nullable_string "$item" updated_at || true)"
    [[ -n "$pushed" && "$pushed" > "${PUSHED_AFTER}T00:00:00Z" ]] || return 1
  fi
  return 0
}

clean_readme() {
  local text="$1"
  local line stripped cleaned=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    stripped="${line#"${line%%[![:space:]]*}"}"
    stripped="${stripped%"${stripped##*[![:space:]]}"}"
    if [[ -z "$stripped" ]]; then
      cleaned+=$'\n'
      continue
    fi
    case "$stripped" in
      "<p align"* | "</p>" | "<img"* | "<a href"*) continue ;;
      '![*](*)'*) continue ;;
      '[![*](*)](*)'*) continue ;;
    esac
    cleaned+="${line%"${line##*[![:space:]]}"}"$'\n'
  done <<< "$text"
  printf '%s' "$cleaned" | sed -E '/./,$!d; /^$/N; /^\n$/D'
}

truncate_readme() {
  local text="$1"
  local max_chars="$2"
  if ((${#text} <= max_chars)); then
    printf '%s' "$text"
    return
  fi
  local chunk="${text:0:max_chars}"
  local cut="${chunk%%$'\n\n'*}"
  if ((${#cut} > max_chars / 2)); then
    chunk="$cut"
  fi
  chunk="${chunk%"${chunk##*[![:space:]]}"}"
  printf '%s\n\n… (README truncated)' "$chunk"
}

decode_base64() {
  local data="$1"
  if printf '%s' "dGVzdA==" | base64 -d >/dev/null 2>&1; then
    printf '%s' "$data" | base64 -d 2>/dev/null && return 0
  fi
  printf '%s' "$data" | base64 -D 2>/dev/null
}

fetch_readme() {
  local full_name="$1"
  local token="$2"
  local max_chars="$3"
  local payload content text cleaned
  payload="$(gh_api "/repos/${full_name}/readme" "$token" || true)"
  [[ -n "$payload" ]] || return 1
  content="$(printf '%s' "$payload" | tr -d '\n' | sed -E 's/^.*"content"[[:space:]]*:[[:space:]]*"//; s/","encoding".*$//; s/\\n//g')"
  [[ -n "$content" ]] || return 1
  text="$(decode_base64 "$content" || true)"
  [[ -n "$text" ]] || return 1
  cleaned="$(clean_readme "$text")"
  [[ -n "$cleaned" ]] || return 1
  truncate_readme "$cleaned" "$max_chars"
}

fetch_topics() {
  local full_name="$1"
  local token="$2"
  local payload
  payload="$(gh_api "/repos/${full_name}/topics" "$token" || true)"
  [[ -n "$payload" ]] || return 0
  printf '%s' "$payload" | grep -o '"names"[[:space:]]*:\[[^]]*\]' | sed 's/"names"[[:space:]]*:\[//; s/\]//; s/"//g'
}

format_markdown() {
  local gh_query="$1"
  shift
  local items=("$@")
  echo "# GitHub repository summaries"
  echo
  echo "**${#items[@]} results** · Query: \`${gh_query}\`"
  echo
  local i=0
  for entry in "${items[@]}"; do
    i=$((i + 1))
    IFS="$FIELD_SEP" read -r name stars forks language url desc license topics created updated readme_b64 readme_missing readme_truncated <<<"$entry"
    local readme=""
    if [[ -n "$readme_b64" ]]; then
      readme="$(printf '%s' "$readme_b64" | base64 -d 2>/dev/null || true)"
    fi
    echo "## ${i}. [${name}](${url})"
    echo
    echo "- **Stars:** ${stars} | **Forks:** ${forks} | **Language:** ${language:-—}"
    [[ -n "$license" ]] && echo "- **License:** ${license}"
    [[ -n "$topics" ]] && echo "- **Topics:** ${topics}"
    [[ -n "$created" ]] && echo "- **Created:** ${created}"
    [[ -n "$updated" ]] && echo "- **Last push:** ${updated}"
    echo
    echo "**GitHub description:** ${desc:-No description.}"
    echo
    if [[ -n "$readme" ]]; then
      echo -n "**README:**"
      [[ "$readme_truncated" == "1" ]] && echo -n " *(truncated)*"
      echo
      echo
      echo '```markdown'
      echo "$readme"
      echo '```'
      echo
    elif [[ "$readme_missing" == "1" ]]; then
      echo "*No README found via API.*"
      echo
    fi
  done
}

format_table() {
  local show_dates="$1"
  shift
  local items=("$@")
  if [[ "$show_dates" -eq 1 ]]; then
    printf '%-3s  %-40s  %-8s  %-8s  %-10s  %-10s  %s\n' "#" "Repository" "Stars" "Lang" "Created" "Pushed" "Description"
    printf '%-3s  %-40s  %-8s  %-8s  %-10s  %-10s  %s\n' "---" "----------" "-----" "----" "-------" "------" "-----------"
  else
    printf '%-3s  %-40s  %-8s  %-8s  %s\n' "#" "Repository" "Stars" "Lang" "Description"
    printf '%-3s  %-40s  %-8s  %-8s  %s\n' "---" "----------" "-----" "----" "-----------"
  fi
  local i=0
  for entry in "${items[@]}"; do
    i=$((i + 1))
    IFS="$FIELD_SEP" read -r name stars forks language url desc license topics created updated readme_b64 readme_missing readme_truncated <<<"$entry"
    local readme=""
    if [[ -n "$readme_b64" ]]; then
      readme="$(printf '%s' "$readme_b64" | base64 -d 2>/dev/null || true)"
    fi
    local short_desc="${desc:-}"
    short_desc="${short_desc//$'\n'/ }"
    if ((${#short_desc} > 72)); then
      short_desc="${short_desc:0:69}…"
    fi
    if [[ "$show_dates" -eq 1 ]]; then
      printf '%-3s  %-40s  %-8s  %-8s  %-10s  %-10s  %s\n' "$i" "$name" "$stars" "${language:-}" "${created:-}" "${updated:-}" "$short_desc"
    else
      printf '%-3s  %-40s  %-8s  %-8s  %s\n' "$i" "$name" "$stars" "${language:-}" "$short_desc"
    fi
  done
}

enrich_item() {
  local item="$1"
  local token="$2"
  local name stars forks language url desc license topics="" created updated readme="" readme_missing=0 readme_truncated=0
  name="$(json_string "$item" full_name || true)"
  stars="$(json_number "$item" stargazers_count || echo 0)"
  forks="$(json_number "$item" forks_count || echo 0)"
  language="$(json_nullable_string "$item" language || true)"
  url="https://github.com/${name}"
  desc="$(json_nullable_string "$item" description || true)"
  license="$(printf '%s' "$item" | grep -o '"spdx_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)"
  created="$(json_nullable_string "$item" created_at | cut -c1-10 || true)"
  updated="$(json_nullable_string "$item" pushed_at | cut -c1-10 || true)"
  if [[ -z "$updated" ]]; then
    updated="$(json_nullable_string "$item" updated_at | cut -c1-10 || true)"
  fi
  if [[ "$INCLUDE_TOPICS" -eq 1 && -n "$name" ]]; then
    topics="$(fetch_topics "$name" "$token" || true)"
  fi
  if [[ "$INCLUDE_README" -eq 1 && -n "$name" ]]; then
    if readme="$(fetch_readme "$name" "$token" "$README_CHARS")"; then
      if [[ "$readme" == *$'\n\n… (README truncated)' ]]; then
        readme_truncated=1
      fi
    else
      readme_missing=1
      readme=""
    fi
  else
    readme=""
  fi
  local readme_b64=""
  if [[ -n "$readme" ]]; then
    readme_b64="$(printf '%s' "$readme" | base64 | tr -d '\n')"
  fi
  printf '%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s\036%s' \
    "$name" "$stars" "$forks" "$language" "$url" "$desc" "$license" "$topics" "$created" "$updated" \
    "$readme_b64" "$readme_missing" "$readme_truncated"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --language|-l) LANGUAGE="$2"; shift 2 ;;
      --topic|-t) TOPICS+=("$2"); shift 2 ;;
      --min-stars) MIN_STARS="$2"; shift 2 ;;
      --max-stars) MAX_STARS="$2"; shift 2 ;;
      --created-after) CREATED_AFTER="$2"; shift 2 ;;
      --pushed-after) PUSHED_AFTER="$2"; shift 2 ;;
      --sort) SORT="$2"; shift 2 ;;
      --order) ORDER="$2"; shift 2 ;;
      --limit) LIMIT="$2"; shift 2 ;;
      --readme-chars) README_CHARS="$2"; shift 2 ;;
      --include-readme) INCLUDE_README=1; shift ;;
      --no-include-readme) INCLUDE_README=0; shift ;;
      --include-topics) INCLUDE_TOPICS=1; shift ;;
      --no-include-topics) INCLUDE_TOPICS=0; shift ;;
      --fork) INCLUDE_FORK=1; shift ;;
      --no-fork) INCLUDE_FORK=0; shift ;;
      --archived) INCLUDE_ARCHIVED=1; shift ;;
      --no-archived) INCLUDE_ARCHIVED=0; shift ;;
      --format) FORMAT="$2"; shift 2 ;;
      -o|--output) OUTPUT="$2"; shift 2 ;;
      --) shift; QUERY="$*"; break ;;
      -*) die "unknown option: $1" ;;
      *)
        if [[ -z "$QUERY" ]]; then
          QUERY="$1"
        else
          QUERY+=" $1"
        fi
        shift
        ;;
    esac
  done
}

main() {
  need_cmd curl

  if [[ $# -eq 0 ]]; then
    :
  elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
  else
    parse_args "$@"
  fi

  resolve_mode_defaults

  [[ "$LIMIT" =~ ^[0-9]+$ ]] || die "--limit must be a number"
  ((LIMIT >= 1 && LIMIT <= 100)) || die "--limit must be between 1 and 100"
  [[ "$README_CHARS" =~ ^[0-9]+$ ]] || die "--readme-chars must be a number"
  ((README_CHARS >= 500 && README_CHARS <= 50000)) || die "--readme-chars must be between 500 and 50000"

  for label_value in "created-after:${CREATED_AFTER}" "pushed-after:${PUSHED_AFTER}"; do
    local label="${label_value%%:*}"
    local value="${label_value#*:}"
    if [[ -n "$value" && ! "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      die "--${label} must be YYYY-MM-DD"
    fi
  done

  local token gh_query fetch_limit search_json item
  token="$(auth_token)"
  gh_query="$(build_search_query)"
  fetch_limit="$LIMIT"
  if has_date_filter && [[ -n "$MIN_STARS" ]]; then
    fetch_limit=$((LIMIT * OVERFETCH_FACTOR))
    ((fetch_limit > 100)) && fetch_limit=100
    ((fetch_limit < LIMIT)) && fetch_limit="$LIMIT"
  fi

  search_json="$(search_repos "$gh_query" "$fetch_limit" "$token")"
  local -a rows=()
  local full_name item
  while IFS= read -r full_name; do
    [[ -n "$full_name" ]] || continue
    item="$(fetch_repo_item "$full_name" "$token")"
    [[ -n "$item" ]] || continue
    passes_filters "$item" || continue
    rows+=("$(enrich_item "$item" "$token")")
    ((${#rows[@]} >= LIMIT)) && break
  done < <(search_repo_names "$search_json")

  echo "# query: ${gh_query}" >&2
  echo "# results: ${#rows[@]}" >&2
  if [[ "$WEEKLY_MODE" -eq 1 ]]; then
    echo "# mode: weekly — top ${LIMIT} repos created since ${CREATED_AFTER} (last ${DEFAULT_WEEKLY_DAYS} days), sorted by stars" >&2
  fi

  local show_dates=0
  if [[ -n "$CREATED_AFTER" || -n "$PUSHED_AFTER" ]]; then
    show_dates=1
  fi

  local output=""
  case "$FORMAT" in
    json)
      output="# GitHub repository summaries (json)\n{\"query\":\"${gh_query}\",\"count\":${#rows[@]},\"repos\":["
      local first=1 entry name
      for entry in "${rows[@]}"; do
        IFS="$FIELD_SEP" read -r name stars forks language url desc license topics created updated readme_b64 readme_missing readme_truncated <<<"$entry"
    local readme=""
    if [[ -n "$readme_b64" ]]; then
      readme="$(printf '%s' "$readme_b64" | base64 -d 2>/dev/null || true)"
    fi
        [[ "$first" -eq 1 ]] || output+=","
        first=0
        output+="\n  {\"full_name\":\"${name}\",\"stargazers_count\":${stars},\"forks_count\":${forks},\"language\":\"${language}\",\"html_url\":\"${url}\",\"description\":\"${desc}\",\"license\":\"${license}\",\"topics\":\"${topics}\",\"created_at\":\"${created}\",\"updated_at\":\"${updated}\",\"readme_missing\":${readme_missing},\"readme_truncated\":${readme_truncated}}"
      done
      output+="\n]}\n"
      printf '%b' "$output"
      ;;
    table)
      output="$(format_table "$show_dates" "${rows[@]}")"
      ;;
    markdown)
      output="$(format_markdown "$gh_query" "${rows[@]}")"
      ;;
    *) die "unknown format: $FORMAT" ;;
  esac

  if [[ -n "$OUTPUT" ]]; then
    printf '%s\n' "$output" >"$OUTPUT"
    echo "Wrote ${#rows[@]} repos to ${OUTPUT}" >&2
  else
    printf '%s\n' "$output"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
