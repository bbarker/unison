#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/unison/share-api-fallback.sh <command> [args]

Fallback helper for Share lookups when MCP is unavailable.

Commands:
  search <query>
      Search Share entities using /search.

  project <@owner/project>
      Fetch project metadata from /ucm/v1/projects/project.

  readme <owner> <project>
      Fetch project README from /users/<owner>/projects/<project>/readme.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Missing required dependency: curl" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing required dependency: jq" >&2
  exit 1
fi

api_base="${UNISON_SHARE_API_BASE:-https://api.unison-lang.org}"
command="$1"
shift

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

case "$command" in
  search)
    if [[ $# -ne 1 ]]; then
      usage
      exit 2
    fi
    query="$1"
    enc_query="$(urlencode "$query")"
    curl -fsSL "$api_base/search?query=$enc_query" | jq '.'
    ;;

  project)
    if [[ $# -ne 1 ]]; then
      usage
      exit 2
    fi
    project_ref="$1"
    if [[ "$project_ref" != @*/* ]]; then
      echo "Expected project ref format: @owner/project" >&2
      exit 2
    fi
    enc_name="$(urlencode "$project_ref")"
    curl -fsSL "$api_base/ucm/v1/projects/project?name=$enc_name" | jq '.'
    ;;

  readme)
    if [[ $# -ne 2 ]]; then
      usage
      exit 2
    fi
    owner="$1"
    project="$2"
    curl -fsSL "$api_base/users/$owner/projects/$project/readme" | jq '.'
    ;;

  *)
    usage
    exit 2
    ;;
esac
