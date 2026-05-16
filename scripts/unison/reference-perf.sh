#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/unison/reference-perf.sh [options]

Run repeated timing samples for curated Unison command/transcript cases and
optionally compare against a golden baseline with error bars.

Options:
  --binary PATH                Unison binary to run (default: result/bin/unison)
  --profile NAME               quick | core | extended (default: core)
  --samples N                  Measured samples per case (default: 20)
  --warmup N                   Warmup runs per case (default: 3)
  --work-dir DIR               Output directory (default: timestamped under .run/)
  --baseline-dir DIR           Baseline dir (default: scripts/unison/baselines/perf/<profile>)
  --benchmark-transcript PATH  Optional transcript case (for @mitchellwrosen/benchmark, etc.)
  --max-regression-pct PCT     Regression threshold percent (default: 10)
  --update-baseline            Write summary and samples to baseline dir
  --check-baseline             Compare current run vs baseline summary
  -h, --help                   Show help

Stats:
  - mean, stddev, stderr, and 95% confidence-interval half-width (ci95_ms)
  - baseline gate fails when both:
      1) percent regression > --max-regression-pct
      2) current lower CI bound > baseline upper CI bound
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
binary="$repo_root/result/bin/unison"
profile="core"
samples=20
warmup=3
max_regression_pct=10
benchmark_transcript=""
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
work_dir=""
baseline_dir=""
update_baseline=0
check_baseline=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary)
      binary="$2"
      shift 2
      ;;
    --profile)
      profile="$2"
      shift 2
      ;;
    --samples)
      samples="$2"
      shift 2
      ;;
    --warmup)
      warmup="$2"
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
    --benchmark-transcript)
      benchmark_transcript="$2"
      shift 2
      ;;
    --max-regression-pct)
      max_regression_pct="$2"
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

if [[ "$profile" != "quick" && "$profile" != "core" && "$profile" != "extended" ]]; then
  echo "Unsupported profile: $profile" >&2
  exit 2
fi

if ! [[ "$samples" =~ ^[0-9]+$ ]] || [[ "$samples" -lt 2 ]]; then
  echo "--samples must be an integer >= 2" >&2
  exit 2
fi

if ! [[ "$warmup" =~ ^[0-9]+$ ]]; then
  echo "--warmup must be a non-negative integer" >&2
  exit 2
fi

if [[ ! -x "$binary" ]]; then
  echo "Binary is not executable: $binary" >&2
  exit 1
fi

if [[ -n "$benchmark_transcript" && ! -f "$benchmark_transcript" ]]; then
  echo "--benchmark-transcript not found: $benchmark_transcript" >&2
  exit 1
fi

if [[ -z "$baseline_dir" ]]; then
  baseline_dir="$repo_root/scripts/unison/baselines/perf/$profile"
fi

if [[ -z "$work_dir" ]]; then
  work_dir="$repo_root/.run/unison-reference/perf/$profile/$timestamp"
fi

raw_dir="$work_dir/raw"
normalized_dir="$work_dir/normalized"
fixtures_dir="$work_dir/fixtures"
codebase_root="$work_dir/codebases"
xdg_data_home="$work_dir/xdg-data"

mkdir -p "$raw_dir" "$normalized_dir" "$fixtures_dir" "$codebase_root" "$xdg_data_home"

case_manifest="$normalized_dir/cases.txt"
summary_file="$normalized_dir/summary.tsv"
: >"$case_manifest"
printf 'case_id\tn\tmean_ms\tstddev_ms\tstderr_ms\tci95_ms\tmin_ms\tmax_ms\n' >"$summary_file"

stage_transcript_path() {
  local repo_rel="$1"
  local parent
  parent="$(dirname "$repo_rel")"
  local src_parent="$repo_root/$parent"
  local dst_parent="$fixtures_dir/$parent"

  if [[ ! -d "$dst_parent" ]]; then
    mkdir -p "$(dirname "$dst_parent")"
    cp -R "$src_parent" "$dst_parent"
  fi

  printf '%s\n' "$fixtures_dir/$repo_rel"
}

