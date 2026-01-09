# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## Phase 1: MVP Core Features

### Task 1: Project Structure Setup

**Completed:** 2026-01-08

**What was done:**
- Created `lib/ex_unit_json/formatter.ex` - GenServer stub with struct and typespecs
- Created `lib/ex_unit_json/json_encoder.ex` - Encoder module with function stubs and specs
- Created `lib/mix/tasks/test_json.ex` - Mix task stub with option parsing
- Updated `lib/ex_unit_json.ex` with comprehensive moduledoc
- Added 4 module existence tests

**Files created:**
- `lib/ex_unit_json/formatter.ex`
- `lib/ex_unit_json/json_encoder.ex`
- `lib/mix/tasks/test_json.ex`

**Verification:**
- `mix compile --warnings-as-errors` passes
- `mix test` passes (4 tests)

---

### Task 2: JSON Encoder - Basic Test Serialization

**Completed:** 2026-01-09

**What was done:**
- Implemented `encode_test/1` - converts `%ExUnit.Test{}` to JSON-serializable map
- Implemented `encode_state/1` - converts test state tuples to strings (nil→passed, failed, skipped, excluded, invalid)
- Implemented `encode_tags/1` - filters internal ExUnit keys and converts values to JSON-safe types
- Added `encode_tag_value/1` - handles atoms, strings, numbers, booleans, lists, maps, and non-serializable values
- Added `encoded_test` type with full field documentation
- Handles `:ex_unit_no_meaningful_value` marker
- Filters keys starting with `ex_` prefix
- 28 comprehensive unit tests covering all edge cases

**Key implementation details:**
- Struct type enforced in function signature: `def encode_test(%ExUnit.Test{} = test)`
- Pattern matching in function heads for state encoding
- Boolean guards checked before atom guards (booleans are atoms in Elixir)
- Non-serializable values (PIDs, refs) safely converted via `inspect/1`
- Nested structures (maps, lists) recursively encoded

**Files modified:**
- `lib/ex_unit_json/json_encoder.ex` - Full implementation
- `test/ex_unit_json/json_encoder_test.exs` - 28 tests

**Also in this commit:**
- Removed unused `jason` dependency (using built-in `:json`)
- Updated GitHub URL to `ZenHive/ex_unit_json`

**Verification:**
- `mix test` passes (32 tests)
- `mix dialyzer` passes (0 warnings)
- `mix doctor` passes (100% coverage)

---

### Task 3: JSON Encoder - Failure Serialization

**Completed:** 2026-01-09

**What was done:**
- Implemented `encode_failure/1` - extracts failure details from `{:failed, failures}` state
- Implemented `encode_single_failure/1` - handles `{kind, error, stacktrace}` tuples
- Implemented `encode_stacktrace/1` - converts stacktrace to JSON-serializable frames
- Added assertion error handling with `left`, `right`, and `expr` extraction
- Implemented truncation for very long assertion values (10,000 char limit)
- Added `encode_failure_kind/2` - detects assertion errors vs error/exit/throw
- Handles non-serializable values (PIDs, refs) via `inspect/2`
- 21 comprehensive tests for failure serialization

**Key implementation details:**
- Truncation limits defined as module attributes at top of file
- `@value_char_limit 10_000` for inspected values
- `@collection_item_limit 100` for collections
- `@printable_limit 4096` for printable strings
- Stacktrace frames include: module, function, arity, file, line, app
- Arity normalization handles both integer and list-of-args formats
- All private functions have `@doc false` + explanatory comments

**Files modified:**
- `lib/ex_unit_json/json_encoder.ex` - Failure/stacktrace encoding
- `test/ex_unit_json/json_encoder_test.exs` - 21 additional tests

**Verification:**
- `mix test` passes (53 tests)
- `mix dialyzer` passes (0 warnings)
- `mix format --check-formatted` passes
- `mix credo --strict` passes (staged files)

---

### Task 4: Formatter GenServer - Event Collection

**Completed:** 2026-01-09

**What was done:**
- Created `ExUnitJSON.Config` module for centralized option handling
- Implemented `ExUnitJSON.Formatter` GenServer event handlers
- Handles `{:suite_started, opts}` - captures seed from suite options
- Handles `{:test_finished, test}` - accumulates encoded test results
- Handles `{:module_finished, module}` - tracks setup_all failures
- Silently ignores unknown events (no crashes)
- Added `:get_state` call handler for testing
- 39 new tests (12 Config, 27 Formatter)

**Key implementation details:**
- Config module validates and filters option keys
- Options merged from Application env and start_link args
- Tests prepended to list for O(1) accumulation (reversed later in Task 5)
- Module failures only tracked when state is `{:failed, _}`
- Full integration test simulating complete test suite lifecycle

