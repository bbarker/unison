#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/unison/reference-corpus.sh [options]

Run a curated corpus against a reference Unison binary, normalize outputs,
and optionally update/check a stored baseline.

Options:
  --binary PATH           Unison binary to run (default: result/bin/unison)
  --profile NAME          Corpus profile: smoke | parser | adapter | core | extended | all-transcripts (default: core)
  --work-dir DIR          Working output directory (default: timestamped under .run/)
  --baseline-dir DIR      Baseline directory (default: scripts/unison/baselines/<profile>)
  --max-cases N           Max number of cases (only used by all-transcripts; default: unlimited)
  --case-timeout-seconds N
                          Per-case timeout in seconds; 0 disables timeout
                          (all-transcripts default: 120)
  --update-baseline       Write normalized outputs into baseline directory
  --check-baseline        Compare normalized outputs against baseline directory
  -h, --help              Show this help

Artifacts:
  <work-dir>/raw/<case>.*         raw command/stdin/stdout/stderr/rc
  <work-dir>/normalized/<case>.*  normalized stdout/stderr/rc plus case manifest
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
binary="$repo_root/result/bin/unison"
profile="core"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
work_dir=""
baseline_dir=""
update_baseline=0
check_baseline=0
max_cases=0
case_timeout_seconds=0

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

if [[ "$profile" != "smoke" && "$profile" != "parser" && "$profile" != "adapter" && "$profile" != "core" && "$profile" != "extended" && "$profile" != "all-transcripts" ]]; then
  echo "Unsupported profile: $profile" >&2
  exit 2
fi

if ! [[ "$max_cases" =~ ^[0-9]+$ ]]; then
  echo "Invalid --max-cases value: $max_cases" >&2
  exit 2
fi

if ! [[ "$case_timeout_seconds" =~ ^[0-9]+$ ]]; then
  echo "Invalid --case-timeout-seconds value: $case_timeout_seconds" >&2
  exit 2
fi

if [[ ! -x "$binary" ]]; then
  echo "Binary is not executable: $binary" >&2
  exit 1
fi

if [[ -z "$work_dir" ]]; then
  work_dir="$repo_root/.run/unison-reference/corpus/$profile/$timestamp"
fi

if [[ -z "$baseline_dir" ]]; then
  baseline_dir="$repo_root/scripts/unison/baselines/$profile"
fi

if [[ "$profile" == "all-transcripts" && "$case_timeout_seconds" -eq 0 ]]; then
  case_timeout_seconds=120
  echo "All-transcripts default: using --case-timeout-seconds=$case_timeout_seconds"
fi

if [[ "$profile" == "all-transcripts" && "$check_baseline" -eq 1 && "$update_baseline" -eq 0 && "$max_cases" -eq 0 ]]; then
  baseline_summary_file="$baseline_dir/all-transcripts-summary.txt"
  if [[ -f "$baseline_summary_file" ]]; then
    baseline_max_cases="$(awk -F= '$1 == "max_cases" { print $2; exit }' "$baseline_summary_file" | tr -d '[:space:]')"
    if [[ "$baseline_max_cases" =~ ^[0-9]+$ && "$baseline_max_cases" -gt 0 ]]; then
      max_cases="$baseline_max_cases"
      echo "All-transcripts baseline check: using max_cases=$max_cases from $baseline_summary_file"
    fi
  fi
fi

raw_dir="$work_dir/raw"
normalized_dir="$work_dir/normalized"
fixtures_dir="$work_dir/fixtures"
codebase_root="$work_dir/codebases"
xdg_data_home="$work_dir/xdg-data"
home_dir="${HOME:-}"
work_dir_tilde="$work_dir"
if [[ -n "$home_dir" && "$work_dir" == "$home_dir"* ]]; then
  work_dir_tilde="~${work_dir#$home_dir}"
fi

mkdir -p "$raw_dir" "$normalized_dir" "$fixtures_dir" "$codebase_root" "$xdg_data_home"

stage_transcript_path() {
  local repo_rel="$1"
  local parent
  parent="$(dirname "$repo_rel")"
  local src_parent="$repo_root/$parent"
  local dst_parent="$fixtures_dir/$parent"
  local src_file="$repo_root/$repo_rel"
  local dst_file="$fixtures_dir/$repo_rel"

  if [[ ! -d "$dst_parent" ]]; then
    mkdir -p "$(dirname "$dst_parent")"
    cp -R "$src_parent" "$dst_parent"
  fi

  # Always refresh the specific staged file so repeated runs in a stable
  # work dir pick up newly added/updated corpus fixtures.
  cp "$src_file" "$dst_file"

  printf '%s\n' "$dst_file"
}