append_case_summary() {
  local case_id="$1"
  local samples_file="$2"

  awk -F'\t' -v cid="$case_id" '
    $1 == "sample" {
      x[++n] = $3 + 0
      sum += x[n]
      sumsq += x[n] * x[n]
      if (n == 1 || x[n] < min) min = x[n]
      if (n == 1 || x[n] > max) max = x[n]
    }
    END {
      if (n < 2) {
        exit 1
      }
      mean = sum / n
      var = (sumsq - (sum * sum / n)) / (n - 1)
      if (var < 0) var = 0
      stddev = sqrt(var)
      stderr = stddev / sqrt(n)
      ci95 = 1.96 * stderr
      printf "%s\t%d\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\n", cid, n, mean, stddev, stderr, ci95, min, max
    }
  ' "$samples_file" >>"$summary_file"
}

run_timed_case() {
  local case_id="$1"
  local expected_rc="$2"
  local stdin_payload="$3"
  shift 3
  local cmd_template=("$@")

  local case_raw_dir="$raw_dir/$case_id"
  local samples_file="$case_raw_dir/samples.tsv"
  mkdir -p "$case_raw_dir"
  printf 'phase\titeration\telapsed_ms\trc\n' >"$samples_file"

  run_one_iteration() {
    local phase="$1"
    local iteration="$2"
    local codebase_path="$codebase_root/$case_id/${phase}_${iteration}"
    mkdir -p "$codebase_path"

    local cmd=()
    local arg
    for arg in "${cmd_template[@]}"; do
      if [[ "$arg" == "__CODEBASE__" ]]; then
        cmd+=("$codebase_path")
      else
        cmd+=("$arg")
      fi
    done

    local stdout_file="$case_raw_dir/${phase}_${iteration}.out"
    local stderr_file="$case_raw_dir/${phase}_${iteration}.err"

    local start_ns
    local end_ns
    local elapsed_ns
    local elapsed_ms

    start_ns="$(date +%s%N)"
    set +e
    if [[ -n "$stdin_payload" ]]; then
      env XDG_DATA_HOME="$xdg_data_home" "${cmd[@]}" >"$stdout_file" 2>"$stderr_file" <<<"$stdin_payload"
    else
      env XDG_DATA_HOME="$xdg_data_home" "${cmd[@]}" >"$stdout_file" 2>"$stderr_file"
    fi
    local rc=$?
    set -e
    end_ns="$(date +%s%N)"

    elapsed_ns=$((end_ns - start_ns))
    elapsed_ms="$(awk -v ns="$elapsed_ns" 'BEGIN { printf "%.3f", ns / 1000000.0 }')"
    printf '%s\t%s\t%s\t%s\n' "$phase" "$iteration" "$elapsed_ms" "$rc" >>"$samples_file"

    if [[ "$rc" -ne "$expected_rc" ]]; then
      echo "FAIL $case_id/$phase/$iteration (expected rc $expected_rc, got $rc)" >&2
      echo "stderr:" >&2
      sed -n '1,80p' "$stderr_file" >&2 || true
      exit 1
    fi
  }

  local i
  for ((i = 1; i <= warmup; i++)); do
    run_one_iteration "warmup" "$i"
  done

  for ((i = 1; i <= samples; i++)); do
    run_one_iteration "sample" "$i"
  done

  append_case_summary "$case_id" "$samples_file"
  echo "$case_id" >>"$case_manifest"
  echo "PASS $case_id"
}

run_profile() {
  local staged_integration_transcript
  local staged_hello_transcript
  local staged_roundtrip_transcript
  local staged_parser_declaration_heavy_transcript
  local staged_print_u

  staged_integration_transcript="$(stage_transcript_path "unison-cli-integration/integration-tests/IntegrationTests/transcript.md")"
  staged_hello_transcript="$(stage_transcript_path "unison-src/transcripts/hello.md")"
  staged_roundtrip_transcript="$(stage_transcript_path "unison-src/transcripts-round-trip/main.md")"
  staged_parser_declaration_heavy_transcript="$(stage_transcript_path "scripts/unison/benchmarks/parser-declaration-heavy.md")"
  staged_print_u="$(stage_transcript_path "unison-cli-integration/integration-tests/IntegrationTests/print.u")"

  local pipe_program
  pipe_program=$'print : \'{IO, Exception} ()\nprint _ = base.io.printLine "ok"\n'

  run_timed_case run_file_print 0 "" \
    "$binary" run.file "$staged_print_u" print --codebase-create "__CODEBASE__"

  run_timed_case run_pipe_print 0 "$pipe_program" \
    "$binary" run.pipe print --codebase-create "__CODEBASE__"

  if [[ "$profile" == "core" || "$profile" == "extended" ]]; then
    run_timed_case transcript_parser_declaration_heavy 0 "" \
      "$binary" transcript "$staged_parser_declaration_heavy_transcript" --codebase-create "__CODEBASE__"

    run_timed_case transcript_integration 0 "" \
      "$binary" transcript "$staged_integration_transcript" --codebase-create "__CODEBASE__"

    run_timed_case transcript_hello 0 "" \
      "$binary" transcript "$staged_hello_transcript" --codebase-create "__CODEBASE__"
  fi

  if [[ "$profile" == "extended" ]]; then
    run_timed_case transcript_round_trip 0 "" \
      "$binary" transcript "$staged_roundtrip_transcript" --codebase-create "__CODEBASE__"
  fi

  if [[ -n "$benchmark_transcript" ]]; then
    run_timed_case benchmark_transcript 0 "" \
      "$binary" transcript "$benchmark_transcript" --codebase-create "__CODEBASE__"
  fi
}

