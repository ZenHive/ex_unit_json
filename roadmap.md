# ex_unit_json

**Status:** Phase 1 Complete (Task 8 of 8 complete)
**Last Updated:** 2026-01-09

## Project Overview

**Goal:** Provide AI-friendly JSON test output for ExUnit, enabling AI editors like Claude Code to efficiently parse and reason about test results.

**Target Users:**
- AI editors (Claude Code, Cursor, etc.)
- CI/CD systems needing structured test output
- Developers wanting machine-parseable test results

**Success Metrics:**
- Claude Code can parse output without grep/tail/sed
- All ExUnit test states correctly represented in JSON
- Package published to Hex.pm
- Stable JSON Schema v1 documented and enforced by tests

**Tech Stack:**
- Elixir 1.18+ (for built-in `:json` module)
- ExUnit (formatter API)
- No external dependencies for core functionality

**Phases:** 2 (MVP Core + Future Enhancements)

---

## Phase 1: MVP Core Features

**Goal:** Working JSON formatter with basic filtering options via `mix test.json`

**Duration:** ~8 tasks

**Success Criteria:**
- [x] `mix test.json` outputs valid JSON with all test results
- [x] `--summary-only` flag works
- [x] `--failures-only` flag works
- [x] All edge cases handled (Unicode, long values, setup failures)
- [x] Tests pass with good coverage (150 tests)
- [ ] Published to Hex.pm
- [x] Output ordering is deterministic (file, line, name)

---

### Task 1: Project Structure Setup ✅

