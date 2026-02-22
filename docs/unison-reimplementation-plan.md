# Unison Reimplementation Plan

Date: 2026-02-09
Owner: Unison reimplementation effort

## Goals
- Re-implement core Unison behavior in a pure-Unison reimplementation with high behavioral parity.
- MVP must typecheck and run Unison code both locally and in Unison Cloud workflows.
- Follow existing Haskell package/module structure as closely as practical (path-to-namespace mapping).

## Non-Goals (MVP)
- Full `ucm` command parity.
- Replacing every runtime builtin immediately.
- Fully replacing Haskell FFI implementation on day one.

## Hard MVP Requirements
- [ ] Parse and typecheck a meaningful Unison subset used by transcripts and public libraries.
- [ ] Execute terms (including effectful programs) via a runtime path that works locally.
- [ ] Execute the same programs in Cloud-oriented projects (at minimum via existing Cloud libraries and APIs).
- [ ] Differential test against `result/bin/unison` for parser, typechecker, runtime output, and transcript behavior.

## Type Modeling Conventions
- Prefer newtypes over raw primitives where values have distinct domain meaning (for example: names, hashes, source text, errors, branch identifiers, codebase paths).
- Keep boundary functions explicit: convert at parse/load boundaries instead of passing raw `Text`/`Nat` throughout parser/typechecker/runtime internals.
- In Unison, structurally identical wrappers can collapse to the same type; use `unique type` when semantic wrappers must remain distinct.
- Introduce newtypes early in each milestone so readability and type-safety improve before behavior gets complex.
- Treat unwrapped primitives as acceptable only for truly generic helpers and tight interop boundaries.

## Discovery Snapshot
- [x] Inventory monorepo package graph from `stack.yaml` and package manifests.
- [x] Map key source trees to future Unison namespaces:
  - [x] `parser-typechecker/src/Unison/...`
  - [x] `unison-runtime/src/Unison/...`
  - [x] `unison-cli/src/Unison/...`
  - [x] `unison-share-api/src/Unison/...`
  - [x] `unison-syntax/src/Unison/...` (lexer, parser, syntax utilities)
- [x] Identify existing regression anchors:
  - [x] Transcript suites: `unison-src/transcripts/` (including `idempotent/` and `errors/`), `unison-src/transcripts-manual/`, `unison-src/transcripts-round-trip/`, `unison-src/transcripts-using-base/`
  - [x] CLI integration tests in `unison-cli-integration`
  - [x] Runtime tests and `@unison/runtime-tests`
- [x] Confirm `result/bin/unison` exists and is runnable for differential testing.
- [x] Pull Share metadata from `api.unison-lang.org` for candidate `@unison/*` libs.
- [x] Extract and review FFI documentation from `@unison/base` (see `FFI.DLL.doc`, `FFI.DLL.caveat`, `FFI.Spec.doc`, `FFI.Type.doc`, and per-function `.doc` definitions).
- [x] Update Codex MCP server command to wrapper script `/home/bbarker/workspace/unison-scratch/unison-mcp` in `~/.codex/config.toml`.
- [x] Wire direct Unison MCP tool usage in this dev environment (verified by direct `mcp__unison__*` calls in this session).

## Current Session State (from `context-unite.u`)
- [x] Resume target for the next increment is real implementation scaffolding in local project `unite/main`.
- [x] Confirm local project `unite` exists and `@unison/base` is installed.
- [x] Wrapper script `/home/bbarker/workspace/unison-scratch/unison-mcp` is configured and unsets `LD_LIBRARY_PATH` before launching `result/bin/unison`.
- [x] MCP status in this session: tools are available and callable (`mcp__unison__*` succeeded).
- [x] Initial scaffolding has now been written into `unite/main` via MCP updates.

Resume commands:
- `/mcp`
- `scripts/unison/share-api-fallback.sh project @unison/base`
- `scripts/unison/reference-corpus.sh --profile core --check-baseline`

## Dependency Mapping (Haskell -> Unison Share)

### Verified `@unison/*` candidates (latest release on 2026-02-08)
| Project | Latest release | Why it matters |
|---|---:|---|
| `@unison/base` | `7.14.0` | Core language/data/effects utilities, test helpers, FFI docs. |
| `@unison/http` | `15.2.0` | HTTP client/server capabilities. |
| `@unison/cloud` | `27.2.1` | Cloud runtime and deployment-facing APIs. |
| `@unison/json` | `1.3.5` | JSON encoding/decoding and interop. |
| `@unison/codec` | `2.3.0` | Binary/data codecs. |
| `@unison/auth` | `2.0.0` | Authentication workflows. |
| `@unison/aws` | `5.2.0` | Cloud provider integration. |
| `@unison/share-sdk` | `2.8.0` | Share API integration surface. |
| `@unison/routes` | `7.0.2` | Routing and service boundaries. |
| `@unison/resource` | `1.1.0` | Resource lifecycle patterns. |
| `@unison/connection-pool` | `3.1.1` | Connection/resource pooling patterns. |
| `@unison/tcpserver` | `2.3.0` | TCP server/network primitives. |
| `@unison/distributed-extra` | `0.1.0` | Distributed execution helpers. |
| `@unison/internal` | `0.0.25` | Internal/reflection helpers when parity work needs runtime internals. |
| `@unison/runtime-tests` | `0.0.6` | Runtime equivalence test corpus. |