update_baseline_files() {
  mkdir -p "$baseline_dir/samples"
  cp "$summary_file" "$baseline_dir/summary.tsv"
  cp "$case_manifest" "$baseline_dir/cases.txt"
  while IFS= read -r case_id; do
    cp "$raw_dir/$case_id/samples.tsv" "$baseline_dir/samples/$case_id.samples.tsv"
  done <"$case_manifest"
  echo "Baseline updated at $baseline_dir"
}

check_baseline_files() {
  local baseline_summary="$baseline_dir/summary.tsv"
  local baseline_cases="$baseline_dir/cases.txt"
  if [[ ! -f "$baseline_summary" ]]; then
    echo "Missing baseline summary: $baseline_summary" >&2
    return 1
  fi
  if [[ ! -f "$baseline_cases" ]]; then
    echo "Missing baseline cases manifest: $baseline_cases" >&2
    return 1
  fi

  local fail_file="$work_dir/baseline-check.fail"
  : >"$fail_file"

  awk -F'\t' \
    -v threshold="$max_regression_pct" \
    -v fail_file="$fail_file" '
    NR == FNR {
      if (FNR == 1) next
      bmean[$1] = $3 + 0
      bci[$1] = $6 + 0
      next
    }
    FNR == 1 { next }
    {
      case_id = $1
      cmean = $3 + 0
      cci = $6 + 0

      if (!(case_id in bmean)) {
        printf "MISSING_BASELINE %s\n", case_id
        print "1" >> fail_file
        next
      }

      bupper = bmean[case_id] + bci[case_id]
      clower = cmean - cci
      if (bmean[case_id] == 0) {
        pct = 0
      } else {
        pct = ((cmean - bmean[case_id]) / bmean[case_id]) * 100
      }

      printf "CASE %s baseline=%.3f±%.3fms current=%.3f±%.3fms delta=%.2f%%\n", case_id, bmean[case_id], bci[case_id], cmean, cci, pct

      if (pct > threshold && clower > bupper) {
        printf "REGRESSION %s exceeds threshold (delta=%.2f%%, non-overlapping CI)\n", case_id, pct
        print "1" >> fail_file
      }

      seen[case_id] = 1
    }
    END {
      for (case_id in bmean) {
        if (!(case_id in seen)) {
          printf "MISSING_CURRENT %s\n", case_id
          print "1" >> fail_file
        }
      }
    }
  ' "$baseline_summary" "$summary_file"

  if [[ -s "$fail_file" ]]; then
    rm -f "$fail_file"
    return 1
  fi
  rm -f "$fail_file"
  echo "Baseline check passed."
}

echo "Reference binary: $binary"
echo "Profile: $profile"
echo "Samples: $samples (warmup $warmup)"
echo "Work dir: $work_dir"
echo "Baseline dir: $baseline_dir"
if [[ -n "$benchmark_transcript" ]]; then
  echo "Benchmark transcript: $benchmark_transcript"
fi

run_profile

echo "Summary:"
cat "$summary_file"

if [[ "$update_baseline" -eq 1 ]]; then
  update_baseline_files
fi

if [[ "$check_baseline" -eq 1 ]]; then
  check_baseline_files
fi

echo "Perf run complete."