**Status:** Complete (2026-01-08) - See [CHANGELOG.md](CHANGELOG.md#task-1-project-structure-setup)

**Acceptance Criteria:**
- [x] All directories and stub files created
- [x] `mix compile` succeeds
- [x] `mix test` passes (4 tests)

---

### Task 2: JSON Encoder - Basic Test Serialization ✅

**Status:** Complete (2026-01-09) - See [CHANGELOG.md](CHANGELOG.md#task-2-json-encoder---basic-test-serialization)

**Acceptance Criteria:**
- [x] All test states correctly encoded
- [x] Tags properly filtered (no internal keys exposed)
- [x] Output is JSON-serializable (no structs, PIDs, etc.)
- [x] Tests pass (28 encoder tests)
- [x] State mapping documented: `nil → "passed"`, `{:failed, _} → "failed"`, `{:invalid, _} → "invalid"`, `{:skipped, _} → "skipped"`, `{:excluded, _} → "excluded"`
- [x] Truncation policy: non-serializable values use `inspect/1`

---

### Task 3: JSON Encoder - Failure Serialization ✅

**Status:** Complete (2026-01-09) - See [CHANGELOG.md](CHANGELOG.md#task-3-json-encoder---failure-serialization)

**Acceptance Criteria:**
- [x] All failure types correctly serialized
- [x] Assertion left/right values captured
- [x] Stacktraces include file/line info
- [x] Output remains valid JSON
- [x] Stacktrace frames are structured, not just strings
- [x] Truncation policy respected (10,000 char limit)

---

### Task 4: Formatter GenServer - Event Collection ✅

**Status:** Complete (2026-01-09) - See [CHANGELOG.md](CHANGELOG.md#task-4-formatter-genserver---event-collection)

**Acceptance Criteria:**
- [x] GenServer starts successfully
- [x] All events properly accumulated
- [x] State maintains correct order
- [x] No crashes on unexpected events
- [x] Option plumbing uses centralized `ExUnitJSON.Config`

---

### Task 5: Formatter GenServer - JSON Output ✅

**Status:** Complete (2026-01-09) - See [CHANGELOG.md](CHANGELOG.md#task-5-formatter-genserver---json-output)

**Acceptance Criteria:**
- [x] Complete JSON document output on suite finish
- [x] Summary statistics accurate
- [x] Version field present for future compatibility
- [x] Valid JSON parseable by any JSON parser
- [x] Summary reflects full suite even when `tests` are filtered
- [x] Tests array order is deterministic

---

### Task 6: Mix Task - Basic Implementation ✅

**Status:** Complete (2026-01-09) - See [CHANGELOG.md](CHANGELOG.md#task-6-mix-task---basic-implementation)

**Acceptance Criteria:**
- [x] `mix test.json` produces JSON output
- [x] All `mix test` arguments supported (files, line numbers)
- [x] Exit code 0 on pass, non-zero on failure
- [x] `mix help test.json` shows documentation
- [x] Options validated via `ExUnitJSON.Config`

---

### Task 7: Filtering Options ✅

**Status:** Complete (2026-01-09) - See [CHANGELOG.md](CHANGELOG.md#task-7-filtering-options)

**Acceptance Criteria:**
- [x] `mix test.json --summary-only` outputs only summary
- [x] `mix test.json --failures-only` outputs only failed tests
- [x] Flags can be combined
- [x] Documentation updated
- [x] Summary reflects full suite regardless of filters

---

### Task 8: Output File Option & Polish ✅

**Status:** Complete (2026-01-09) - See [CHANGELOG.md](CHANGELOG.md#task-8-output-file-option--polish)

**Acceptance Criteria:**
- [x] `mix test.json --output results.json` works
- [x] README complete with examples
- [x] CHANGELOG.md created
- [x] `mix hex.build` succeeds
- [x] All tests pass (150 tests)
- [x] JSON Schema v1 documented and tests validate against it

---

## Phase 1.5: AI-Friendly Enhancements ✅

**Status:** Complete (2026-01-09)

Features added to improve AI agent usability:

- [x] **Relative paths** - File paths are now relative to project root (e.g., `test/my_test.exs` instead of full absolute path)
- [x] **Tighter truncation** - Reduced limits for assertion values (500 chars) to reduce output size
- [x] **`--compact` flag** - JSONL output with minimal fields, one test per line:
  - Keys: `f` (file:line), `n` (name), `s` (state), `e` (error message, failed only)
  - Summary line at end: `{"summary":{...}}`
  - Dramatically reduces output size for large test suites

---

## Phase 2: Future Enhancements

**Note:** Prioritized by ROI (Benefit/Difficulty). Higher priority = better ROI.

### High Priority (ROI > 2.0)

#### `--first-failure` [D:2/B:5 → 2.5] 🎯
Quick iteration mode - only output first failure in detail.
```bash
mix test.json --first-failure
```

#### `--filter-out "pattern"` [D:4/B:8 → 2.0] 🎯
Exclude failures matching pattern from output. Mark as `"filtered": true` in JSON rather than hiding.
```bash
mix test.json --filter-out "credentials" --filter-out "API key"
```
Use case: Filter expected failures (missing credentials, rate limits) to focus on real bugs.

### Medium Priority (ROI 1.0-2.0)

#### `--group-by-error` [D:6/B:7 → 1.2] 📋
Group failures by similar error message. Shows root causes at a glance:
```json
{"error_groups": [{"pattern": "Not all sent parameters", "count": 47, "example": "..."}]}
```
Use case: When 100 tests fail with the same root cause, show it once.

### Other Future Features

- `--list` flag for test discovery without running
- Captured logs inclusion option (`--include-logs`)
- Integration with CI systems (GitHub Actions output)
- Custom output templates
- Optional `Jason` fallback for Elixir versions without `:json`

---

## Technical Decisions

### Architecture Patterns
- **GenServer Formatter:** Accumulate all results, output at end (buffered, not streaming)
- **Separate Encoder:** JSON encoding logic isolated for testability
- **Application.get_env for Options:** Pass options from Mix task to formatter
- **Config Module:** Centralize option parsing/validation in `ExUnitJSON.Config`
 - **Codec Boundary:** Encoder returns plain maps/lists; actual JSON serialization only in formatter

### Key Libraries/Dependencies
- **Primary:** Use Elixir 1.18+'s built-in `:json` module when available
- **Fallback:** Use `Jason` if `:json` is unavailable (optional dependency)
- **ex_doc:** Documentation only (dev dependency)

### Compatibility
- **Elixir 1.18+:** Preferred (native `:json`)
- **Earlier versions:** Supported via optional Jason fallback

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ExUnit formatter API changes | Low | Medium | Pin to stable API, test against multiple Elixir versions |
| Large test suites produce huge JSON | Medium | Low | Add `--failures-only` flag, consider streaming in Phase 2 |
| Non-serializable values in assertions | Medium | Medium | Robust `inspect/1` fallback for all values |
| Users without Elixir 1.18 | Medium | Medium | Provide Jason fallback and document compatibility |

---

## Open Questions

- [x] Hex package vs Elixir core? → Hex package
- [x] Streaming vs buffered JSON? → Buffered (with filtering options)
- [x] Should we truncate very long assertion values? → Yes, with sensible, documented defaults
- [ ] Include captured logs by default or opt-in? → Opt-in (planned for Phase 2)

---

## References

- [ExUnit.Formatter docs](https://hexdocs.pm/ex_unit/ExUnit.Formatter.html)
- [ExUnit source - CLIFormatter](https://github.com/elixir-lang/elixir/blob/main/lib/ex_unit/lib/ex_unit/cli_formatter.ex)

---

## Output Schema v1

Root
- version: integer (1)
- seed: integer
- summary: object
- tests: array of test objects (omitted with `--summary-only`; filtered with `--failures-only`)
- meta: object (optional; includes truncation settings)

Summary
- total: integer
- passed: integer
- failed: integer
- skipped: integer
- excluded: integer
- duration_us: integer (microseconds)
- result: string ("passed" | "failed")

Test
- name: string
- module: string
- file: string
- line: integer
- state: string ("passed" | "failed" | "skipped" | "excluded")
- duration_us: integer (microseconds)
- tags: object (filtered)
- failures: array of failure objects (only when failed)

Failure
- kind: string (e.g., "error", "exit", "throw", "assertion")
- message: string
- assertion: object (optional; for assertion errors)
  - left: string (inspected/truncated)
  - right: string (inspected/truncated)
  - expr: string
- stacktrace: array of frames

Frame
- file: string
- line: integer
- module: string (optional)
- function: string (optional)
- arity: integer (optional)
- app: string (optional)

Metadata
- truncation: object
  - value_char_limit: integer (default: 500)
  - expr_char_limit: integer (default: 200)
  - collection_item_limit: integer (default: 50)
  - printable_limit: integer (default: 500)

Ordering
- Tests are sorted by `file`, then `line`, then `name` for determinism.

Versioning
- Breaking schema changes bump `version` and are noted in CHANGELOG.