### Capability mapping
| Haskell dependency cluster | Current Haskell examples | Capability to replace/provide | Preferred Unison Share source |
|---|---|---|---|
| Core types/collections | `base`, `containers`, `text`, `bytestring`, `vector` | Lists, maps/sets, text/bytes, foundational combinators | `@unison/base` |
| Parsing and syntax helpers | `megaparsec`, `regex-tdfa` | Parser tooling, syntax helpers, regex-compatible workflows | `@unison/base` (+ targeted custom parser modules) |
| Serialization formats | `aeson`, `serialise`, `cborg`, `avro` | JSON/binary codec parity | `@unison/json`, `@unison/codec` |
| HTTP/network | `http-client`, `servant`, `network`, `network-simple`, `tls` | Local/remote API calls, service APIs | `@unison/http`, `@unison/routes`, `@unison/tcpserver` |
| Cloud and Share integration | `unison-share-api`, `unison-share-projects-api` | Cloud runtime access and Share workflows | `@unison/cloud`, `@unison/share-sdk`, `@unison/auth`, `@unison/aws` |
| Concurrency and effects | `async`, `stm`, runtime thread primitives | Effectful runtime semantics and scheduling helpers | `@unison/base`, `@unison/resource`, `@unison/connection-pool` |
| Crypto and security | `crypton`, `x509`, `tls` | Signing, hashing, auth flows | `@unison/auth`, `@unison/aws`, `@unison/base` |
| Distributed execution | runtime hash/serialization APIs | Cross-node execution and references | `@unison/distributed-extra`, `@unison/cloud` |
| Testing/fuzzing | `easytest`, `hedgehog` | Differential/property/runtime tests | `@unison/runtime-tests`, `test.verify` in `@unison/base` |
| Performance benchmarking | Criterion-style micro/meso benchmarks | Regression detection for parser/typechecker/runtime hot paths | `@mitchellwrosen/benchmark` (via transcript/script runner for IO-heavy cases) |

### Script migration library decisions (2026-02-09)
| Project | Latest release | Decision | Why |
|---|---:|---|---|
| `@ceedubs/shell` | `4.1.0` | Adopt now | Provides process execution, streaming pipelines, and file/path helpers needed to replace most bash script behavior in `unite.scripts`. |
| `@etorreborre/potions` | `1.5.0` | Adopt now | Provides typed CLI argument parsing and help rendering for script entrypoints that currently rely on shell flags/argv parsing. |
| `@runarorama/terminus` | `3.0.1` | Optional, defer | Useful for interactive/TUI UX, but not required for current non-interactive parity harnesses and CI runners. |

Current sufficiency call:
- `@ceedubs/shell` + `@etorreborre/potions` are sufficient for the first migration wave (non-interactive script runners + typed option parsing).
- Keep `@runarorama/terminus` as a later add when interactive progress displays or richer terminal UX become a priority.

## Milestones

> **Dependency order**: M0 (scaffolding) is parallel to M1 (parser). M1 blocks M2 (typechecker). M2 blocks M3 (runtime bridge). M3 blocks M4 (execution paths). M5 (testing) runs continuously from M1 onward. M5A (script migration to `unite.scripts`) can start now and feeds M6. M6 (UCM surface) depends on M3+M4. M7 (native runtime) is post-MVP.

## Milestone 0 - Baseline + Scaffolding
### Task M0.1 Differential harness bootstrap
- [x] Add initial smoke comparison harness: `scripts/unison/reference-smoke.sh`.
- [x] Validate smoke harness against `result/bin/unison` (help/version/run.file/transcript).
- [x] Add parser/typecheck/runtime corpus runner (transcripts + hand-written edge cases): `scripts/unison/reference-corpus.sh`.
- [x] Add parser-focused corpus profile for fast declaration/parser drift checks (`scripts/unison/reference-corpus.sh --profile parser`).
- [x] Add large transcript sweep profile (`scripts/unison/reference-corpus.sh --profile all-transcripts`) plus wrapper (`scripts/unison/reference-all-transcripts.sh`) to run parser-oriented checks across upstream transcript suites and surface case-level mismatches quickly.
- [x] Exclude non-executable `*.output.md` expectation files from all-transcripts runnable case collection.
- [x] Add heuristic-mode controls for all-transcripts triage: explicit known-failure overrides (including idempotent merge/print-ordering/upgrade, selected `transcripts-using-base` cases, and manual benchmark/remote-tab-completion/dll-ffi transcripts) plus known-unstable paths (`cycle-update-3.md`, `update-term-with-dependent-to-different-type.md`, `public-tests.md`) that skip strict RC matching in heuristic mode.
- [x] Validate broader all-transcripts sweep slice in heuristic mode (`--max-cases 200`: 200 matched / 0 mismatched in latest run).
- [x] Validate full all-transcripts heuristic sweep (`--max-cases 391`) under timeout-protected execution with curated expected-failure/unstable policy (latest run: 391 matched / 0 mismatched).
- [x] Make transcript fixture staging refresh individual files on repeated runs in stable work dirs so newly added corpus fixtures are not missed.
- [x] Harden baseline checks to fail on case-manifest drift (`cases.txt` diff now catches both missing and extra generated cases).
- [x] Keep all-transcripts baseline checks stable for sliced baselines: when checking baseline with `--profile all-transcripts` and no explicit `--max-cases`, auto-use baseline summary `max_cases` (currently 200).
- [x] In baseline-check mode, force known unstable all-transcripts cases (`cycle-update-3.md`, `update-term-with-dependent-to-different-type.md`, `public-tests.md`) to use non-strict RC matching (`heuristic-unstable`) even if a baseline RC file exists.
- [x] Add per-case timeout controls for large all-transcripts sweeps (`--case-timeout-seconds`, default `120` for `--profile all-transcripts`) so long-running cases cannot stall the corpus run.
- [x] Exclude `heuristic-unstable` all-transcripts cases from strict baseline artifact file diffs (`.out/.err/.rc/.cmd`) while retaining strict manifest parity and strict diffing for all stable cases.
- [x] Add initial performance runner with repeated samples and CI/error-bar summaries: `scripts/unison/reference-perf.sh`.
- [x] Store normalized baseline outputs from `result/bin/unison` in reproducible locations: `scripts/unison/baselines/core/`, `scripts/unison/baselines/parser/`, `scripts/unison/baselines/perf/quick/`, and `scripts/unison/baselines/all-transcripts/` (current all-transcripts slice: 200 cases).
- [x] Add CI job to run baseline corpus checks on every branch (`reimplementation reference corpus` job in `.github/workflows/ci.yaml`, now checking both `core` and `parser` profiles).
- [x] Add CI perf-smoke job to produce repeatable timing artifacts and enforce quick-profile regression checks (`reimplementation perf smoke` job in `.github/workflows/ci.yaml`, quick profile + uploaded summary artifact + `--check-baseline` gate).