normalize_file() {
  local input="$1"
  local output="$2"

  REPO_ROOT="$repo_root" WORK_DIR="$work_dir" WORK_DIR_TILDE="$work_dir_tilde" BASELINE_DIR="$baseline_dir" \
    perl -CSDA -pe '
      s/\e\[[0-9;?]*[ -\/]*[@-~]//g;                      # ANSI escapes
      s/\r[^\n]*//g;                                      # progress line rewrites

      s/^⚙️\s+Processing stanza.*\n//mg;                  # transcript progress bars
      s/^⚠️\s+Port 5858 is already bound.*\n//mg;         # transient port warning
      s/^\s*The UCM server will be started on port .*\n//mg;
      s/^\s*Tools which expect the server on a specific port.*\n//mg;

      s/You are running version: .*/You are running version: <VERSION>/g;
      s/\bunison version:\s+.*/unison version: <VERSION>/g;

      s/\Q$ENV{WORK_DIR_TILDE}\E/<WORK_DIR>/g;
      s/\Q$ENV{WORK_DIR}\E/<WORK_DIR>/g;
      s/\Q$ENV{BASELINE_DIR}\E/<BASELINE_DIR>/g;
      s/\Q$ENV{REPO_ROOT}\E/<REPO_ROOT>/g;

      s#transcript-[0-9a-f]+#transcript-<ID>#g;
      s#http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_-]+#http://127.0.0.1:<PORT>/<TOKEN>#g;
      s#http://localhost:[0-9]+/[A-Za-z0-9_-]+#http://localhost:<PORT>/<TOKEN>#g;
      s#(/private)?/tmp/[A-Za-z0-9._/\-]+#<TMP_PATH>#g;
    ' "$input" >"$output"
}

run_case() {
  local case_id="$1"
  local expected_rc="$2"
  local stdin_payload="$3"
  shift 3

  local case_raw_prefix="$raw_dir/$case_id"
  local case_norm_prefix="$normalized_dir/$case_id"
  local stdout_file="$case_raw_prefix.out"
  local stderr_file="$case_raw_prefix.err"
  local rc_file="$case_raw_prefix.rc"
  local cmd_file="$case_raw_prefix.cmd"
  local stdin_file="$case_raw_prefix.stdin"

  mkdir -p "$codebase_root/$case_id"

  printf '%q ' "$@" >"$cmd_file"
  printf '\n' >>"$cmd_file"
  printf '%s' "$stdin_payload" >"$stdin_file"

  local -a timeout_prefix=()
  if [[ "$case_timeout_seconds" -gt 0 ]]; then
    timeout_prefix=(timeout "${case_timeout_seconds}s")
  fi

  set +e
  if [[ -n "$stdin_payload" ]]; then
    env XDG_DATA_HOME="$xdg_data_home" "${timeout_prefix[@]}" "$@" >"$stdout_file" 2>"$stderr_file" <<<"$stdin_payload"
  else
    env XDG_DATA_HOME="$xdg_data_home" "${timeout_prefix[@]}" "$@" >"$stdout_file" 2>"$stderr_file"
  fi
  local rc=$?
  set -e

  echo "$rc" >"$rc_file"

  normalize_file "$stdout_file" "$case_norm_prefix.out"
  normalize_file "$stderr_file" "$case_norm_prefix.err"
  printf '%s\n' "$rc" >"$case_norm_prefix.rc"
  normalize_file "$cmd_file" "$case_norm_prefix.cmd"

  if [[ "$rc" -eq 124 && "$case_timeout_seconds" -gt 0 ]]; then
    echo "TIMEOUT $case_id (>${case_timeout_seconds}s)"
  fi

  if [[ "$expected_rc" != "-1" && "$rc" -ne "$expected_rc" ]]; then
    echo "FAIL $case_id (expected exit $expected_rc, got $rc)"
    return 1
  fi
  echo "PASS $case_id"
}

run_exec_case() {
  local case_id="$1"
  local expected_rc="$2"
  shift 2
  run_case "$case_id" "$expected_rc" "" "$@"
}

run_stdin_case() {
  local case_id="$1"
  local expected_rc="$2"
  local stdin_payload="$3"
  shift 3
  run_case "$case_id" "$expected_rc" "$stdin_payload" "$@"
}

all_transcript_expected_rc() {
  local repo_rel="$1"
  case "$repo_rel" in
    unison-src/transcripts/idempotent/cancel.md|\
    unison-src/transcripts/idempotent/delete.md|\
    unison-src/transcripts/idempotent/fix-5612.md|\
    unison-src/transcripts/idempotent/merge.md|\
    unison-src/transcripts/idempotent/print-ordering.md|\
    unison-src/transcripts/idempotent/upgrade.md|\
    unison-src/transcripts-manual/benchmarks.md|\
    unison-src/transcripts-manual/remote-tab-completion.md|\
    unison-src/transcripts-manual/dll-ffi-unix.md|\
    unison-src/transcripts-using-base/all-base-hashes.md|\
    unison-src/transcripts-using-base/binary-encoding-nats.md|\
    unison-src/transcripts-using-base/codeops.md|\
    unison-src/transcripts-using-base/doc.md|\
    unison-src/transcripts-using-base/failure-tests.md|\
    unison-src/transcripts-using-base/fix2158-1.md|\
    unison-src/transcripts-using-base/fix2358.md|\
    unison-src/transcripts-using-base/fix2944.md|\
    unison-src/transcripts-using-base/fix3166.md|\
    unison-src/transcripts-using-base/fix3542.md|\
    unison-src/transcripts-using-base/fix3939.md|\
    unison-src/transcripts-using-base/fix4746.md|\
    unison-src/transcripts-using-base/fix5178.md|\
    unison-src/transcripts-using-base/hashing.md|\
    unison-src/transcripts-using-base/mvar.md|\
    unison-src/transcripts-using-base/nat-coersion.md|\
    unison-src/transcripts-using-base/net.md|\
    unison-src/transcripts-using-base/random-deserial.md|\
    unison-src/transcripts-using-base/ref-promise.md|\
    unison-src/transcripts-using-base/replacements.md|\
    unison-src/transcripts-using-base/serial-test-0[0-5].md|\
    unison-src/transcripts-using-base/stm.md|\
    unison-src/transcripts-using-base/thread.md|\
    unison-src/transcripts-using-base/tls.md|\
    unison-src/transcripts-using-base/utf8.md|\
    unison-src/transcripts-manual/dll-ffi-win.md)
      printf '1\n'
      return
      ;;
  esac
  if [[ "$repo_rel" == *"/errors/"* ]]; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

all_transcript_is_unstable_case() {
  local repo_rel="$1"
  case "$repo_rel" in
    unison-src/transcripts/idempotent/cycle-update-3.md|\
    unison-src/transcripts/idempotent/update-term-with-dependent-to-different-type.md|\
    unison-src/transcripts-manual/public-tests.md)
      return 0
      ;;
  esac
  return 1
}

