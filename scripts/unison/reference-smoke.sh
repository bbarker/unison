#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/unison/reference-smoke.sh [--binary PATH] [--out-dir DIR]

Runs a small reference suite against a Unison binary and writes artifacts for
differential testing.

Artifacts per step:
  <step>.cmd  - exact command line
  <step>.out  - stdout
  <step>.err  - stderr
  <step>.rc   - exit code
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
binary="$repo_root/result/bin/unison"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
out_dir="$repo_root/.run/unison-reference/$timestamp"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary)
      binary="$2"
      shift 2
      ;;
    --out-dir)
      out_dir="$2"
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

mkdir -p "$out_dir"
codebase_dir="$out_dir/codebase"
xdg_data_home="$out_dir/xdg-data"
mkdir -p "$xdg_data_home"

run_step() {
  local step="$1"
  shift

  local cmd_file="$out_dir/$step.cmd"
  local out_file="$out_dir/$step.out"
  local err_file="$out_dir/$step.err"
  local rc_file="$out_dir/$step.rc"

  printf '%q ' "$@" >"$cmd_file"
  printf '\n' >>"$cmd_file"

  set +e
  env XDG_DATA_HOME="$xdg_data_home" "$@" >"$out_file" 2>"$err_file"
  local rc=$?
  set -e

  echo "$rc" >"$rc_file"
  if [[ "$rc" -eq 0 ]]; then
    echo "PASS $step"
  else
    echo "FAIL $step (exit $rc)"
  fi
  return "$rc"
}

echo "Writing reference outputs to: $out_dir"
echo "Using binary: $binary"

failures=0
run_step help "$binary" --help || failures=$((failures + 1))
run_step version "$binary" version || failures=$((failures + 1))
run_step run_file \
  "$binary" \
  run.file \
  "$repo_root/unison-cli-integration/integration-tests/IntegrationTests/print.u" \
  print \
  --codebase-create \
  "$codebase_dir" || failures=$((failures + 1))
run_step transcript \
  "$binary" \
  transcript \
  "$repo_root/unison-cli-integration/integration-tests/IntegrationTests/transcript.md" \
  --codebase-create \
  "$codebase_dir" || failures=$((failures + 1))

echo "Completed with $failures failing step(s)."
if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
