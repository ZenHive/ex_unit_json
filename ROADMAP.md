# ex_unit_json

**Status:** Phase 2 In Progress (Published to Hex.pm)

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
- [x] Tests pass with good coverage
- [x] Published to Hex.pm (v0.1.3)
- [x] Output ordering is deterministic (file, line, name)

---

### Task 1: Project Structure Setup ✅

**Status:** Complete (2026-01-08) - See [CHANGELOG.md](CHANGELOG.md#task-1-project-structure-setup)

**Acceptance Criteria:**
- [x] All directories and stub files created
- [x] `mix compile` succeeds
- [x] `mix test` passes

---

### Task 2: JSON Encoder - Basic Test Serialization ✅

**Status:** Complete (2026-01-09) - See [CHANGELOG.md](CHANGELOG.md#task-2-json-encoder---basic-test-serialization)

**Acceptance Criteria:**
- [x] All test states correctly encoded
- [x] Tags properly filtered (no internal keys exposed)
- [x] Output is JSON-serializable (no structs, PIDs, etc.)
- [x] Tests pass
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
- [x] All tests pass
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

### Completed

#### Umbrella Project Support ✅ [D:3/B:7 → 2.3] (v0.4.2)
`mix test.json` from an umbrella root produces a single merged document instead of being overwritten by the last child's suite. See [CHANGELOG.md](CHANGELOG.md#v042-2026-04-18). Contributed by @talkingdonkeyz (PR #1).

#### Default to Failures-Only Output ✅ [D:3/B:9 → 3.0] (v0.3.0)
Breaking change: `mix test.json` now outputs only failed tests by default. Use `--all` to include passing tests. Optimized for AI agents where passing tests are noise.

#### Code Coverage with `--cover` ✅ [D:5/B:7 → 1.4] (v0.4.0/v0.4.1)
`--cover` enables coverage collection. JSON includes `coverage` object with total percentage, per-module coverage, and uncovered line numbers. Use `--cover-threshold N` to fail when coverage drops below N%.

#### Warn-by-Default for `--failed` Usage ✅ [D:3/B:9 → 3.0]
When `.mix_test_failures` exists and you're running without `--failed`, automatically shows a tip suggesting focused options:
```
TIP: 3 previous failure(s) exist. Consider:
  mix test.json --failed
  mix test.json test/unit/ --failed
  mix test.json --only integration --failed
```
- Warning skipped when: `--failed` used, file/dir targeted, tag filters used, `--no-warn` passed
- Optional strict enforcement via `config :ex_unit_json, enforce_failed: true`
- Solves AI assistant problem of forgetting `--failed` during iteration

#### Smart `--failed` Hint ✅ [D:2/B:6 → 3.0]
When `.mix_test_failures` exists and you're running without `--failed`, prints a hint to stderr suggesting `--failed` for faster iteration. Also warns if the failures file is stale (>2 hours old).
```
Hint: 3 test(s) failed previously. Use --failed to re-run only those.
Note: .mix_test_failures is 3 hours old. Consider a full run if you changed shared setup.
```

#### `--first-failure` ✅ [D:2/B:5 → 2.5]
Quick iteration mode - only output first failure in detail.
```bash
mix test.json --first-failure
```

#### `--filter-out "pattern"` ✅ [D:4/B:8 → 2.0]
Mark failures matching pattern as `"filtered": true` in JSON. Use case: Filter expected failures (missing credentials, rate limits) to focus on real bugs.
```bash
mix test.json --filter-out "credentials" --filter-out "API key"
```

#### `--group-by-error` ✅ [D:6/B:7 → 1.2]
Group failures by similar error message. Shows root causes at a glance:
```json
{"error_groups": [{"pattern": "Not all sent parameters", "count": 47, "example": {...}}]}
```
Use case: When 100 tests fail with the same root cause, show it once.

### High Priority (ROI > 2.0)

#### Consistent `failure_message` Field [D:2/B:7 → 3.5] ⚠️ Schema v2
Populate the top-level `failure_message` field from `failures[0].message` when present. Currently often `null`, forcing users to drill into the failures array.

**Note:** This is a schema change. Will require Schema v2 bump since v1 already published.

**Files to update:**
- `lib/ex_unit_json/json_encoder.ex` - Implementation
- `ROADMAP.md` - Output Schema section
- `README.md` - Schema documentation
- `AGENT.md` - AI usage guide
- `~/.claude/includes/ex-unit-json.md` - Global Claude include (user's system)

**Current workaround:**
```bash
jq -r '.tests[] | select(.state == "failed") | .failures[0].message[0:100]'
```

#### `--filter-in "pattern"` [D:2/B:5 → 2.5]
Inverse of `--filter-out`: only show failures matching a pattern. Use case: focus on specific error categories.
```bash
# Show only timeout-related failures
mix test.json --quiet --failures-only --filter-in "timeout|GenServer"
```

#### `--min-duration MS` Filter [D:2/B:4 → 2.0]
Only output tests taking longer than specified milliseconds. Use case: find slow tests for optimization.
```bash
# Only show tests taking > 5 seconds
mix test.json --quiet --min-duration 5000
```

### Medium Priority (ROI 1.0-2.0)

#### Error Type Classification [D:5/B:6 → 1.2]
Automatic categorization of failure types. Helps AI identify patterns faster without parsing messages.
```json
{
  "failures": [{
    "message": "...",
    "error_type": "assertion",      // or "crash", "timeout", "protocol_error"
    "error_category": "api_error"   // extracted from message patterns
  }]
}
```

#### `--group-by TAG` Option [D:6/B:6 → 1.0]
Group failures by custom tags or module prefixes. Useful for large multi-service test suites.
```bash
# Group by module prefix
mix test.json --quiet --group-by-module-prefix "CCXT.Exchanges"
```
Output:
```json
{
  "groups": {
    "binance": {"total": 15, "failed": 3, "tests": [...]},
    "bybit": {"total": 12, "failed": 0, "tests": [...]}
  }
}
```

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
- error_groups: array of error group objects (only with `--group-by-error`)
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

Error Group (only with `--group-by-error`)
- pattern: string (first line of error message, max 200 chars)
- count: integer
- example: object
  - name: string
  - module: string
  - file: string
  - line: integer

Ordering
- Tests are sorted by `file`, then `line`, then `name` for determinism.

Versioning
- Breaking schema changes bump `version` and are noted in CHANGELOG.
