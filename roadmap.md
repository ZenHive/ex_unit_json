# ex_unit_json

**Status:** In Progress
**Last Updated:** 2026-01-08

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

**Tech Stack:**
- Elixir 1.18+ (for built-in `:json` module)
- ExUnit (formatter API)
- No external dependencies for core functionality

**Development Timeline:** 1-2 weeks

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

---

### Task 1: Project Structure Setup

**Goal:** Set up project with correct directory structure and dependencies.

**Dependencies:** None

**Approach:**
1. Verify mix.exs configuration (already created)
2. Create directory structure:
   - `lib/ex_unit_json/formatter.ex`
   - `lib/ex_unit_json/json_encoder.ex`
   - `lib/mix/tasks/test_json.ex`
3. Add basic module stubs
4. Verify `mix compile` succeeds

**Testing Requirements:**
- [ ] Project compiles without warnings

**Acceptance Criteria:**
- [ ] All directories and stub files created
- [ ] `mix compile` succeeds
- [ ] `mix test` passes (default generated tests)

**Estimated Complexity:** Simple

---

### Task 2: JSON Encoder - Basic Test Serialization

**Goal:** Implement `ExUnitJSON.JSONEncoder` to convert ExUnit test structs to JSON-serializable maps.

**Dependencies:** Task 1

**Approach:**
1. Create `ExUnitJSON.JSONEncoder` module
2. Implement `encode_test/1` - converts `%ExUnit.Test{}` to map
3. Implement `encode_state/1` - converts test state tuples to strings
4. Implement `encode_tags/1` - filters and converts tags
5. Handle the `:ex_unit_no_meaningful_value` marker

**Key Functions:**
```elixir
def encode_test(test) do
  %{
    name: to_string(test.name),
    module: to_string(test.module),
    file: test.tags[:file],
    line: test.tags[:line],
    state: encode_state(test.state),
    duration_us: test.time,
    tags: encode_tags(test.tags)
  }
end
```

**Testing Requirements:**
- [ ] Unit: `encode_test/1` with passed test
- [ ] Unit: `encode_test/1` with failed test
- [ ] Unit: `encode_test/1` with skipped test
- [ ] Unit: `encode_test/1` with excluded test
- [ ] Unit: `encode_state/1` for all state types
- [ ] Edge: Unicode in test names
- [ ] Edge: Very long module names

**Acceptance Criteria:**
- [ ] All test states correctly encoded
- [ ] Tags properly filtered (no internal keys exposed)
- [ ] Output is JSON-serializable (no structs, PIDs, etc.)
- [ ] Tests pass

**Estimated Complexity:** Medium

---

### Task 3: JSON Encoder - Failure Serialization

**Goal:** Extend encoder to serialize failure details including assertion errors with left/right values.

**Dependencies:** Task 2

**Approach:**
1. Implement `encode_failure/1` - handles `{:failed, failures}` tuple
2. Implement `encode_single_failure/1` - handles `{kind, error, stacktrace}`
3. Implement `encode_assertion_error/1` - extracts left/right/expression
4. Implement `encode_stacktrace/1` - converts stacktrace to JSON
5. Handle non-assertion errors (exits, throws)

**Key Functions:**
```elixir
defp encode_single_failure({kind, error, stacktrace}) do
  base = %{
    kind: to_string(kind),
    message: Exception.message(error),
    stacktrace: encode_stacktrace(stacktrace)
  }
  maybe_add_assertion_details(base, error)
end
```

**Testing Requirements:**
- [ ] Unit: Assertion error with == comparison
- [ ] Unit: Assertion error with pattern match
- [ ] Unit: Non-assertion error (raise)
- [ ] Unit: Exit error
- [ ] Unit: Throw error
- [ ] Unit: Stacktrace encoding
- [ ] Edge: Very long assertion values (truncation?)
- [ ] Edge: Binary/non-printable values in assertions

**Acceptance Criteria:**
- [ ] All failure types correctly serialized
- [ ] Assertion left/right values captured
- [ ] Stacktraces include file/line info
- [ ] Output remains valid JSON

**Estimated Complexity:** Medium

---

### Task 4: Formatter GenServer - Event Collection