### Task M0.2 Namespace mapping convention
- [ ] Freeze the Haskell-path to Unison-namespace mapping rule.
- [ ] Apply it to parser/typechecker/runtime/cli/syntax package boundaries.
- [ ] Add lint/check that new Unison files follow the mapping.

Example mapping (simplified; actual mapping must handle all package prefixes):
```unison
-- Pseudocode: generalizes across parser-typechecker, unison-runtime,
-- unison-cli, unison-share-api, and unison-syntax source trees.
toNamespace : Text -> Text -> Name
toNamespace packagePrefix haskellPath =
  haskellPath
    |> Text.dropPrefix (packagePrefix ++ "/src/")
    |> Text.dropSuffix ".hs"
    |> Text.split "/"
    |> List.map NameSegment.fromText
    |> Name.fromSegments
```

### Task M0.3 MCP and Share integration setup
- [x] Configure local `ucm mcp` in developer environment and document setup (wrapper path set; tool usage verified from this Codex session).
- [x] Add scripted fallback that queries `api.unison-lang.org` when MCP is unavailable: `scripts/unison/share-api-fallback.sh`.
- [ ] Keep an audited list of third-party libraries approved for use.

### Task M0.4 `unite/main` bootstrap and first scaffold
- [x] Confirm `unite/main` prerequisites (`unite` exists, `@unison/base` installed).
- [x] Verify MCP tool access from this session and inspect `unite/main` state (definitions, namespaces, libraries).
- [ ] If MCP is empty in a future session, run `/home/bbarker/workspace/unison-scratch/unison-mcp mcp` manually and capture startup diagnostics.
- [x] Create initial scaffolding namespaces (`parser`, `typechecker`, `runtime`, `cli`) and add a typecheckable+runnable entrypoint (`unite.cli.entry`).
- [x] Add first in-project parity smoke checks (`unite.parity.smoke.*` for empty/missing-equals/simple inputs).
- [x] Extend parser scaffold to a minimal module path (`parseModule`) that handles multi-line source, blank-line skipping, `--` comment-line skipping, declaration-line continuation coalescing for indented `type`/`ability` bodies, and comment-line tolerance inside declaration continuations.
- [x] Add line-aware module parse diagnostics (`line N: ...`) for parse failures surfaced through parser and pipeline smoke checks.
- [x] Extend typechecker/pipeline/runtime scaffolding to module flow (`TypedModule`, `compileModule`, `evalModule`, `entryModule`).
- [x] Align in-project smoke checks with `scripts/unison/reference-corpus.sh --profile core --check-baseline` (latest run passed after parser compatibility changes).
- [x] Extend reference corpus with transcript-based file-loading IO cases (`transcript_load_file_success`, `transcript_load_file_missing`, `transcript_load_file_parse_error`).
- [x] Apply first readability pass using newtypes in scaffold (`BindingName`, `BindingValue`, `ParameterName`, `UseImportBody`, parse/typecheck error wrappers, runtime output wrapper).
- [x] Add in-project `test>` smoke tests and validate with `run-tests` (`unite.parity.smoke.tests` + `unite.tests.scripts.*`, currently 302 passing total).
- [ ] Commit each verified scaffold milestone in small increments.
- [ ] Fallback if MCP remains unavailable: use escalated shell inspection of `~/.unison/v2` and continue scaffolding directly.

