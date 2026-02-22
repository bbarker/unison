#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/unison/reference-all-transcripts.sh [options]

Run a large transcript sweep using the all-transcripts profile.
This is intended to build or check parser-oriented corpus parity at scale.

Options:
  --binary PATH           Unison binary to run (default: result/bin/unison)
  --work-dir DIR          Working output directory (default: timestamped under .run/)
  --baseline-dir DIR      Baseline directory (default: scripts/unison/baselines/all-transcripts)
  --max-cases N           Limit number of transcript cases (default: unlimited)
  --case-timeout-seconds N
                          Per-case timeout in seconds; 0 defers to
                          reference-corpus defaults (all-transcripts: 120)
  --update-baseline       Update baseline from this run
  --check-baseline        Compare this run against baseline
  -h, --help              Show this help
USAGE
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
binary="$repo_root/result/bin/unison"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
work_dir=""
baseline_dir="$repo_root/scripts/unison/baselines/all-transcripts"
max_cases=0
case_timeout_seconds=0
update_baseline=0
check_baseline=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary)
      binary="$2"
      shift 2
      ;;
    --work-dir)
      work_dir="$2"
      shift 2
      ;;
    --baseline-dir)
      baseline_dir="$2"
      shift 2
      ;;
    --max-cases)
      max_cases="$2"
      shift 2
      ;;
    --case-timeout-seconds)
      case_timeout_seconds="$2"
      shift 2
      ;;
    --update-baseline)
      update_baseline=1
      shift
      ;;
    --check-baseline)
      check_baseline=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$work_dir" ]]; then
  work_dir="$repo_root/.run/unison-reference/all-transcripts/$timestamp"
fi

if [[ "$update_baseline" -eq 0 && "$check_baseline" -eq 0 && -d "$baseline_dir" ]]; then
  check_baseline=1
fi

if [[ "$update_baseline" -eq 0 && "$check_baseline" -eq 0 && ! -d "$baseline_dir" ]]; then
  echo "No baseline found at $baseline_dir; running in heuristic expected-exit mode."
  echo "Tip: run with --update-baseline (using result/bin/unison) to enable stable delta checks."
fi

cmd=(
  "$repo_root/scripts/unison/reference-corpus.sh"
  --binary "$binary"
  --profile all-transcripts
  --work-dir "$work_dir"
  --baseline-dir "$baseline_dir"
  --max-cases "$max_cases"
  --case-timeout-seconds "$case_timeout_seconds"
)

if [[ "$update_baseline" -eq 1 ]]; then
  cmd+=(--update-baseline)
fi
if [[ "$check_baseline" -eq 1 ]]; then
  cmd+=(--check-baseline)
fi

"${cmd[@]}"

summary_file="$work_dir/normalized/all-transcripts-summary.txt"
map_file="$work_dir/normalized/all-transcripts-map.tsv"
mismatch_file="$work_dir/normalized/all-transcripts-mismatches.txt"

echo ""
echo "All-transcripts artifacts:"
echo "  summary:  $summary_file"
echo "  case map: $map_file"
echo "  mismatches: $mismatch_file"

if [[ -f "$summary_file" ]]; then
  echo ""
  echo "Summary:"
  cat "$summary_file"
fi