**Files created:**
- `lib/ex_unit_json/config.ex` - Option parsing/validation
- `test/ex_unit_json/config_test.exs` - 12 tests
- `test/ex_unit_json/formatter_test.exs` - 27 tests

**Files modified:**
- `lib/ex_unit_json/formatter.ex` - Full event handler implementation

**Verification:**
- `mix test` passes (91 tests)
- `mix dialyzer` passes (0 warnings)
- Coverage: 90% total (Formatter: 100%, Config: 100%)

---

### Task 5: Formatter GenServer - JSON Output

**Completed:** 2026-01-09

**What was done:**
- Implemented `handle_cast({:suite_finished, times_us}, state)` - outputs complete JSON document
- Added `build_document/2` - assembles root document with version, seed, summary, tests
- Added `build_summary/2` - calculates test counts and overall result
- Added `sort_tests/1` - deterministic ordering by file, line, name
- Added `filter_tests/2` - supports summary_only and failures_only options
- Handles module failures (setup_all) separately in output
- Outputs to stdout by default, or to file when configured
- 11 new tests for suite_finished functionality

**Key implementation details:**
- Uses `:json.encode/1` for JSON serialization (no external dependencies)
- Uses `IO.write/1` (not `IO.puts/1`) to avoid trailing newline in JSON
- Tests reversed from accumulation order before output
- Summary counts include: total, passed, failed, skipped, excluded, invalid
- Overall result is "failed" if any test failed or is invalid
- Tests use file output instead of capture_io (GenServer group leader isolation)

**Output structure:**
```json
{
  "version": 1,
  "seed": 12345,
  "summary": {
    "total": 10, "passed": 8, "failed": 2, "skipped": 0,
    "excluded": 0, "invalid": 0, "duration_us": 123456,
    "result": "failed"
  },
  "tests": [...],
  "module_failures": [...]
}
```

**Files modified:**
- `lib/ex_unit_json/formatter.ex` - suite_finished handler and helpers
- `test/ex_unit_json/formatter_test.exs` - 11 new tests

**Verification:**
- `mix test` passes (102 tests)
- All acceptance criteria verified
- JSON output validated against schema v1

---

### Task 6: Mix Task - Basic Implementation

**Completed:** 2026-01-09

**What was done:**
- Created `Mix.Tasks.Test.Json` module with full documentation
- Parses `--summary-only`, `--failures-only`, `--output` switches
- Passes remaining args through to `mix test` (file paths, line numbers)
- Configures ExUnit to use `ExUnitJSON.Formatter`
- Exit codes preserved from delegated test task
- Added `@shortdoc` and `@moduledoc` with examples
- 15 tests covering option parsing, module attributes, and integration

**Key implementation details:**
- Uses `OptionParser.parse!/2` with strict mode for argument parsing
- Options stored in Application env (ExUnit formatter API limitation)
- Delegates to `Mix.Task.run("test", test_args)` preserving exit codes
- `mix help test.json` shows full documentation

**Files created:**
- `lib/mix/tasks/test_json.ex` - Mix task implementation
- `test/mix/tasks/test_json_test.exs` - 15 tests

**Files modified:**
- `mix.exs` - Added `cli/0` for preferred_envs config

**Verification:**
- `mix test` passes (117 tests)
- `mix help test.json` displays documentation
- `mix test.json` produces valid JSON output
- Exit code 0 on pass, non-zero on failure

---

### Task 7: Filtering Options

**Completed:** 2026-01-09

**What was done:**
- Implemented `filter_tests/2` in formatter with summary_only and failures_only support
- `--summary-only` omits the `tests` array entirely (only summary in output)
- `--failures-only` filters tests array to include only failed tests
- Summary statistics always reflect full suite regardless of filter flags
- When both flags are used, `--summary-only` takes precedence
- Added 3 integration tests for filtering flags
- Added 2 unit tests for filtering logic in formatter

**Key implementation details:**
- Filtering handled in `build_document/2` via `filter_tests/2`
- Returns `nil` for summary_only (omits key), filtered list for failures_only
- Summary counts computed from full test list before filtering
- Options flow from Mix task → Application env → Config → Formatter

**Files modified:**
- `lib/ex_unit_json/formatter.ex` - `filter_tests/2` implementation
- `test/ex_unit_json/formatter_test.exs` - 2 unit tests for filtering
- `test/mix/tasks/test_json_test.exs` - 3 integration tests

**Verification:**
- `mix test` passes (120 tests)
- `mix test.json --summary-only` outputs summary only
- `mix test.json --failures-only` outputs only failed tests
- Both flags combined works correctly