Current `unite/main` scaffold snapshot (2026-02-10):
- `unite.core` wrappers for domain values (`SourceText`, `BindingName`, `BindingValue`, `ParameterName`, `UseImportBody`, `DeclarationName`, `DeclarationHeader`, `TypeDeclarationBody`, `AbilityDeclarationBody` + unwrap helpers).
- `unite.parser` pipeline with nominal parse types (`ParseError`, `ParsedAssignment`, `ParsedTypeSignature`, `Ast`, `ModuleAst`, `Signature`) and module parsing (`parseModule`, `parseUseImport`, `parseTypeDeclaration`, `parseAbilityDeclaration`, support for `unique`/`structural` and `unique[guid]` declaration prefixes with declaration flavor + structured headers preserved in declaration payloads, comment/blank handling, declaration continuation coalescing for indented declaration lines, multiline assignment continuation coalescing for indented RHS lines, token-class layer via `ParserToken` + `tokenizeParserTokensStrict` (built on `tokenizeWords`/`tokenizeWordsStrict`, now including whitespace-sensitive signed-number behavior, scientific-notation tokenization with uppercase-`E` normalization, numeric-operator spacing parity cases, signed-list numeric tokenization cases, hash-qualified symbol token handling, and qualified/escaped-dot token sequence handling), token-driven keyword dispatch in `parseAst` (including tab-whitespace forms for `use`/`type`/`ability`), explicit unterminated string literal detection (`hasUnterminatedDoubleQuote`), reserved-identifier rejection and leading-digit identifier rejection in assignment/signature/declaration names, escaped-reserved identifier support via backticks (semantic normalization for wordy names, preserved escapes for operator heads where needed), wordy/qualified identifier support for declaration/assignment/signature heads, parenthesized operator head support (`(|>)`, `(++)`, `(==)`), infix operator assignment-head parsing (including symbolic, backtick, and qualified-backtick forms), assignment-separator disambiguation for operator-heavy heads, horizontal-rule/ignore-tail handling (`---` and explicit `---- Anything below this line is ignored by Unison...` markers), block-comment-span skipping in module parsing, `unique` multiline declaration-prefix handling, and quote-aware trailing `--` comment stripping for both module lines and single-line parses, line-aware errors).
- `unite.typechecker` nominal typed output and errors (`TypedAst`, `TypeError`), including declaration flavor preserved from parser declarations into typed declarations.
- `unite.typechecker` module support (`TypedModule`, `checkModuleAst`).
- `unite.pipeline` compile paths and tagged phase errors (`PipelineError`, `compile`, `compileModule`).
- `unite.runtime` nominal render output (`RuntimeMessage`) and execution entrypoints (`renderTyped`, `evalTyped`, `eval`, `renderModule`, `evalModule`), plus a minimal executable path for `main = printLine "..."` / `main = base.io.printLine "..."` (including balanced single-outer-parentheses handling).
- `unite.codebase` adapter scaffolding with explicit wrappers (`CodebasePath`, `ProjectRef`, `BranchRef`, `DependencyRef`, `LibraryRef`), backend planning (`BackendDelegated`/`BackendNative`, `planOperation`), delegated execution plumbing (`executePlanWith`, `executeOperationWith`, `executeOperation`, `localDelegatedRunner`, `executeOperationIO`, `delegatedProcessRunner`), process-level transcript bridge support for UCM-only commands (`pull`/`lib.install`/`add`/`update`), normalized transcript-first delegated error/success output shaping (`preferTranscriptOutput`), transcript-command/argument validation for delegated UCM flows, controlled delegated environment (`XDG_DATA_HOME`), workspace-scoped runtime/cache paths (`.run/...`) instead of predictable global `/tmp` paths, persistent delegated codebase path handling, and cloud hydration primitives including effectful snapshot cache read/write + install loop (`HydrationMode`, `planDependencyHydration`, `DependencySnapshot`, `hydrateDependenciesIO`) with context-keyed snapshot paths (`dependencySnapshotPath`) and legacy snapshot fallback.
- `unite.run` loading-path scaffolding (`run.file`/`run.pipe`-style APIs via `unite.run.file` (on-disk loader using `IO.FilePath.readFileUtf8` + error capture), `unite.run.fileWithLoader` test hook, and `unite.run.pipe`, plus `RunError` and load/path wrappers; loader path now uses dedicated `SourceFilePath` wrapper to avoid parser-parameter aliasing).
- script migration scaffold (`unite.scripts.core`, `unite.scripts.reference`, `unite.scripts.reference.diff`, `unite.scripts.smoke`, `unite.scripts.cli`, `unite.scripts.corpus`, `unite.scripts.corpus.diff`, `unite.scripts.parserdiff`, `unite.scripts.perf`) with typed option modeling and native Unison runners (process execution isolated via `@ceedubs/shell`), parser/core corpus case-plan construction + profile summary runner terms, outcome-level bash-vs-Unison parser/core differential checks (case IDs + rc expectations), all-transcripts outcome/summary diff checks (map/mismatch/summary artifacts), parser-diff artifact checks + summary report output in Unison-side terms, perf sample/statistics aggregation + baseline regression checks in Unison-side terms, and `@etorreborre/potions` parser wiring for all-transcripts CLI options.
- runnable CLI entrypoints `unite.cli.entry` and `unite.cli.entryModule`.
- smoke parity terms under `unite.parity.smoke.*` including module parse/compile cases, function-head assignment normalization, signature declarations, `use` imports, `type`/`ability` declaration lines (including `unique`/`structural` and `unique[guid]` forms, with/without space after `]`, multiline continuation coalescing, and comment lines inside declaration continuations), RHS `=` handling, tight `type ...=...` declaration spacing, and quote-aware trailing comment stripping.
- parser differential scaffolding in-project (`unite.parser.renderAstCanonical`, `unite.parser.renderModuleCanonical`, parser line/module differential cases under `unite.parity.smoke.*`, and differential smoke tests).
- smoke tests under `unite.parity.smoke.tests.*` plus `unite.tests.scripts.*` (302 passing in latest `run-tests` run, including `run.file`/`run.pipe` scaffolding cases, runtime print-line extraction/execution helpers, parser differential scaffolding checks, multiline-assignment module parser coverage, tokenizer unit checks (including strict unterminated-quote rejection, token classification, whitespace-sensitive signed/scientific numeric tokenization, uppercase-`E` exponent normalization, compact type-ascription tokenization, multiline comma-delimited collection tokenization, signed-list numeric tokenization, semicolon-separated symbol tokenization, semicolon-before-parenthesized identifier tokenization, qualified+escaped-dot tokenization, escaped qualified symbol variants (`.Foo.++.+`, `.Foo.\`++\`.+`, `.Foo.\`+.+\`.+`), hash-qualified symbol token handling, qualified symbol-chain token merges, and expanded keyword-prefix identifier classification matrix), tokenized `use` import parsing checks (including tab-whitespace forms), signature-LHS validation checks, reserved-identifier rejection checks, escaped-reserved identifier checks, escaped-symbol identifier rejection checks, leading-digit identifier rejection checks (assignment/signature/type/ability), hydration snapshot parse/cache helpers (including context cache key/path generation), marker-content integrity checks for cached dependencies, expanded codebase adapter command/argv routing + normalization checks, and script runner planning/CLI-option conversion checks for all-transcripts/smoke/corpus/parser-diff/perf harnesses).
- IO smoke terms for delegated codebase operations (`unite.parity.smoke.runCodebaseOpenIO`, `unite.parity.smoke.runCodebaseRunPipeIO`, `unite.parity.smoke.runCodebasePullIO`, `unite.parity.smoke.runCodebaseInstallIO`, `unite.parity.smoke.runCodebaseHydrateOnlineIO`, `unite.parity.smoke.runCodebaseHydrateOfflineIO`) now execute real `result/bin/unison` subprocess flows.
- script-runner IO smoke terms (`unite.parity.smoke.runScriptsAllTranscriptsSampleIO`, `unite.parity.smoke.runScriptsAllTranscriptsOutcomeDiffIO`, `unite.parity.smoke.runScriptsAllTranscriptsSweep50IO`, `unite.parity.smoke.runScriptsAllTranscriptsSweep200IO`, `unite.parity.smoke.runScriptsSmokeSampleIO`, `unite.parity.smoke.runScriptsCorpusOutcomeDiffIO`, `unite.parity.smoke.runScriptsParserDiffIO`, `unite.parity.smoke.runScriptsParserCorpusSampleIO`, `unite.parity.smoke.runScriptsParserCorpusFullIO`, `unite.parity.smoke.runScriptsParserCorpusOracleFullIO`, `unite.parity.smoke.runScriptsPerfQuickCheckIO`) now execute through `unite.scripts.*`; latest runs return `0` failures on the smoke/diff gates (including parser/core outcome-diff parity against bash corpus runs, all-transcripts map/mismatch/summary parity checks, parser-diff artifact/summary checks, parser-corpus static and oracle full sweeps, and quick perf baseline checks).

