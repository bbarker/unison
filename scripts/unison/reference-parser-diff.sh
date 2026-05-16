#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/unison/reference-parser-diff.sh [options]

Run parser-focused differential checks against the reference binary.
This wraps the parser corpus baseline check and enforces key parser
expectations on normalized artifacts.

Options:
  --binary PATH         Unison binary to run (default: result/bin/unison)
  --work-dir DIR        Working output directory (default: timestamped under .run/)
  --baseline-dir DIR    Parser baseline directory (default: scripts/unison/baselines/parser)
  -h, --help            Show this help
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
binary="$repo_root/result/bin/unison"
baseline_dir="$repo_root/scripts/unison/baselines/parser"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
work_dir="$repo_root/.run/unison-reference/parser-diff/$timestamp"

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
  --profile parser \
  --check-baseline \
  --baseline-dir "$baseline_dir" \
  --work-dir "$corpus_work_dir"

if [[ ! -f "$case_manifest" ]]; then
  echo "Missing parser case manifest: $case_manifest" >&2
  exit 1
fi

required_cases=(
  transcript_decl_prefixes
  transcript_decl_multiline
  transcript_decl_tight_equals
  transcript_decl_parse_error
  transcript_unterminated_string_parse_error
  transcript_signature_lhs_parse_error
  transcript_reserved_identifier_parse_error
  transcript_numeric_identifier_parse_error
  transcript_keyword_prefix_identifier_parse_success
  transcript_keyword_prefix_apostrophe_identifier_parse_success
  transcript_scientific_notation_uppercase_parse_success
  transcript_escaped_reserved_identifier_parse_success
  transcript_escaped_symbol_identifier_parse_error
  transcript_tab_keyword_whitespace_parse_success
)

for case_id in "${required_cases[@]}"; do
  if ! rg -Fxq "$case_id" "$case_manifest"; then
    echo "Missing parser differential case in manifest: $case_id" >&2
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
expect_contains "$fixture_corpus_dir/declaration-prefixes.output.md" "type TightTagged a = TightTagged a"
expect_contains "$fixture_corpus_dir/declaration-prefixes.output.md" "ability TightFlag where"
expect_contains "$fixture_corpus_dir/declaration-multiline.output.md" "structural type Maybe a = Just a | Nothing"
expect_contains "$fixture_corpus_dir/declaration-multiline.output.md" "ability Store where"
expect_contains "$fixture_corpus_dir/declaration-tight-equals.output.md" "type Maybe a = Just a | Nothing"
expect_contains "$fixture_corpus_dir/keyword-prefix-identifier-parse-success.output.md" "ifx = 42"
expect_contains "$fixture_corpus_dir/keyword-prefix-identifier-parse-success.output.md" "type then0 a = Then0 a"
expect_contains "$fixture_corpus_dir/keyword-prefix-apostrophe-identifier-parse-success.output.md" "else' = 42"
expect_contains "$fixture_corpus_dir/keyword-prefix-apostrophe-identifier-parse-success.output.md" "if' = else' + then'"
expect_contains "$fixture_corpus_dir/scientific-notation-uppercase-parse-success.output.md" "expUpper = 1000.0"
expect_contains "$fixture_corpus_dir/scientific-notation-uppercase-parse-success.output.md" "expUpperNeg = -1.2e-3"
expect_contains "$fixture_corpus_dir/scientific-notation-uppercase-parse-success.output.md" "signedList = [+1, +1]"
expect_contains "$fixture_corpus_dir/escaped-reserved-identifier-parse-success.output.md" '`if` = 42'
expect_contains "$fixture_corpus_dir/tab-keyword-whitespace-parse-success.output.md" "type Maybe a = Just a | Nothing"
expect_contains "$fixture_corpus_dir/tab-keyword-whitespace-parse-success.output.md" "ability Store where"

parse_error_rc_file="$normalized_dir/transcript_decl_parse_error.rc"
if [[ ! -f "$parse_error_rc_file" ]]; then
  echo "Missing parse-error rc file: $parse_error_rc_file" >&2
  exit 1
fi
parse_error_rc="$(tr -d '\n' <"$parse_error_rc_file")"
if [[ "$parse_error_rc" != "1" ]]; then
  echo "Expected transcript_decl_parse_error rc=1, got: $parse_error_rc" >&2
  exit 1
fi

unterminated_string_rc_file="$normalized_dir/transcript_unterminated_string_parse_error.rc"
if [[ ! -f "$unterminated_string_rc_file" ]]; then
  echo "Missing parse-error rc file: $unterminated_string_rc_file" >&2
  exit 1
fi
unterminated_string_rc="$(tr -d '\n' <"$unterminated_string_rc_file")"
if [[ "$unterminated_string_rc" != "1" ]]; then
  echo "Expected transcript_unterminated_string_parse_error rc=1, got: $unterminated_string_rc" >&2
  exit 1
fi

signature_lhs_rc_file="$normalized_dir/transcript_signature_lhs_parse_error.rc"
if [[ ! -f "$signature_lhs_rc_file" ]]; then
  echo "Missing parse-error rc file: $signature_lhs_rc_file" >&2
  exit 1
fi
signature_lhs_rc="$(tr -d '\n' <"$signature_lhs_rc_file")"
if [[ "$signature_lhs_rc" != "1" ]]; then
  echo "Expected transcript_signature_lhs_parse_error rc=1, got: $signature_lhs_rc" >&2
  exit 1
