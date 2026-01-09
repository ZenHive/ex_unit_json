# ex_unit_json

**Status:** In Progress (Task 4 of 8 complete)
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
- [ ] `mix test.json` outputs valid JSON with all test results
- [ ] `--summary-only` flag works
- [ ] `--failures-only` flag works
- [ ] All edge cases handled (Unicode, long values, setup failures)
- [ ] Tests pass with good coverage
- [ ] Published to Hex.pm
- [ ] Output ordering is deterministic (file, line, name)

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

### Task 5: Formatter GenServer - JSON Output

**Goal:** Implement suite_finished handler that outputs complete JSON.

**Dependencies:** Task 4

**Approach:**
1. Implement `handle_cast({:suite_finished, times_us}, state)`
 2. Build complete output structure with summary
3. Use `:json.encode/1` for JSON serialization
4. Output to stdout (default) or file (if configured)
5. Handle output options from Application.get_env
6. Sort `tests` deterministically by file, line, name unless configured otherwise
7. Include `version` and truncation metadata in root document

**Output Structure:**
```json
{
  "version": 1,
  "seed": 12345,
  "summary": {
    "total": 10,
    "passed": 8,
    "failed": 2,
    "skipped": 0,
    "excluded": 0,
    "duration_us": 123456,
    "result": "failed"
  },
  "tests": [...]
}
```

**Testing Requirements:**
- [ ] Unit: Summary calculation correct
- [ ] Unit: JSON output is valid
- [ ] Unit: Output to stdout works
- [ ] Integration: Full test run produces valid JSON
- [ ] Edge: Empty test suite
- [ ] Edge: All tests excluded
- [ ] Unit: Summary unaffected by filtering flags

**Acceptance Criteria:**
- [ ] Complete JSON document output on suite finish
- [ ] Summary statistics accurate
- [ ] Version field present for future compatibility
- [ ] Valid JSON parseable by any JSON parser
- [ ] Summary reflects full suite even when `tests` are filtered
- [ ] Tests array order is deterministic

**Estimated Complexity:** Medium

---

### Task 6: Mix Task - Basic Implementation

**Goal:** Create `mix test.json` task that configures ExUnit and runs tests with JSON output.

**Dependencies:** Task 5

**Approach:**
1. Create `Mix.Tasks.Test.Json` module
2. Parse command-line arguments
3. Configure ExUnit with `ExUnitJSON.Formatter`
4. Delegate to `Mix.Tasks.Test`
5. Handle exit codes properly
6. Define `@switches` (summary_only, failures_only, output) and document `mix help test.json`

**Key Implementation:**
```elixir
defmodule Mix.Tasks.Test.Json do
  use Mix.Task

  @shortdoc "Run tests with JSON output"

  def run(args) do
    {opts, test_args} = OptionParser.parse!(args, switches: @switches)
    Application.put_env(:ex_unit_json, :opts, opts)

    # Replace default formatter
    ExUnit.configure(formatters: [ExUnitJSON.Formatter])

    Mix.Task.run("test", test_args)
  end
end
```

**Testing Requirements:**
- [ ] Unit: Option parsing works correctly
- [ ] Integration: `mix test.json` runs and outputs JSON
- [ ] Integration: Exit code reflects test results
- [ ] Integration: Test file arguments pass through
- [ ] Unit: `mix help test.json` shows documented switches

**Acceptance Criteria:**
- [ ] `mix test.json` produces JSON output
- [ ] All `mix test` arguments supported (files, line numbers)
- [ ] Exit code 0 on pass, non-zero on failure
- [ ] `mix help test.json` shows documentation
- [ ] Options validated via `ExUnitJSON.Config`

**Estimated Complexity:** Medium

---

### Task 7: Filtering Options

**Goal:** Implement `--summary-only` and `--failures-only` flags.

**Dependencies:** Task 6

**Approach:**
1. Add switches to Mix task: `summary_only`, `failures_only`
2. Pass options to formatter via Application.put_env
3. In formatter, check options when building output:
   - `--summary-only`: Omit `tests` array entirely
   - `--failures-only`: Filter tests array to failed only
4. Test both flags

**Testing Requirements:**
- [ ] Unit: --summary-only produces summary-only output
- [ ] Unit: --failures-only filters to failures
- [ ] Unit: Both flags together work correctly
- [ ] Integration: Real test run with flags
- [ ] Unit: Summary counts unchanged by filters

**Acceptance Criteria:**
- [ ] `mix test.json --summary-only` outputs only summary
- [ ] `mix test.json --failures-only` outputs only failed tests
- [ ] Flags can be combined
- [ ] Documentation updated
- [ ] Summary reflects full suite regardless of filters

**Estimated Complexity:** Simple

---

### Task 8: Output File Option & Polish

**Goal:** Add `--output FILE` option and polish for release.

**Dependencies:** Task 7

**Approach:**
1. Add `output` switch to Mix task
2. In formatter, write to file instead of stdout if specified
3. Update README with full documentation
4. Add CHANGELOG.md
5. Verify all tests pass
6. Prepare for Hex.pm publish
7. Document JSON Schema v1 in README and include example
8. Add a small golden test suite (pass, fail, skip, excluded, setup_all failure)

**Testing Requirements:**
- [ ] Unit: --output writes to file
- [ ] Unit: File contains valid JSON
- [ ] Integration: Full workflow with file output
- [ ] Edge: Invalid file path handling
- [ ] Integration: Golden suite produces expected JSON (schema + ordering)

**Acceptance Criteria:**
- [ ] `mix test.json --output results.json` works
- [ ] README complete with examples
- [ ] CHANGELOG.md created
- [ ] `mix hex.build` succeeds
- [ ] All tests pass
- [ ] JSON Schema v1 documented and tests validate against it

**Estimated Complexity:** Simple

---

## Phase 2: Future Enhancements

**Note:** Phase 2 begins after Phase 1 is validated with real usage.

- `--list` flag for test discovery without running
- JSON Lines format (`--format jsonl`) for streaming
- Captured logs inclusion option
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
  - value_char_limit: integer (default: 10_000)
  - collection_item_limit: integer (default: 100)
  - printable_limit: integer (default: 4096)

Ordering
- Tests are sorted by `file`, then `line`, then `name` for determinism.

Versioning
- Breaking schema changes bump `version` and are noted in CHANGELOG.