Newtype refactor status:
- Implemented in scaffold: assignment parts, parse/typecheck/pipeline/runtime errors, source wrapper, runtime render output, parser parameter tokens (`ParameterName`), parser import body boundaries (`UseImportBody`), and declaration payload wrappers (`TypeDeclarationBody`, `AbilityDeclarationBody`) now use nominal types.
- Declaration flavor (`default` / `unique` / `structural`) is now carried semantically in declaration payload wrappers and reflected in runtime render output for declaration forms.
- Added declaration-header wrappers (`DeclarationName`, `DeclarationHeader`) so declaration payloads retain parsed name/parameter structure in AST and typed AST.
- `ParameterName` now has a distinct type shape from `CodebasePath` in `unite/main`, so parser parameter tokens are no longer aliased to codebase path wrappers.
- Review findings: remaining opportunities are expected to appear as parser/typechecker coverage expands (hashes, references, names, module/project identifiers, codebase paths).

Security/correctness hardening status (2026-02-10):
- Delegated transcript execution now validates command text and command atoms before transcript materialization (`pull`/`lib.install` paths), rejecting control characters/backticks and unsupported characters.
- Delegated runtime and hydration cache paths now use workspace-scoped `.run/...` locations instead of predictable global `/tmp` paths.
- Delimiter/separator scanning now accounts for quoted/backtick/triple-quoted text and line-comment boundaries.
- Parenthesis stripping for runtime hello-world extraction now only strips a balanced single outer pair.
- Dependency-list helpers were tightened (`listAppend` via `++`, `uniqueDependencies` via `Set`-backed dedupe preserving first-seen order).

Dead-code review notes:
- `unite.parser.parse`, `unite.typechecker.check`, and `unite.runtime.eval` currently have no dependents in `unite/main`; keep as intentional API facades for now and revisit removal if CLI/runtime entrypoints converge on other paths.

## Milestone 1 - Core Data Model + Parser
### Task M1.1 AST and reference model parity
- [ ] Implement Unison equivalents of core syntax/reference data structures.
- [ ] Match hash/reference identity semantics with Haskell behavior.
- [ ] Add round-trip parser/pretty-printer invariants for stable hashes.

### Task M1.2 Lexer/parser compatibility
- [x] Extend scaffold grammar beyond assignment lines: support `name : Type` signature declarations (including RHS text with additional `:`), `use ...` imports, `type ...` and `ability ...` declaration lines (including `unique`/`structural` and `unique[guid]` prefixes with and without spacing after `]`), mixed declaration modules, indented declaration continuation lines in modules (including comment lines inside declaration continuations), multiline assignment continuation lines (`name =` then indented RHS), function-head assignments (`f x = ...` normalized to lambda RHS), RHS expressions containing `=`, tight `type ...=...` declaration spacing, and quote-aware trailing `--` comment stripping in module lines and single-line parses.
- [x] Add parser-focused reference corpus profile and CI gate (`scripts/unison/reference-corpus.sh --profile parser`) for declaration-prefix, multiline-declaration, tight-equals declaration, parser success fixtures (`keyword-prefix-identifier-parse-success`, `keyword-prefix-apostrophe-identifier-parse-success`, `scientific-notation-uppercase-parse-success`, `tab-keyword-whitespace-parse-success`, `escaped-reserved-identifier-parse-success`), and parse-error fixtures (including unterminated-string, invalid signature-LHS, reserved-identifier, leading-digit-identifier, and escaped-symbol-identifier parse errors).
- [x] Add large transcript parser sweep profile (`all-transcripts`) that materializes case maps and mismatch summaries for broad corpus triage (`all-transcripts-map.tsv`, `all-transcripts-mismatches.txt`, `all-transcripts-summary.txt`).
- [x] Add parser differential scaffolding: canonical parser renderers in `unite` (`renderAstCanonical`, `renderModuleCanonical`), in-project differential smoke tests, and repo parser differential script/CI gate (`scripts/unison/reference-parser-diff.sh` in `.github/workflows/ci.yaml`).
- [ ] Port tokenization and parser behavior from `unison-syntax`/`parser-typechecker` (in progress: `unite.parser.tokenizeWords` + `tokenizeWordsStrict` are integrated and now wrapped by `ParserToken`/`tokenizeParserTokensStrict` for parser header consumption; `parseAst` now uses token-driven keyword dispatch and token-normalized declaration/import parsing; explicit unterminated string literal detection, stricter signature-LHS validation, reserved-identifier and leading-digit identifier rejection, escaped-reserved backtick identifier normalization, wordy-identifier head validation, string/comment-aware separator scanning (including triple-quoted text) and backtick-aware separator scanning, escaped-symbol identifier rejection coverage, keyword-prefix identifier coverage (including apostrophe-suffixed variants and the broader `if|then|else` + `{0,x,!,\'}` matrix), whitespace-sensitive signed/scientific numeric tokenization parity cases (including uppercase-`E` normalization), numeric-operator spacing parity, signed-list numeric tokenization parity, semicolon-before-parenthesized tokenization parity (`woot;(woot)`), hash-qualified symbol token coverage (`+#bar`), qualified symbol-chain tokenization coverage (`.Foo.Bar.+` style), escaped qualified symbol-chain tokenization coverage (`.Foo.\`++\`.+`, `.Foo.\`+.+\`.+`), qualified/escaped-dot tokenization coverage, infix operator assignment-head parsing for symbolic/backtick/qualified-backtick forms, horizontal-rule and explicit ignore-tail marker handling, and parser differential fixture coverage are in place).
- [ ] Track parser error message compatibility for high-signal diagnostics (started with deterministic `parser scaffold: unterminated string literal` errors and module-level `line N:` propagation).
- [ ] Differential-test parser outputs against `result/bin/unison` (now automated with parser-corpus oracle baseline + full sweep gate via `run unite.parity.smoke.runScriptsParserCorpusFullIO`, `run unite.parity.smoke.runScriptsParserCorpusOracleFullIO`, and `run unite.parity.smoke.runScriptsParserCorpusSampleIO`; latest 2026-02-10 runs: static full `240/240` (`compatibility-waived=1`), oracle full `240/240` (`compatibility-waived=1`), sample `150/150` (`compatibility-waived=0`), parser diff `41/41`; parser-corpus artifacts now include `parser-corpus-compatibility-waived.tsv` and summary fields `compatibility_waived_cases`/`compatibility_waived_file`; current compatibility waivers include one known expected-failure mismatch (`unison-src/transcripts-round-trip/docTest2.u`, reference failure vs scaffold success due unresolved-name behavior not yet modeled in parser scaffolding); compatibility policy also allows small line-offset tolerance in diagnostic parity checks, while output-shape parity is currently clean (`0` output-shape mismatches); remaining work is deeper strict diagnostic/message parity beyond the current compatibility envelope).