fi

reserved_identifier_rc_file="$normalized_dir/transcript_reserved_identifier_parse_error.rc"
if [[ ! -f "$reserved_identifier_rc_file" ]]; then
  echo "Missing parse-error rc file: $reserved_identifier_rc_file" >&2
  exit 1
fi
reserved_identifier_rc="$(tr -d '\n' <"$reserved_identifier_rc_file")"
if [[ "$reserved_identifier_rc" != "1" ]]; then
  echo "Expected transcript_reserved_identifier_parse_error rc=1, got: $reserved_identifier_rc" >&2
  exit 1
fi

numeric_identifier_rc_file="$normalized_dir/transcript_numeric_identifier_parse_error.rc"
if [[ ! -f "$numeric_identifier_rc_file" ]]; then
  echo "Missing parse-error rc file: $numeric_identifier_rc_file" >&2
  exit 1
fi
numeric_identifier_rc="$(tr -d '\n' <"$numeric_identifier_rc_file")"
if [[ "$numeric_identifier_rc" != "1" ]]; then
  echo "Expected transcript_numeric_identifier_parse_error rc=1, got: $numeric_identifier_rc" >&2
  exit 1
fi

keyword_prefix_success_rc_file="$normalized_dir/transcript_keyword_prefix_identifier_parse_success.rc"
if [[ ! -f "$keyword_prefix_success_rc_file" ]]; then
  echo "Missing parser success rc file: $keyword_prefix_success_rc_file" >&2
  exit 1
fi
keyword_prefix_success_rc="$(tr -d '\n' <"$keyword_prefix_success_rc_file")"
if [[ "$keyword_prefix_success_rc" != "0" ]]; then
  echo "Expected transcript_keyword_prefix_identifier_parse_success rc=0, got: $keyword_prefix_success_rc" >&2
  exit 1
fi

keyword_prefix_apostrophe_success_rc_file="$normalized_dir/transcript_keyword_prefix_apostrophe_identifier_parse_success.rc"
if [[ ! -f "$keyword_prefix_apostrophe_success_rc_file" ]]; then
  echo "Missing parser success rc file: $keyword_prefix_apostrophe_success_rc_file" >&2
  exit 1
fi
keyword_prefix_apostrophe_success_rc="$(tr -d '\n' <"$keyword_prefix_apostrophe_success_rc_file")"
if [[ "$keyword_prefix_apostrophe_success_rc" != "0" ]]; then
  echo "Expected transcript_keyword_prefix_apostrophe_identifier_parse_success rc=0, got: $keyword_prefix_apostrophe_success_rc" >&2
  exit 1
fi

scientific_uppercase_success_rc_file="$normalized_dir/transcript_scientific_notation_uppercase_parse_success.rc"
if [[ ! -f "$scientific_uppercase_success_rc_file" ]]; then
  echo "Missing parser success rc file: $scientific_uppercase_success_rc_file" >&2
  exit 1
fi
scientific_uppercase_success_rc="$(tr -d '\n' <"$scientific_uppercase_success_rc_file")"
if [[ "$scientific_uppercase_success_rc" != "0" ]]; then
  echo "Expected transcript_scientific_notation_uppercase_parse_success rc=0, got: $scientific_uppercase_success_rc" >&2
  exit 1
fi

escaped_reserved_success_rc_file="$normalized_dir/transcript_escaped_reserved_identifier_parse_success.rc"
if [[ ! -f "$escaped_reserved_success_rc_file" ]]; then
  echo "Missing parser success rc file: $escaped_reserved_success_rc_file" >&2
  exit 1
fi
escaped_reserved_success_rc="$(tr -d '\n' <"$escaped_reserved_success_rc_file")"
if [[ "$escaped_reserved_success_rc" != "0" ]]; then
  echo "Expected transcript_escaped_reserved_identifier_parse_success rc=0, got: $escaped_reserved_success_rc" >&2
  exit 1
fi

escaped_symbol_error_rc_file="$normalized_dir/transcript_escaped_symbol_identifier_parse_error.rc"
if [[ ! -f "$escaped_symbol_error_rc_file" ]]; then
  echo "Missing parse-error rc file: $escaped_symbol_error_rc_file" >&2
  exit 1
fi
escaped_symbol_error_rc="$(tr -d '\n' <"$escaped_symbol_error_rc_file")"
if [[ "$escaped_symbol_error_rc" != "1" ]]; then
  echo "Expected transcript_escaped_symbol_identifier_parse_error rc=1, got: $escaped_symbol_error_rc" >&2
  exit 1
fi

tab_keyword_whitespace_success_rc_file="$normalized_dir/transcript_tab_keyword_whitespace_parse_success.rc"
if [[ ! -f "$tab_keyword_whitespace_success_rc_file" ]]; then
  echo "Missing parser success rc file: $tab_keyword_whitespace_success_rc_file" >&2
  exit 1
fi
tab_keyword_whitespace_success_rc="$(tr -d '\n' <"$tab_keyword_whitespace_success_rc_file")"
if [[ "$tab_keyword_whitespace_success_rc" != "0" ]]; then
  echo "Expected transcript_tab_keyword_whitespace_parse_success rc=0, got: $tab_keyword_whitespace_success_rc" >&2
  exit 1
fi

echo "Parser differential scaffold check passed."