all_transcript_case_id() {
  local repo_rel="$1"
  local digest
  digest="$(printf '%s' "$repo_rel" | sha1sum | cut -c1-12)"
  printf 'transcript_all_%s\n' "$digest"
}

case_manifest="$normalized_dir/cases.txt"
: >"$case_manifest"

run_profile() {
  local staged_transcript
  local staged_roundtrip
  local staged_error_transcript
  local staged_integration_transcript
  local staged_integration_main_uc
  local staged_rewrites_transcript
  local staged_using_base_transcript
  local staged_decl_prefixes_transcript
  local staged_decl_multiline_transcript
  local staged_decl_tight_equals_transcript
  local staged_decl_parse_error_transcript
  local staged_unterminated_string_parse_error_transcript
  local staged_signature_lhs_parse_error_transcript
  local staged_reserved_identifier_parse_error_transcript
  local staged_numeric_identifier_parse_error_transcript
  local staged_keyword_prefix_identifier_parse_success_transcript
  local staged_keyword_prefix_apostrophe_identifier_parse_success_transcript
  local staged_scientific_notation_uppercase_parse_success_transcript
  local staged_escaped_reserved_identifier_parse_success_transcript
  local staged_escaped_symbol_identifier_parse_error_transcript
  local staged_tab_keyword_whitespace_parse_success_transcript
  local staged_load_file_success_transcript
  local staged_load_file_missing_transcript
  local staged_load_file_parse_error_transcript
  local staged_adapter_pull_transcript
  local staged_adapter_lib_install_transcript
  local staged_adapter_add_update_transcript
  local staged_adapter_add_empty_transcript
  local staged_adapter_update_empty_transcript

  staged_integration_transcript="$(stage_transcript_path "unison-cli-integration/integration-tests/IntegrationTests/transcript.md")"
  staged_integration_main_uc="$(stage_transcript_path "unison-cli-integration/integration-tests/IntegrationTests/main.uc")"
  staged_transcript="$(stage_transcript_path "unison-src/transcripts/hello.md")"
  staged_roundtrip="$(stage_transcript_path "unison-src/transcripts-round-trip/main.md")"
  staged_error_transcript="$(stage_transcript_path "unison-src/transcripts/errors/code-block-parse-error.md")"
  staged_rewrites_transcript="$(stage_transcript_path "unison-src/transcripts-manual/rewrites.md")"
  staged_using_base_transcript="$(stage_transcript_path "unison-src/transcripts-using-base/serial-test-00.md")"
  staged_decl_prefixes_transcript="$(stage_transcript_path "scripts/unison/corpus/declaration-prefixes.md")"
  staged_decl_multiline_transcript="$(stage_transcript_path "scripts/unison/corpus/declaration-multiline.md")"
  staged_decl_tight_equals_transcript="$(stage_transcript_path "scripts/unison/corpus/declaration-tight-equals.md")"
  staged_decl_parse_error_transcript="$(stage_transcript_path "scripts/unison/corpus/declaration-parse-error.md")"
  staged_unterminated_string_parse_error_transcript="$(stage_transcript_path "scripts/unison/corpus/unterminated-string-parse-error.md")"
  staged_signature_lhs_parse_error_transcript="$(stage_transcript_path "scripts/unison/corpus/signature-lhs-parse-error.md")"
  staged_reserved_identifier_parse_error_transcript="$(stage_transcript_path "scripts/unison/corpus/reserved-identifier-parse-error.md")"
  staged_numeric_identifier_parse_error_transcript="$(stage_transcript_path "scripts/unison/corpus/numeric-identifier-parse-error.md")"
  staged_keyword_prefix_identifier_parse_success_transcript="$(stage_transcript_path "scripts/unison/corpus/keyword-prefix-identifier-parse-success.md")"
  staged_keyword_prefix_apostrophe_identifier_parse_success_transcript="$(stage_transcript_path "scripts/unison/corpus/keyword-prefix-apostrophe-identifier-parse-success.md")"
  staged_scientific_notation_uppercase_parse_success_transcript="$(stage_transcript_path "scripts/unison/corpus/scientific-notation-uppercase-parse-success.md")"
  staged_escaped_reserved_identifier_parse_success_transcript="$(stage_transcript_path "scripts/unison/corpus/escaped-reserved-identifier-parse-success.md")"
  staged_escaped_symbol_identifier_parse_error_transcript="$(stage_transcript_path "scripts/unison/corpus/escaped-symbol-identifier-parse-error.md")"
  staged_tab_keyword_whitespace_parse_success_transcript="$(stage_transcript_path "scripts/unison/corpus/tab-keyword-whitespace-parse-success.md")"
  staged_load_file_success_transcript="$(stage_transcript_path "scripts/unison/corpus/load-file-success.md")"
  staged_load_file_missing_transcript="$(stage_transcript_path "scripts/unison/corpus/load-file-missing.md")"
  staged_load_file_parse_error_transcript="$(stage_transcript_path "scripts/unison/corpus/load-file-parse-error.md")"
  staged_adapter_pull_transcript="$(stage_transcript_path "scripts/unison/corpus/adapter-pull.md")"
  staged_adapter_lib_install_transcript="$(stage_transcript_path "scripts/unison/corpus/adapter-lib-install.md")"
  staged_adapter_add_update_transcript="$(stage_transcript_path "scripts/unison/corpus/adapter-add-update.md")"
  staged_adapter_add_empty_transcript="$(stage_transcript_path "scripts/unison/corpus/adapter-add-empty.md")"
  staged_adapter_update_empty_transcript="$(stage_transcript_path "scripts/unison/corpus/adapter-update-empty.md")"

  local staged_print_u
  staged_print_u="$(stage_transcript_path "unison-cli-integration/integration-tests/IntegrationTests/print.u")"

  local pipe_program
  pipe_program=$'print : \'{IO, Exception} ()\nprint _ = base.io.printLine "ok"\n'

  run_exec_case help 0 "$binary" --help
  echo "help" >>"$case_manifest"

  run_exec_case version 0 "$binary" version
  echo "version" >>"$case_manifest"

  if [[ "$profile" == "all-transcripts" ]]; then
    local -a transcript_roots=(
      "unison-src/transcripts"
      "unison-src/transcripts-manual"
      "unison-src/transcripts-round-trip"
      "unison-src/transcripts-using-base"
      "unison-cli-integration/integration-tests/IntegrationTests"
    )
    local -a transcript_files=()
    local root=""
    for root in "${transcript_roots[@]}"; do
      if [[ -d "$repo_root/$root" ]]; then
        while IFS= read -r transcript_path; do
          transcript_files+=("$transcript_path")
        done < <(find "$repo_root/$root" -type f -name '*.md' ! -name '*.output.md' | sort)
      fi
    done

    local all_map_file="$normalized_dir/all-transcripts-map.tsv"
    local mismatch_list="$normalized_dir/all-transcripts-mismatches.txt"
    printf 'case_id\texpected_rc\texpected_source\trepo_path\n' >"$all_map_file"
    printf 'case_id\texpected_rc\tactual_rc\texpected_source\trepo_path\n' >"$mismatch_list"

    local total_cases=0
    local matched_cases=0
    local mismatched_cases=0
    local transcript_path=""

    for transcript_path in "${transcript_files[@]}"; do
      if [[ "$max_cases" -gt 0 && "$total_cases" -ge "$max_cases" ]]; then
        break
      fi
      local repo_rel="${transcript_path#$repo_root/}"
      local case_id
      case_id="$(all_transcript_case_id "$repo_rel")"
      local expected_rc
      local expected_source="heuristic"
      if [[ "$update_baseline" -eq 1 && "$check_baseline" -eq 0 ]]; then
        expected_rc="-1"
        expected_source="recorded"
      elif all_transcript_is_unstable_case "$repo_rel"; then
        expected_rc="-1"
        expected_source="heuristic-unstable"
      elif [[ -f "$baseline_dir/$case_id.rc" ]]; then
        expected_rc="$(tr -d '\n' <"$baseline_dir/$case_id.rc")"
        expected_source="baseline"
      else
        expected_rc="$(all_transcript_expected_rc "$repo_rel")"
      fi
      local staged_transcript_file
      staged_transcript_file="$(stage_transcript_path "$repo_rel")"

      printf '%s\t%s\t%s\t%s\n' "$case_id" "$expected_rc" "$expected_source" "$repo_rel" >>"$all_map_file"
      echo "$case_id" >>"$case_manifest"
      total_cases=$((total_cases + 1))

      if run_exec_case "$case_id" "$expected_rc" \
        "$binary" \
        transcript \
        "$staged_transcript_file" \
        --codebase-create \
        "$codebase_root/$case_id"; then
        matched_cases=$((matched_cases + 1))
      else
        mismatched_cases=$((mismatched_cases + 1))
        local actual_rc
        actual_rc="$(tr -d '\n' <"$normalized_dir/$case_id.rc")"
        printf '%s\t%s\t%s\t%s\t%s\n' "$case_id" "$expected_rc" "$actual_rc" "$expected_source" "$repo_rel" >>"$mismatch_list"
      fi
    done

    {
      echo "profile=all-transcripts"
      echo "total_cases=$total_cases"
      echo "matched_cases=$matched_cases"
      echo "mismatched_cases=$mismatched_cases"
      echo "max_cases=$max_cases"
      echo "case_timeout_seconds=$case_timeout_seconds"
      echo "map_file=all-transcripts-map.tsv"
      echo "mismatch_file=all-transcripts-mismatches.txt"
      echo "expected_precedence=recorded(update-baseline) > heuristic-unstable > baseline > heuristic"
    } >"$normalized_dir/all-transcripts-summary.txt"

    echo "All-transcripts sweep summary: total=$total_cases matched=$matched_cases mismatched=$mismatched_cases"
    if [[ "$mismatched_cases" -ne 0 ]]; then
      echo "Mismatch details: $mismatch_list"
      return 1
    fi

    return
  fi

  if [[ "$profile" == "parser" ]]; then
    run_exec_case transcript_decl_prefixes 0 \
      "$binary" \
      transcript \
      "$staged_decl_prefixes_transcript" \
      --codebase-create \
      "$codebase_root/transcript_decl_prefixes"
    echo "transcript_decl_prefixes" >>"$case_manifest"

    run_exec_case transcript_decl_multiline 0 \
      "$binary" \
      transcript \
      "$staged_decl_multiline_transcript" \
      --codebase-create \
      "$codebase_root/transcript_decl_multiline"
    echo "transcript_decl_multiline" >>"$case_manifest"

    run_exec_case transcript_decl_tight_equals 0 \
      "$binary" \
      transcript \
      "$staged_decl_tight_equals_transcript" \
      --codebase-create \
      "$codebase_root/transcript_decl_tight_equals"
    echo "transcript_decl_tight_equals" >>"$case_manifest"

    run_exec_case transcript_decl_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_decl_parse_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_decl_parse_error"
    echo "transcript_decl_parse_error" >>"$case_manifest"

    run_exec_case transcript_unterminated_string_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_unterminated_string_parse_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_unterminated_string_parse_error"
    echo "transcript_unterminated_string_parse_error" >>"$case_manifest"

    run_exec_case transcript_signature_lhs_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_signature_lhs_parse_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_signature_lhs_parse_error"
    echo "transcript_signature_lhs_parse_error" >>"$case_manifest"

    run_exec_case transcript_reserved_identifier_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_reserved_identifier_parse_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_reserved_identifier_parse_error"
    echo "transcript_reserved_identifier_parse_error" >>"$case_manifest"

    run_exec_case transcript_numeric_identifier_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_numeric_identifier_parse_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_numeric_identifier_parse_error"
    echo "transcript_numeric_identifier_parse_error" >>"$case_manifest"

    run_exec_case transcript_keyword_prefix_identifier_parse_success 0 \
      "$binary" \
      transcript \
      "$staged_keyword_prefix_identifier_parse_success_transcript" \
      --codebase-create \
      "$codebase_root/transcript_keyword_prefix_identifier_parse_success"
    echo "transcript_keyword_prefix_identifier_parse_success" >>"$case_manifest"

    run_exec_case transcript_keyword_prefix_apostrophe_identifier_parse_success 0 \
      "$binary" \
      transcript \
      "$staged_keyword_prefix_apostrophe_identifier_parse_success_transcript" \
      --codebase-create \
      "$codebase_root/transcript_keyword_prefix_apostrophe_identifier_parse_success"
    echo "transcript_keyword_prefix_apostrophe_identifier_parse_success" >>"$case_manifest"

    run_exec_case transcript_scientific_notation_uppercase_parse_success 0 \
      "$binary" \
      transcript \
      "$staged_scientific_notation_uppercase_parse_success_transcript" \
      --codebase-create \
      "$codebase_root/transcript_scientific_notation_uppercase_parse_success"
    echo "transcript_scientific_notation_uppercase_parse_success" >>"$case_manifest"

    run_exec_case transcript_escaped_reserved_identifier_parse_success 0 \
      "$binary" \
      transcript \
      "$staged_escaped_reserved_identifier_parse_success_transcript" \
      --codebase-create \
      "$codebase_root/transcript_escaped_reserved_identifier_parse_success"
    echo "transcript_escaped_reserved_identifier_parse_success" >>"$case_manifest"

    run_exec_case transcript_escaped_symbol_identifier_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_escaped_symbol_identifier_parse_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_escaped_symbol_identifier_parse_error"
    echo "transcript_escaped_symbol_identifier_parse_error" >>"$case_manifest"

    run_exec_case transcript_tab_keyword_whitespace_parse_success 0 \
      "$binary" \
      transcript \
      "$staged_tab_keyword_whitespace_parse_success_transcript" \
      --codebase-create \
      "$codebase_root/transcript_tab_keyword_whitespace_parse_success"
    echo "transcript_tab_keyword_whitespace_parse_success" >>"$case_manifest"

    return
  fi

  if [[ "$profile" == "adapter" ]]; then
    run_exec_case transcript_adapter_pull 0 \
      "$binary" \
      transcript \
      "$staged_adapter_pull_transcript" \
      --codebase-create \
      "$codebase_root/transcript_adapter_pull"
    echo "transcript_adapter_pull" >>"$case_manifest"

    run_exec_case transcript_adapter_lib_install 0 \
      "$binary" \
      transcript \
      "$staged_adapter_lib_install_transcript" \
      --codebase-create \
      "$codebase_root/transcript_adapter_lib_install"
    echo "transcript_adapter_lib_install" >>"$case_manifest"

    run_exec_case transcript_adapter_add_update 0 \
      "$binary" \
      transcript \
      "$staged_adapter_add_update_transcript" \
      --codebase-create \
      "$codebase_root/transcript_adapter_add_update"
    echo "transcript_adapter_add_update" >>"$case_manifest"

    run_exec_case transcript_adapter_add_empty 1 \
      "$binary" \
      transcript \
      "$staged_adapter_add_empty_transcript" \
      --codebase-create \
      "$codebase_root/transcript_adapter_add_empty"
    echo "transcript_adapter_add_empty" >>"$case_manifest"

    run_exec_case transcript_adapter_update_empty 1 \
      "$binary" \
      transcript \
      "$staged_adapter_update_empty_transcript" \
      --codebase-create \
      "$codebase_root/transcript_adapter_update_empty"
    echo "transcript_adapter_update_empty" >>"$case_manifest"

    return
  fi

  run_exec_case run_file_print 0 \
    "$binary" \
    run.file \
    "$staged_print_u" \
    print \
    --codebase-create \
    "$codebase_root/run_file_print"
  echo "run_file_print" >>"$case_manifest"

  run_stdin_case run_pipe_print 0 "$pipe_program" \
    "$binary" \
    run.pipe \
    print \
    --codebase-create \
    "$codebase_root/run_pipe_print"
  echo "run_pipe_print" >>"$case_manifest"

  run_exec_case transcript_integration 0 \
    "$binary" \
    transcript \
    "$staged_integration_transcript" \
    --codebase-create \
    "$codebase_root/transcript_integration"
  echo "transcript_integration" >>"$case_manifest"

  run_exec_case transcript_fork_integration 0 \
    "$binary" \
    transcript.fork \
    "$staged_integration_transcript" \
    --codebase-create \
    "$codebase_root/transcript_fork_integration"
  echo "transcript_fork_integration" >>"$case_manifest"

  run_exec_case run_compiled_integration_main 0 \
    "$binary" \
    run.compiled \
    "$staged_integration_main_uc"
  echo "run_compiled_integration_main" >>"$case_manifest"

  if [[ "$profile" == "core" || "$profile" == "extended" ]]; then
    run_exec_case transcript_hello 0 \
      "$binary" \
      transcript \
      "$staged_transcript" \
      --codebase-create \
      "$codebase_root/transcript_hello"
    echo "transcript_hello" >>"$case_manifest"

    run_exec_case transcript_round_trip 0 \
      "$binary" \
      transcript \
      "$staged_roundtrip" \
      --codebase-create \
      "$codebase_root/transcript_round_trip"
    echo "transcript_round_trip" >>"$case_manifest"

    run_exec_case transcript_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_parse_error"
    echo "transcript_parse_error" >>"$case_manifest"

    run_exec_case transcript_decl_prefixes 0 \
      "$binary" \
      transcript \
      "$staged_decl_prefixes_transcript" \
      --codebase-create \
      "$codebase_root/transcript_decl_prefixes"
    echo "transcript_decl_prefixes" >>"$case_manifest"

    run_exec_case transcript_decl_multiline 0 \
      "$binary" \
      transcript \
      "$staged_decl_multiline_transcript" \
      --codebase-create \
      "$codebase_root/transcript_decl_multiline"
    echo "transcript_decl_multiline" >>"$case_manifest"

    run_exec_case transcript_decl_tight_equals 0 \
      "$binary" \
      transcript \
      "$staged_decl_tight_equals_transcript" \
      --codebase-create \
      "$codebase_root/transcript_decl_tight_equals"
    echo "transcript_decl_tight_equals" >>"$case_manifest"

    run_exec_case transcript_decl_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_decl_parse_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_decl_parse_error"
    echo "transcript_decl_parse_error" >>"$case_manifest"

    run_exec_case transcript_load_file_success 0 \
      "$binary" \
      transcript \
      "$staged_load_file_success_transcript" \
      --codebase-create \
      "$codebase_root/transcript_load_file_success"
    echo "transcript_load_file_success" >>"$case_manifest"

    run_exec_case transcript_load_file_missing 1 \
      "$binary" \
      transcript \
      "$staged_load_file_missing_transcript" \
      --codebase-create \
      "$codebase_root/transcript_load_file_missing"
    echo "transcript_load_file_missing" >>"$case_manifest"

    run_exec_case transcript_load_file_parse_error 1 \
      "$binary" \
      transcript \
      "$staged_load_file_parse_error_transcript" \
      --codebase-create \
      "$codebase_root/transcript_load_file_parse_error"
    echo "transcript_load_file_parse_error" >>"$case_manifest"
  fi

  if [[ "$profile" == "extended" ]]; then
    run_exec_case transcript_manual_rewrites 0 \
      "$binary" \
      transcript \
      "$staged_rewrites_transcript" \
      --codebase-create \
      "$codebase_root/transcript_manual_rewrites"
    echo "transcript_manual_rewrites" >>"$case_manifest"

    run_exec_case transcript_using_base_serial_00 0 \
      "$binary" \
      transcript \
      "$staged_using_base_transcript" \
      --codebase-create \
      "$codebase_root/transcript_using_base_serial_00"
    echo "transcript_using_base_serial_00" >>"$case_manifest"
  fi
}