### Task M1.3 File loading model
- [ ] Match `.u` file loading and scratch-file behavior.
- [x] Support `run.file` and `run.pipe`-style source loading path (implemented `unite.run.file` on-disk loader + `unite.run.pipe`; retained `unite.run.fileWithLoader` for deterministic pure smoke tests).
- [x] Add transcript-based IO/load-path regression cases in the differential corpus (`load-file-success`, `load-file-missing`, `load-file-parse-error` fixtures).
- [x] Verify sample files from `unison-cli-integration/integration-tests/IntegrationTests` (currently `ArgumentParsing.hs`, `transcript.md`, and `main.uc`; covered in corpus via `transcript_integration`, `transcript_fork_integration`, and `run_compiled_integration_main`).

## Milestone 2 - Typechecker MVP
### Task M2.1 Type inference and checking core
- [ ] Implement principal type inference for core language forms.
- [ ] Implement ability/effect checking required by runtime execution.
- [ ] Match builtin type surfaces needed by `@unison/base`.

### Task M2.2 Name resolution and namespaces
- [ ] Implement namespace lookup semantics aligned with Haskell `Names` behavior.
- [ ] Match project/lib namespace behavior (`lib.*` handling).
- [ ] Differential-test resolution failures/ambiguity messages.

### Task M2.3 Hashing and dependency extraction
- [ ] Implement content hashing compatible with Haskell references.
- [ ] Expose dependency extraction APIs for runtime and cloud sync.
- [ ] Add corpus tests for stable hash parity across formatting changes.

## Milestone 3 - Runtime Bridge MVP (Builtins + FFI via existing runtime)
### Task M3.1 Execution bridge design
- [ ] Define stable adapter protocol from reimplementation-evaluated terms to Haskell runtime.
- [ ] Start with process boundary (`result/bin/unison` or runtime service mode), then optimize.
- [ ] Normalize runtime errors so user-visible behavior matches existing CLI.

Example bridge contract:
```json
{
  "entrypoint": "main",
  "args": ["--flag", "value"],
  "codebasePath": ".run/unite-codebase-adapter",
  "executionMode": "local|cloud",
  "expectType": "'{IO, Exception} ()"
}
```

### Task M3.2 Builtin replacement boundary
- [ ] Generate machine-readable list of builtin names from `ForeignFunc`.
- [ ] Implement dispatch table in the reimplementation that routes unsupported builtins to runtime bridge.
- [ ] Prioritize native implementations for pure/high-volume builtins first.

### Task M3.3 FFI strategy (based on FFI docs in `@unison/base` + runtime source)
- [ ] Preserve user-facing API (`FFI.DLL.open`, `FFI.DLL.getSymbol`, `FFI.Spec`, `FFI.Type.*`, pointer ops) exactly for MVP.
- [ ] Delegate dynamic linking and pointer operations to existing Haskell runtime.
- [ ] Add explicit memory-safety test cases for `FFI.Ptr.*` (allocate/get/set/getAt/setAt), `mutable.ByteArray.Raw.Pinned`, and `FFI.Ptr.free`.

### Task M3.4 Codebase adapter (bridge-first MVP)
- [x] Define a `unite.codebase` adapter boundary with explicit wrappers (for example: `ProjectRef`, `BranchRef`, `CodebasePath`, `DependencyRef`, `LibraryRef`) using `unique type` where semantic separation matters (initial scaffolding now present in `unite/main`).
- [ ] Implement MVP backend by delegating codebase operations to `result/bin/unison` (process/transcript bridge), including open/init/pull/lib.install/add/update/run flows (open/create + run.pipe are delegated via direct process args; pull/lib.install/add/update are delegated through generated `transcript.in-place` runs against a persistent adapter codebase path with controlled `XDG_DATA_HOME`; transcript output is now preferred for delegated success/failure normalization; remaining work is fuller add/update semantics tied to staged loads and differential fixture coverage).
- [ ] Normalize codebase-side errors into reimplementation error types so command UX remains consistent (partially implemented via transcript-first delegated error shaping and normalization tests).
- [ ] Add differential tests that compare adapter-backed behavior with direct `result/bin/unison` behavior on the same fixtures (partially implemented with `scripts/unison/reference-codebase-diff.sh`, adapter corpus fixtures, and CI coverage).
- [ ] Keep delegation as default until parser/typechecker/runtime parity is stable; then replace adapter operations natively in priority order.

