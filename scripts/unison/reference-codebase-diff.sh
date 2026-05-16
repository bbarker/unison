#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/unison/reference-codebase-diff.sh [options]

Run codebase-adapter-focused differential checks against the reference binary.
This wraps the adapter corpus baseline check and enforces key adapter-output
expectations on normalized artifacts.

Options:
  --binary PATH         Unison binary to run (default: result/bin/unison)
  --work-dir DIR        Working output directory (default: timestamped under .run/)
  --baseline-dir DIR    Adapter baseline directory (default: scripts/unison/baselines/adapter)
  -h, --help            Show this help
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
binary="$repo_root/result/bin/unison"
baseline_dir="$repo_root/scripts/unison/baselines/adapter"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
work_dir="$repo_root/.run/unison-reference/codebase-diff/$timestamp"

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

if [[ ! -x "$binary" ]]; then
  echo "Binary is not executable: $binary" >&2
  exit 1
fi

corpus_work_dir="$work_dir/corpus"
normalized_dir="$corpus_work_dir/normalized"
case_manifest="$normalized_dir/cases.txt"

mkdir -p "$work_dir"

"$repo_root/scripts/unison/reference-corpus.sh" \
  --binary "$binary" \
  --profile adapter \
  --check-baseline \
  --baseline-dir "$baseline_dir" \
  --work-dir "$corpus_work_dir"

if [[ ! -f "$case_manifest" ]]; then
  echo "Missing adapter case manifest: $case_manifest" >&2
  exit 1
fi

required_cases=(
  transcript_adapter_pull
  transcript_adapter_lib_install
  transcript_adapter_add_update
  transcript_adapter_add_empty
  transcript_adapter_update_empty
)

for case_id in "${required_cases[@]}"; do
  if ! rg -Fxq "$case_id" "$case_manifest"; then
    echo "Missing adapter differential case in manifest: $case_id" >&2
    exit 1
  fi
done

expect_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "$file" ]]; then
    echo "Missing normalized output file: $file" >&2
    exit 1
  fi
  if ! rg -Fq -- "$pattern" "$file"; then
    echo "Pattern not found in $file: $pattern" >&2
    exit 1
  fi
}

fixture_corpus_dir="$corpus_work_dir/fixtures/scripts/unison/corpus"
expect_contains "$fixture_corpus_dir/adapter-pull.output.md" "Successfully pulled into"
expect_contains "$fixture_corpus_dir/adapter-lib-install.output.md" "I installed @unison/http/releases/"
expect_contains "$fixture_corpus_dir/adapter-add-update.output.md" "> add"
expect_contains "$fixture_corpus_dir/adapter-add-update.output.md" "> update"
expect_contains "$fixture_corpus_dir/adapter-add-empty.output.md" "There's nothing for me to add right now."
expect_contains "$fixture_corpus_dir/adapter-update-empty.output.md" "There's nothing for me to add right now."

for failure_case in transcript_adapter_add_empty transcript_adapter_update_empty; do
  failure_rc_file="$normalized_dir/$failure_case.rc"
  if [[ ! -f "$failure_rc_file" ]]; then
    echo "Missing rc file for $failure_case: $failure_rc_file" >&2
    exit 1
  fi
  failure_rc="$(tr -d '\n' <"$failure_rc_file")"
  if [[ "$failure_rc" != "1" ]]; then
    echo "Expected $failure_case rc=1, got: $failure_rc" >&2
    exit 1
  fi
done

echo "Codebase adapter differential scaffold check passed."
