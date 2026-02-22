# Reimplementation Reference Tooling

## Scripts

- `reference-smoke.sh`
  - quick sanity checks against a reference `unison` binary.
  - covers help/version plus small `run.file` and `transcript` checks.

- `reference-corpus.sh`
  - curated parser/typecheck/runtime corpus runner with normalized artifacts.
  - includes parser-focused, large transcript-sweep, and codebase-adapter-focused profiles (`--profile parser`, `--profile all-transcripts`, `--profile adapter`) for targeted parity checks.
  - parser/core profiles include declaration edge fixtures for `unique[...]` prefixes, multiline continuations, tight `type ...=...` spacing, keyword-prefix apostrophe identifiers, and uppercase scientific-notation token behavior.
  - `all-transcripts` profile sweeps the upstream transcript corpus (`unison-src/transcripts*` + integration transcript files), writes a case map (`all-transcripts-map.tsv`), and writes mismatch summaries.
  - baseline checks now enforce `cases.txt` manifest parity (catching both missing and extra cases), not just per-case artifact diffs.
  - known unstable all-transcripts cases (currently `cycle-update-3.md`, `update-term-with-dependent-to-different-type.md`, and `public-tests.md`) are matched non-strictly in both heuristic and baseline-check modes, and are excluded from strict baseline artifact file diffs.
  - all-transcripts runs use a per-case timeout by default (`--case-timeout-seconds 120`) to prevent long-running transcripts from blocking full sweeps; override with `--case-timeout-seconds N`.
  - adapter profile includes `pull`, `lib.install`, and `add`/`update` success/failure transcript fixtures.
  - supports baseline maintenance and drift checks.

- `reference-all-transcripts.sh`
  - convenience wrapper for `reference-corpus.sh --profile all-transcripts`.
  - supports `--update-baseline`/`--check-baseline` and optional `--max-cases` for quick triage subsets.
  - defaults to `--check-baseline` when a baseline exists; otherwise runs in heuristic expected-exit mode.
  - in baseline-check mode without `--max-cases`, automatically uses the baseline summary `max_cases` (currently `200`) to keep sliced baselines stable.
  - intended for large parser-oriented corpus sweeps and binary-vs-baseline deltas.

- `reference-parser-diff.sh`
  - parser-focused differential scaffold check.
  - wraps parser baseline checks and verifies key parser-output expectations from parser fixtures.
  - intended for CI parser drift gating.

- `reference-codebase-diff.sh`
  - codebase-adapter-focused differential scaffold check.
  - wraps adapter baseline checks and verifies key output expectations from adapter fixtures.
  - validates `pull`/`lib.install` success patterns and `add`/`update` failure patterns.

- `reference-perf.sh`
  - repeated-sample performance runner for transcript/script IO paths.
  - core profile includes a parser-heavy declaration transcript case for parser regression signal.
  - writes mean/stddev/stderr/95% CI summaries and supports baseline regression checks.
  - intended for golden performance tracking (error bars + thresholded regression gate).

- `share-api-fallback.sh`
  - direct Share API helper for environments where MCP is unavailable.
  - supports project metadata, readme lookup, and search queries.

## Common commands

Update core baseline:

```bash
scripts/unison/reference-corpus.sh --profile core --update-baseline
```

Check current binary against core baseline:

```bash
scripts/unison/reference-corpus.sh --profile core --check-baseline
```

Run only smoke profile:

```bash
scripts/unison/reference-corpus.sh --profile smoke
```

Run parser-focused profile:

```bash
scripts/unison/reference-corpus.sh --profile parser
```

Run all-transcripts profile directly:

```bash
scripts/unison/reference-corpus.sh --profile all-transcripts
```

Run all-transcripts wrapper:

```bash
scripts/unison/reference-all-transcripts.sh
```

Run all-transcripts wrapper with baseline diff:

```bash
scripts/unison/reference-all-transcripts.sh --check-baseline
```

Update all-transcripts baseline:

```bash
scripts/unison/reference-all-transcripts.sh --update-baseline
```

Run codebase-adapter-focused profile:

```bash
scripts/unison/reference-corpus.sh --profile adapter
```

Run parser differential scaffold check:

```bash
scripts/unison/reference-parser-diff.sh
```

Run codebase adapter differential scaffold check:

```bash
scripts/unison/reference-codebase-diff.sh
```

Run quick perf samples:

```bash
scripts/unison/reference-perf.sh --profile quick --samples 5 --warmup 1
```

Check quick perf run against committed quick baseline:

```bash
scripts/unison/reference-perf.sh --profile quick --samples 5 --warmup 1 --check-baseline
```

Update perf baseline:

```bash
scripts/unison/reference-perf.sh --profile core --samples 20 --warmup 3 --update-baseline
```

Check perf run against baseline:

```bash
scripts/unison/reference-perf.sh --profile core --samples 20 --warmup 3 --check-baseline
```

Include a benchmark-focused transcript (for example, using `@mitchellwrosen/benchmark`):

```bash
scripts/unison/reference-perf.sh \
  --profile quick \
  --samples 20 \
  --warmup 3 \
  --benchmark-transcript scripts/unison/benchmarks/mitchellwrosen-benchmark-libinstall.md
```

Query latest release for `@unison/base` without MCP:

```bash
scripts/unison/share-api-fallback.sh project @unison/base
```