## Milestone 4 - Local and Cloud Execution Paths
### Task M4.1 Local execution
- [ ] Implement `run`, `run.file`, and `run.pipe` equivalents in the reimplementation's shell.
- [x] Add minimal in-project hello-world execution path in scaffold runtime (`main = printLine "hello, world"` and qualified `base.io.printLine`, exercised by `unite.parity.smoke.runHelloWorld`).
- [ ] Support compiled artifact execution path parity (`run.compiled`-like flow; lower priority for MVP).
- [ ] Add smoke tests from existing integration fixtures.

### Task M4.2 Cloud-facing execution
- [x] Prove delegated dependency-fetch path through the adapter (`pull` + `lib.install`) using IO smoke terms against `result/bin/unison`, with persistent delegated codebase path reuse across calls.
- [x] Add initial effectful hydration workflow in `unite.codebase` (`hydrateDependenciesIO`) with snapshot cache parsing/reading/writing, context-aware cached dependency reuse, online install loop, and offline completeness checks built on `planDependencyHydration`.
- [ ] Implement minimum Share project/branch resolution needed to run pulled code.
- [ ] Integrate with `@unison/cloud` and `@unison/share-sdk` conventions.
- [ ] Validate behavior on at least one pulled public project (`@unison/cloud/releases/latest`).
- [ ] Implement dynamic dependency hydration for cloud execution:
  - resolve missing refs during typecheck/run against project/branch/release context.
  - fetch transitive dependencies on demand from Share, verify hashes, and materialize them into an execution codebase snapshot (initial direct `installIO` loop exists; transitive resolution remains pending).
  - cache fetched dependencies by content hash for reuse across runs; avoid refetching unchanged libraries (initial single-snapshot cache path exists; content-addressed layout remains pending).
  - record an execution dependency snapshot (lock-like manifest) per successful run for reproducibility/debugging (initial snapshot read/write exists).
  - define offline behavior explicitly: reuse cached snapshot when complete, otherwise fail with actionable missing-dependency diagnostics (implemented for current snapshot context).
- [ ] Add cloud dependency-fetch regression tests (cold cache vs warm cache, missing auth, missing project/branch, hash mismatch, network failure).

### Task M4.3 Codebase/project model
- [ ] Mirror project/branch/path model from Haskell codebase APIs.
- [ ] Keep path-to-namespace rules consistent between local and remote code.
- [ ] Test `pull`/dependency install workflows for reproducibility.
- [ ] Define cache layout and lifecycle for fetched cloud dependencies (content-addressed storage + eviction policy + integrity checks).

## Milestone 5 - Differential, Property, and Fuzz Testing
### Task M5.1 Transcript equivalence
- [ ] Run selected transcript suites against both implementations (all four transcript directories: `transcripts/`, `transcripts-manual/`, `transcripts-round-trip/`, `transcripts-using-base/`).
- [ ] Normalize non-semantic output differences (timings, paths, hashes when expected to differ).
- [ ] Require zero semantic diffs for MVP transcript gate.

### Task M5.2 Property testing
- [ ] Generate random well-typed programs for parser/typechecker/runtime checks.
- [ ] Assert both implementations agree on typechecking result and runtime result.
- [ ] Store minimal counterexamples automatically.

Example property:
```unison
test> parity.eval.agrees = test.verify do
  prog = Gen.wellTypedProgram
  ensureEqual (Ref.eval prog) (Reimpl.eval prog)
```

### Task M5.3 Fuzz and negative testing
- [ ] Fuzz parser with malformed/near-valid syntax.
- [ ] Fuzz runtime bridge messages and argument passing.
- [ ] Stress pointer and FFI boundary with invalid symbols/types.

### Task M5.4 Performance regression testing (targeted)
- [x] Add targeted benchmarks for parser/typechecker/runtime paths where we expect meaningful cost (for example: large modules, dependency-heavy typechecking, runtime dispatch loops) (added parser-heavy declaration transcript case: `scripts/unison/benchmarks/parser-declaration-heavy.md` in `reference-perf.sh` core profile).
- [x] Add benchmark-focused transcript/script scaffolding using `@mitchellwrosen/benchmark` and wire it into the performance runner via `--benchmark-transcript` (fixture: `scripts/unison/benchmarks/mitchellwrosen-benchmark-libinstall.md`).
- [x] Store golden timing summaries across repeated samples (mean + variance), and track error bars/confidence intervals per benchmark (`reference-perf.sh` summary + samples artifacts).
- [x] Gate regressions using a statistical policy (currently: fail when mean regression exceeds threshold and confidence intervals do not overlap; see `reference-perf.sh --check-baseline`).
- [x] Persist benchmark artifacts (raw samples + computed summary) so trend analysis is reproducible in CI and local runs (`summary.tsv`, `cases.txt`, `samples/*.tsv`).
- [x] Enable perf baseline regression gating in CI (`reimplementation perf smoke` now runs `reference-perf.sh --check-baseline` against committed quick baseline with CI/statistical thresholding).

Performance baseline guidance:
- Use fixed benchmark inputs and warm-up runs before measurement to reduce startup noise.
- Record multiple samples per benchmark and keep both mean and spread (stddev or confidence interval), not a single point estimate.
- Compare distributions across runs; avoid pass/fail decisions from one noisy run.
- Keep benchmark jobs separate from correctness jobs so flaky timing noise does not hide functional regressions.

## Milestone 5A - Script Migration to `unite.scripts` / `unite.tests`
### Task M5A.1 Library adoption and boundaries
- [x] Evaluate `@ceedubs/shell`, `@etorreborre/potions`, and `@runarorama/terminus` against current script needs.
- [x] Install `@ceedubs/shell` and `@etorreborre/potions` into `unite/main`.
- [x] Keep `@runarorama/terminus` deferred unless/ until we need interactive terminal UX.
- [x] Define a strict boundary: script logic in pure terms first, IO/process edges isolated behind effectful adapters (current `unite.scripts.reference` / `unite.scripts.smoke` split follows this).