**Goal:** Implement `ExUnitJSON.Formatter` GenServer that receives ExUnit events and accumulates results.

**Dependencies:** Task 3

**Approach:**
1. Create `ExUnitJSON.Formatter` as GenServer
2. Implement `init/1` - initialize state with options
3. Implement `handle_cast/2` for:
   - `{:suite_started, opts}` - capture seed
   - `{:test_finished, test}` - accumulate test
   - `{:module_finished, module}` - track module failures
4. Store accumulated tests in state

**Key Structure:**
```elixir
defstruct [
  :seed,
  :start_time,
  tests: [],
  modules: [],
  opts: []
]
```

**Testing Requirements:**
- [ ] Unit: init/1 creates correct initial state
- [ ] Unit: Handles :suite_started event
- [ ] Unit: Accumulates :test_finished events
- [ ] Unit: Handles :module_finished for setup_all failures
- [ ] Integration: Receives events from real ExUnit run

**Acceptance Criteria:**
- [ ] GenServer starts successfully
- [ ] All events properly accumulated
- [ ] State maintains correct order
- [ ] No crashes on unexpected events

**Estimated Complexity:** Medium

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

**Acceptance Criteria:**
- [ ] Complete JSON document output on suite finish
- [ ] Summary statistics accurate
- [ ] Version field present for future compatibility
- [ ] Valid JSON parseable by any JSON parser

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

**Acceptance Criteria:**
- [ ] `mix test.json` produces JSON output
- [ ] All `mix test` arguments supported (files, line numbers)
- [ ] Exit code 0 on pass, non-zero on failure
- [ ] `mix help test.json` shows documentation

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

**Acceptance Criteria:**
- [ ] `mix test.json --summary-only` outputs only summary
- [ ] `mix test.json --failures-only` outputs only failed tests
- [ ] Flags can be combined
- [ ] Documentation updated

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

**Testing Requirements:**
- [ ] Unit: --output writes to file
- [ ] Unit: File contains valid JSON
- [ ] Integration: Full workflow with file output
- [ ] Edge: Invalid file path handling

**Acceptance Criteria:**
- [ ] `mix test.json --output results.json` works
- [ ] README complete with examples
- [ ] CHANGELOG.md created
- [ ] `mix hex.build` succeeds
- [ ] All tests pass

**Estimated Complexity:** Simple

---

## Phase 2: Future Enhancements

**Note:** Phase 2 begins after Phase 1 is validated with real usage.

- `--list` flag for test discovery without running
- JSON Lines format (`--format jsonl`) for streaming
- Captured logs inclusion option
- Integration with CI systems (GitHub Actions output)
- Custom output templates

---

## Technical Decisions

### Architecture Patterns
- **GenServer Formatter:** Accumulate all results, output at end (buffered, not streaming)
- **Separate Encoder:** JSON encoding logic isolated for testability
- **Application.get_env for Options:** Pass options from Mix task to formatter

### Key Libraries/Dependencies
- **None for core:** Use Elixir 1.18's built-in `:json` module
- **ex_doc:** Documentation only (dev dependency)

### Compatibility
- **Elixir 1.18+:** Required for `:json` module
- **Earlier versions:** Could add Jason as optional dependency (Phase 2)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ExUnit formatter API changes | Low | Medium | Pin to stable API, test against multiple Elixir versions |
| Large test suites produce huge JSON | Medium | Low | Add `--failures-only` flag, consider streaming in Phase 2 |
| Non-serializable values in assertions | Medium | Medium | Robust `inspect/1` fallback for all values |

---

## Open Questions

- [x] Hex package vs Elixir core? → Hex package
- [x] Streaming vs buffered JSON? → Buffered (with filtering options)
- [ ] Should we truncate very long assertion values?
- [ ] Include captured logs by default or opt-in?

---

## References

- [ExUnit.Formatter docs](https://hexdocs.pm/ex_unit/ExUnit.Formatter.html)
- [ExUnit source - CLIFormatter](https://github.com/elixir-lang/elixir/blob/main/lib/ex_unit/lib/ex_unit/cli_formatter.ex)
- [Plan file](/Users/efries/.claude/plans/mossy-plotting-puffin.md)