echo "Reference binary: $binary"
echo "Profile: $profile"
echo "Work dir: $work_dir"
echo "Baseline dir: $baseline_dir"

set +e
run_profile
run_status=$?
set -e

if [[ "$run_status" -ne 0 ]]; then
  echo "Corpus execution failed."
  exit "$run_status"
fi

if [[ "$update_baseline" -eq 1 ]]; then
  rm -rf "$baseline_dir"
  mkdir -p "$baseline_dir"
  cp -R "$normalized_dir/." "$baseline_dir/"
  {
    echo "profile=$profile"
    echo "updated_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "binary=$binary"
  } >"$baseline_dir/metadata.txt"
  echo "Updated baseline at $baseline_dir"
fi

if [[ "$check_baseline" -eq 1 ]]; then
  if [[ ! -d "$baseline_dir" ]]; then
    echo "Baseline directory does not exist: $baseline_dir" >&2
    exit 1
  fi

  baseline_case_manifest="$baseline_dir/cases.txt"
  if [[ ! -f "$baseline_case_manifest" ]]; then
    echo "Missing baseline case manifest: $baseline_case_manifest" >&2
    exit 1
  fi

  actual_case_manifest="$normalized_dir/cases.txt"
  if [[ ! -f "$actual_case_manifest" ]]; then
    echo "Missing generated case manifest: $actual_case_manifest" >&2
    exit 1
  fi

  diff_failures=0
  if ! diff -u "$baseline_case_manifest" "$actual_case_manifest" >/dev/null; then
    echo "DIFF cases.txt"
    diff -u "$baseline_case_manifest" "$actual_case_manifest" || true
    diff_failures=$((diff_failures + 1))
  fi

  declare -A all_transcripts_unstable_case_ids=()
  if [[ "$profile" == "all-transcripts" ]]; then
    all_map_file="$normalized_dir/all-transcripts-map.tsv"
    if [[ -f "$all_map_file" ]]; then
      while IFS=$'\t' read -r mapped_case_id _ mapped_source _; do
        if [[ "$mapped_case_id" == "case_id" ]]; then
          continue
        fi
        if [[ "$mapped_source" == "heuristic-unstable" ]]; then
          all_transcripts_unstable_case_ids["$mapped_case_id"]=1
        fi
      done <"$all_map_file"
    fi
  fi

  while IFS= read -r case_id; do
    if [[ -n "${all_transcripts_unstable_case_ids[$case_id]:-}" ]]; then
      continue
    fi
    for ext in out err rc cmd; do
      expected="$baseline_dir/$case_id.$ext"
      actual="$normalized_dir/$case_id.$ext"
      if [[ ! -f "$expected" ]]; then
        echo "Missing baseline file: $expected"
        diff_failures=$((diff_failures + 1))
        continue
      fi
      if [[ ! -f "$actual" ]]; then
        echo "Missing generated file: $actual"
        diff_failures=$((diff_failures + 1))
        continue
      fi
      if ! diff -u "$expected" "$actual" >/dev/null; then
        echo "DIFF $case_id.$ext"
        diff -u "$expected" "$actual" || true
        diff_failures=$((diff_failures + 1))
      fi
    done
  done <"$baseline_case_manifest"

  if [[ "$diff_failures" -ne 0 ]]; then
    echo "Baseline check failed with $diff_failures diff(s)."
    exit 1
  fi
  echo "Baseline check passed."
fi

echo "Corpus run complete."