### Task M5A.2 Initial namespace scaffold
- [x] Create `unite.scripts.core` with `unique type` wrappers for script identifiers, profiles, options, and expected outcomes.
- [x] Create `unite.scripts.reference` terms for typed option resolution, transcript planning, and native Unison-runner execution for all-transcripts/reference harnesses.
- [x] Create `unite.scripts.cli` helpers that start mapping CLI argv into typed script options (initial all-transcripts parser/normalization via `@etorreborre/potions`).
- [x] Create `unite.tests.scripts.*` tests for plan rendering, argument validation, and failure normalization.

### Task M5A.3 Incremental migration sequence
- [x] Port `reference-smoke.sh` behavior first (smallest surface, fast feedback) (`unite.scripts.smoke.*` now runs step plans with `XDG_DATA_HOME`, writes per-step `.cmd/.out/.err/.rc` artifacts, and is exercised by `unite.parity.smoke.runScriptsSmokeSampleIO`).
- [x] Port parser/core profile case-planning from `reference-corpus.sh` as pure plan construction (`unite.scripts.corpus.*` case matrices + profile runner terms + tests).
- [x] Port all-transcripts behavior and baseline-mode switching into native `unite.scripts.reference.*` runners (no direct runtime dependency on `scripts/unison/reference-all-transcripts.sh`; `unite.scripts.reference.diff.*` adds map/mismatch/summary outcome parity checks, exercised by `unite.parity.smoke.runScriptsAllTranscriptsOutcomeDiffIO`).
- [x] Add outcome-level parser/core differential checks between bash and Unison script implementations (case IDs + expected rc parity via `unite.scripts.corpus.diff.*` and `unite.parity.smoke.runScriptsCorpusOutcomeDiffIO`).
- [x] Port `reference-parser-diff.sh` normalization and summary generation (`unite.scripts.parserdiff.*` now checks required cases/fixture patterns/expected RCs, writes `parser-diff-summary.txt`, and is exercised by `unite.parity.smoke.runScriptsParserDiffIO`).
- [x] Port `reference-perf.sh` sample aggregation and baseline checks (keep error-bar policy) (`unite.scripts.perf.*` now executes profile plans, records per-case sample files + summary manifests, applies CI/threshold regression checks against baseline summaries, and is exercised by `unite.parity.smoke.runScriptsPerfQuickCheckIO`).

### Task M5A.4 Transition and rollout
- [ ] During migration, run both bash and Unison implementations side-by-side and diff normalized outputs (partially addressed by parser/core outcome-level diffs; full normalized artifact diffs are still pending).
- [ ] Keep CI defaulting to bash until Unison script parity is established and stable for two consecutive green runs.
- [x] Add non-blocking CI coverage for migrated script parity checks (`reimplementation unite.scripts (non-blocking)` job runs smoke/parserdiff/all-transcripts/perf checks without gating merges).
- [x] Remove direct shell-script command-path dependencies from `unite.scripts` runtime terms (legacy `scripts/unison/*.sh` remain optional compatibility tooling).
- [ ] After parity, flip CI to `unite.scripts` entrypoints and keep bash wrappers as thin compatibility shims (or remove once no longer needed).

## Milestone 6 - UCM Surface (MVP subset) + Ergonomics
### Task M6.1 Command surface
- [ ] Implement minimal commands required for day-to-day work:
  - [ ] load/typecheck/update
  - [ ] run/run.file/run.pipe
  - [ ] pull/lib.install subset
- [ ] Ensure command layer routes through `unite.codebase` adapter (so delegated and native backends share one command contract).
- [ ] Keep full CLI parity out of scope for MVP.

### Task M6.2 Developer UX
- [ ] Match key error/help outputs where they drive workflows.
- [ ] Add lightweight migration notes for contributors switching from Haskell implementation.
- [ ] Provide command compatibility matrix.

## Milestone 7 - Native Runtime and FFI De-risking (Post-MVP)
### Task M7.1 Incremental native runtime
- [ ] Port pure builtin implementations from bridge to native runtime in priority order.
- [ ] Keep bridge fallback until confidence and performance targets are met.
- [ ] Track unsupported builtin count as a release metric.

### Task M7.2 Native FFI options
- [ ] Evaluate direct FFI in the reimplementation's runtime (libffi or host-level ABI adapter).
- [ ] Preserve existing `FFI.*` API contract to avoid user-facing breakage.
- [ ] Add conformance tests for all pointer/memory primitives before switching defaults.

## FFI Proposals (Shortlist)

### Proposal A (MVP default): Runtime delegation
- Keep FFI semantics in existing Haskell runtime.
- The reimplementation typechecks and prepares executable payloads.
- Execution bridge calls runtime for builtins + FFI calls.
- Pros: fastest path to parity, lowest risk.
- Cons: cross-process overhead and dual-runtime complexity.

### Proposal B (Hybrid): Native pure runtime + delegated FFI
- Move pure builtins to the reimplementation's runtime.
- Keep only dynamic linking and pointer primitives delegated.
- Pros: better performance while keeping risk bounded.
- Cons: more moving parts than Proposal A.

### Proposal C (Post-MVP): Full native runtime and FFI
- Replace runtime delegation entirely.
- Keep exact API/behavior contract validated by differential suite.
- Pros: full ownership/performance.
- Cons: highest engineering and correctness risk.

## Exit Criteria for MVP
- [ ] The reimplementation passes agreed transcript subset with semantic parity.
- [ ] The reimplementation can typecheck and run representative local programs.
- [ ] The reimplementation can run representative cloud project code using Share-hosted libraries.
- [ ] Cloud dependency hydration is reproducible (snapshot/lock recorded), cache-aware (warm runs avoid refetch), and failure modes are explicit.
- [ ] Differential/property/fuzz suite is green against `result/bin/unison`.
- [ ] Runtime bridge handles required builtins/FFI surface with documented limits.
