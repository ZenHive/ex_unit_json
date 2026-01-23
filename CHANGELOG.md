# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## v0.2.11 (2026-01-23)

### Improvements

**`--quiet` now suppresses TIP warnings for completely clean piping**

When using `--quiet`, the "TIP: N previous failure(s) exist" message is now suppressed. This ensures `mix test.json --quiet | jq` works without needing `2>/dev/null`.

**Before (v0.2.10):**
```bash
MIX_QUIET=1 mix test.json --quiet --summary-only 2>&1 | jq
# jq: parse error (TIP message on stderr combined with stdout)
```

**After (v0.2.11):**
```bash
MIX_QUIET=1 mix test.json --quiet --summary-only 2>&1 | jq
# Works! TIP is suppressed with --quiet
```

Note: The ERROR message for `enforce_failed: true` is still shown even with `--quiet` since it blocks execution entirely.

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Suppress TIP when `--quiet` is used

---

## v0.2.10 (2026-01-23)

### Bug Fixes

**Fix: `--quiet` now properly suppresses Logger output from test_helper.exs**

Fixed an issue where Logger.info/debug/warning messages from test_helper.exs would still appear in stdout even with `--quiet`, breaking jq piping.

**Root cause:** The `:logger.remove_handler(:default)` call in the Mix task was being undone when the test environment loaded and restarted the :logger application.

**Fix:** In addition to removing the handler, also set `Application.put_env(:logger, :level, :error)` before running tests. When the :logger app restarts during test setup, it initializes with `:error` level, suppressing info/debug/warning messages.

**Behavior:**
- `--quiet` now suppresses ALL Logger output (info, debug, warning) from test_helper.exs and test files
- Logger.error messages still appear (appropriate for actual errors)
- Without `--quiet`, Logger output works normally

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Add `Application.put_env(:logger, :level, :error)` when `--quiet` is used

**Added test app:**
- `test_apps/logger_app/` - Test fixture with Logger.info in test_helper.exs for regression testing

**New integration tests:**
- `--quiet suppresses Logger output from test_helper.exs`
- `Logger output appears without --quiet`
- `--quiet produces clean JSON for jq piping`

---

## v0.2.9 (2026-01-23)

### Bug Fixes

**Fix: Buffer JSON output for clean piping without `--output`**

Fixed an issue where stdout pollution from `test_helper.exs` or other sources would corrupt the JSON stream when piping to jq, even with `--quiet` and `MIX_QUIET=1`.

**Problem:**
```bash
MIX_QUIET=1 mix test.json --quiet | jq '.summary'
# jq: parse error: Invalid numeric literal at line 2, column 1
```

This happened because some projects print to stdout in `test_helper.exs` (e.g., "✓ 3 testnet credentials registered") which appears before the JSON formatter runs.

**Solution:** When `--quiet` is used WITHOUT an explicit `--output` path, automatically buffer JSON to a temp file and output it at the very end (after all other stdout pollution).

**Behavior:**
- `mix test.json --quiet` → Buffers to temp file, outputs clean JSON at end
- `mix test.json --quiet --output FILE` → Writes to FILE (unchanged behavior)
- `mix test.json` (no --quiet) → Direct stdout (unchanged behavior)

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Added `maybe_use_temp_output/1` and `output_buffered_json/1`

---

## v0.2.8 (2026-01-23)

### Bug Fixes

**Fix: Logger output still corrupting JSON stream with `--quiet`**

Fixed an issue where Logger messages would still go to stdout even with `--quiet`, corrupting the JSON stream when piping to jq.

**Root cause:** The attempt to redirect the default logger handler to stderr using `:logger.set_handler_config(:default, :config, %{type: :standard_error})` doesn't work because the handler's output type cannot be changed after initialization.

**Fix:** Remove the default handler entirely when `--quiet` is used:
```elixir
:logger.remove_handler(:default)
```

This completely suppresses Logger output, which is appropriate for `--quiet` mode where clean JSON output is the priority.

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Use `remove_handler` instead of `set_handler_config`

---

## v0.2.7 (2026-01-23)

### Documentation

**Docs: `MIX_QUIET=1` required for jq piping when compilation occurs**

Updated documentation to show that `MIX_QUIET=1` must be set when piping to jq if code changes trigger recompilation.

**Issue:**
```bash
$ mix test.json --quiet --summary-only | jq '.summary'
jq: parse error: Invalid numeric literal at line 1, column 10
```

**Root cause:** Mix outputs compilation messages ("Compiling 1 file (.ex)", "Generated app_name app") to stdout before the JSON formatter runs. This happens because compilation occurs before the task code that sets `Mix.shell(Mix.Shell.Quiet)` can execute.

**Fix:** Use `MIX_QUIET=1` environment variable which suppresses Mix output at a lower level:
```bash
MIX_QUIET=1 mix test.json --quiet --summary-only | jq '.summary'
```

Alternatively, use `--output FILE` which avoids piping issues entirely:
```bash
mix test.json --quiet --output /tmp/results.json
jq '.summary' /tmp/results.json
```

**Files modified:**
- `README.md` - Updated jq section with `MIX_QUIET=1`
- `AGENT.md` - Updated jq section with `MIX_QUIET=1`
- `lib/mix/tasks/test_json.ex` - Added comments explaining the limitation

---

## v0.2.6 (2026-01-21)

### Bug Fixes

**Fix: `capture_log` returns empty string when using `--quiet`**

Fixed an issue where `ExUnit.CaptureLog.capture_log/2` returned empty strings when running tests with `mix test.json --quiet`.

**Error:**
```elixir
@tag capture_log: false
test "capture_log works" do
  log = capture_log(fn -> Logger.info("test message") end)
  assert log =~ "test message"  # FAILS: log is ""
end
```

**Root cause:** The `--quiet` flag was calling `Logger.configure(level: :error)`, which sets the **global** Logger level. This filters messages *before* they reach any handler, including `capture_log`'s capture handler.

**Fix:** Changed to `:logger.set_handler_config(:default, :level, :error)` instead. This sets the **console handler's** level while leaving the global level unchanged:
- Console output is still suppressed (handler ignores messages below `:error`)
- `capture_log` works because messages still reach its capture handler

**Files modified:**
- `lib/ex_unit_json/formatter.ex` - Use handler-level suppression
- `lib/mix/tasks/test_json.ex` - Use handler-level suppression

---

## v0.2.5 (2026-01-20)

### Bug Fixes

**Fix: `mix test.json | jq` now works correctly**

Fixed an issue where piping `mix test.json` output to jq would fail with parse errors when previous test failures existed.

**Error:**
```
$ mix test.json --quiet | jq '.summary'
jq: parse error: Invalid numeric literal at line 1, column 10
```

**Root cause:** The TIP message ("TIP: 3 previous failure(s) exist...") was written to stdout via `Mix.shell().info()`, contaminating the JSON stream.

**Fix:** Changed both the TIP warning and ERROR message (for `enforce_failed` mode) to use `IO.puts(:stderr, ...)` instead of `Mix.shell()` functions. This ensures stdout contains only valid JSON.

**After the fix:**
```bash
# Works - TIP goes to stderr, JSON to stdout
mix test.json --quiet | jq '.summary'

# TIP still visible in terminal (stderr)
mix test.json --quiet
```

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Route TIP and ERROR messages to stderr

---

## v0.2.4 (2026-01-18)

### Bug Fixes

**Fix: Protocol.UndefinedError for non-atom failure kinds**

Fixed a crash when a test fails due to a linked process exit (e.g., WebSocket connection failure). ExUnit reports these failures with a tuple kind `{:EXIT, pid}` instead of an atom like `:error`, `:exit`, or `:throw`.

**Error:**
```
** (Protocol.UndefinedError) protocol String.Chars not implemented for Tuple.
Got value: {:EXIT, #PID<0.797.0>}
```

**Root cause:** `encode_failure_kind/2` used `to_string(kind)` which fails for tuples since `String.Chars` is not implemented for them.

**Fix:** Changed `to_string(kind)` to `inspect(kind)` which safely handles any Elixir term.

**Files modified:**
- `lib/ex_unit_json/json_encoder.ex` - Use `inspect/1` for unknown failure kinds
- `test/ex_unit_json/json_encoder_test.exs` - Added test for tuple failure kinds

---

## v0.2.3 (2026-01-11)

### Bug Fixes

**Fix: JSON formatter not used in Phoenix projects**

Fixed a race condition where `mix test.json` would output CLI format (dots) instead of JSON in Phoenix projects due to timing issues with `ExUnit.configure`.

**Root cause:** Calling `ExUnit.configure(formatters: [...])` before delegating to `mix test` could be overwritten by stale compilation state or timing issues with `test_helper.exs` loading.

**Solution:** Use `--formatter` flag instead of `ExUnit.configure`:
```elixir
# Before (race condition prone)
ExUnit.configure(formatters: [ExUnitJSON.Formatter])
Mix.Task.run("test", test_args)

# After (robust)
Mix.Task.run("test", ["--formatter", "ExUnitJSON.Formatter" | test_args])
```

**Fix: Noisy debug logs about failures file**

Removed spurious `[debug] Could not parse failures file` messages that appeared on every run. The failures file format changed in Elixir 1.17+ from a list to `{version, map}` tuple.

**Fix: Correctly parse new failures file format**

Updated `count_previous_failures/1` to handle both:
- New format (Elixir 1.17+): `{version, %{test_id => path}}`
- Old format: `[test_id, ...]`

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Use `--formatter` flag, fix failures file parsing

**Added:**
- `test_apps/phoenix_app/` - Phoenix 1.8 test fixture for regression testing
- `test/mix/tasks/test_json_test.exs` - Phoenix integration tests

---

## v0.2.2 (2026-01-11)

### Improvements

**More defensive error handling in `count_previous_failures/1`:**
- Changed `rescue ArgumentError` to `rescue _` to catch all potential parsing errors
- Ensures graceful fallback to 0 when failures file is corrupted or malformed

**Improved test helper `decode_json/1`:**
- Replaced fragile regex with simpler line-based JSON extraction
- More robust parsing of test output with compilation messages

**Code quality:**
- Fixed Credo line length issue in `@valid_options` (config.ex)
- Added test case for malformed binary failures file

**Files modified:**
- `lib/mix/tasks/test_json.ex` - More defensive rescue clause
- `lib/ex_unit_json/config.ex` - Reformatted long line
- `test/mix/tasks/test_json_test.exs` - Improved decode_json, new test case

---

## v0.2.1 (2026-01-10)

### Bug Fix: `enforce_failed` Now Works Correctly

Fixed a bug where `enforce_failed: true` configuration had no effect because the library was looking for the failures file in the wrong location.

**The problem:**
- ExUnit writes failures to `_build/test/lib/<app>/.mix/.mix_test_failures` (Erlang term format)
- ex_unit_json was checking `.mix_test_failures` in the project root (and treating it as text)

**What's fixed:**
- `failures_file/0` now returns the correct path matching ExUnit's location
- `count_previous_failures/1` now correctly decodes Erlang term format using `:erlang.binary_to_term/1`
- Both warning and enforcement modes now work as documented

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Fixed path computation and file format parsing

---

## v0.2.0 (2026-01-10)

### Warn-by-Default for `--failed` Usage

When previous test failures exist (`.mix_test_failures`) and you're running the full test suite, a helpful tip is now shown:

```
TIP: 3 previous failure(s) exist. Consider:
  mix test.json --failed
  mix test.json test/unit/ --failed
  mix test.json --only integration --failed
(Use --no-warn to suppress this message)
```

**Why this matters:** AI assistants (Claude Code, Cursor, etc.) often forget to use `--failed` when iterating on test fixes, wasting time re-running the entire suite. This warning happens automatically - no flag needed.

**Behavior:**
- Warning shown by default when `.mix_test_failures` exists and full suite is run
- Warning skipped when:
  - `--failed` is already used
  - A specific file or directory is targeted (`test/my_test.exs`, `test/unit/`)
  - Tag filters are used (`--only`, `--exclude`)
  - `--no-warn` flag is passed

**Strict enforcement (optional):**
```elixir
# config/test.exs
config :ex_unit_json, enforce_failed: true
```

With strict enforcement, running the full suite with failures will exit with an error instead of just warning.

**New flag:**
- `--no-warn` - Suppress the "use --failed" warning

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Added `check_failed_usage/2`, `focused_run?/1`, `--no-warn` flag
- `test/mix/tasks/test_json_test.exs` - Added 17 new tests
- `README.md` - Added "Iteration Workflow" and "Strict Enforcement" sections
- `AGENT.md` - Updated workflow documentation

---

## v0.1.3 (2026-01-09)

### Published to Hex.pm 🎉

First public release! Available at [hex.pm/packages/ex_unit_json](https://hex.pm/packages/ex_unit_json)

**Features included in v0.1.3:**
- JSON output for ExUnit test results
- `--summary-only`, `--failures-only`, `--compact` output modes
- `--filter-out`, `--group-by-error`, `--first-failure` for AI workflows
- `--quiet` flag to suppress Logger noise
- `--output FILE` for file output
- Smart `--failed` hint for iteration workflows
- Full passthrough of ExUnit flags (`--only`, `--exclude`, `--seed`, etc.)

### Documentation

#### Improved jq usage guidance

**Issue:** Piping `mix test.json` directly to jq can fail with parse errors when compilation warnings or other non-JSON output appears before the JSON.

**Solution:** Updated documentation to clarify:
- `--summary-only` produces clean, minimal output that pipes safely to jq
- For full test details, use `--output FILE` then jq the file

**Files modified:**
- `AGENT.md` - Updated "Using jq" section with safety guidance, simplified Troubleshooting
- `README.md` - Added "Using with jq" section

---

## v0.1.2 (2026-01-09)

### Bug Fixes

#### Fix: `--quiet` flag not suppressing Logger output

**Fixed:** 2026-01-09

**Issue:** The `--quiet` flag wasn't working - Logger output still appeared even when the flag was used.

**Root cause:** Two issues:
1. `:quiet` was missing from `@valid_options` in `Config.ex`, so it was being filtered out by `validate_opts/1` and never reached the formatter
2. `Logger.configure(level: :error)` was called before `Mix.Task.run("test")`, but when the test task runs it loads application config from `config/test.exs` which overwrites the Logger level

**Fix:**
1. Added `:quiet` to `@valid_options` in `Config.ex`
2. Added `Logger.configure(level: :error)` call in formatter's `init/1` (runs after app config loads)

**Files modified:**
- `lib/ex_unit_json/config.ex` - Added `:quiet` to `@valid_options`
- `lib/ex_unit_json/formatter.ex` - Added Logger config in `init/1`
- `test/ex_unit_json/config_test.exs` - Added tests for `:quiet` option
- `test/mix/tasks/test_json_test.exs` - Added integration test for `--quiet`

---

## v0.1.1 (2026-01-09)

### Smart `--failed` Hint

**Added:** 2026-01-09

When `.mix_test_failures` exists and you're running without `--failed`, prints a helpful hint to stderr:

```
Hint: 3 test(s) failed previously. Use --failed to re-run only those.
```

Also warns if the failures file is stale (>2 hours old):

```
Note: .mix_test_failures is 3 hours old. Consider a full run if you changed shared setup.
```

**Behavior:**
- Hint only shown when:
  - `.mix_test_failures` file exists
  - `--failed` flag is NOT already being used
  - No specific test file is targeted (e.g., `test/my_test.exs`)
- Stale warning shown when file is older than 2 hours
- All output goes to stderr (doesn't pollute JSON stdout)
- Human-readable age formatting: "less than a minute", "5 minutes", "2 hours"

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Added `maybe_hint_failed/1`, `maybe_hint_stale/1`, `test_path?/1`, `count_previous_failures/1`, `format_age/1`
- `test/mix/tasks/test_json_test.exs` - Added 10 unit tests for hint helper functions
- `AGENT.md` - Added "Start Here" section with recommended workflow

---

## Phase 2 Features

### `--group-by-error` Flag

**Added:** 2026-01-09

Group failures by similar error message, showing root causes at a glance.

```bash
mix test.json --group-by-error
```

**Use case:** When 100 tests fail with the same root cause (e.g., connection refused, missing credentials), see it summarized once instead of scrolling through 100 identical errors.

**Output:**
```json
{
  "error_groups": [
    {
      "pattern": "Connection refused",
      "count": 47,
      "example": {
        "name": "test API call",
        "module": "MyApp.APITest",
        "file": "test/api_test.exs",
        "line": 25
      }
    }
  ]
}
```

**Behavior:**
- Groups failed tests by the first line of their error message
- Sorts groups by count (descending) - most common errors first
- Includes one example test for each group
- Truncates long patterns at 200 characters
- Works alongside other options (`--failures-only`, etc.)
- `error_groups` key only added when option is enabled and failures exist

**Files modified:**
- `lib/ex_unit_json/config.ex` - Added `:group_by_error` option
- `lib/mix/tasks/test_json.ex` - Added `--group-by-error` flag parsing
- `lib/ex_unit_json/formatter.ex` - Added `build_error_groups/1`, `extract_error_pattern/1`, `truncate_pattern/1`
- Tests added to config_test.exs, formatter_test.exs, test_json_test.exs

---

### `--filter-out` Flag

**Added:** 2026-01-09

Mark failures matching a pattern as `"filtered": true` in JSON output. Can be used multiple times to filter multiple patterns.

```bash
mix test.json --filter-out "credentials" --filter-out "rate limit"
```

**Use case:** Filter expected failures (missing API credentials, rate limits, timeouts) to focus on real bugs. Tests still appear in output but are marked as filtered so AI tools can distinguish them.

**Behavior:**
- Runs all tests (full suite)
- Summary counts remain unchanged (filtered failures still count as failures)
- Failed tests whose error message contains any pattern get `"filtered": true` added
- Non-matching failures remain unmarked
- Passing/skipped tests are never marked
- Works with both regular JSON and `--compact` JSONL output (uses `"x": true` in compact mode)

**Files modified:**
- `lib/ex_unit_json/config.ex` - Added `:filter_out` option
- `lib/mix/tasks/test_json.ex` - Added `--filter-out` flag parsing with list accumulation
- `lib/ex_unit_json/formatter.ex` - Added `apply_filter_out/2` and `failure_matches_pattern?/2`
- `test/ex_unit_json/config_test.exs` - Added tests for filter_out_patterns/0
- `test/mix/tasks/test_json_test.exs` - Added parsing and integration tests

---

### `--quiet` Flag

**Added:** 2026-01-09

Suppress Logger output for cleaner JSON. Sets Logger level to `:error` before running tests.

```bash
mix test.json --quiet
```

**Use case:** When applications under test have Logger debug/info output, this prevents log noise from appearing before the JSON output.

**Behavior:**
- Sets `Logger.configure(level: :error)` before running tests
- Only error-level logs will appear
- JSON output remains clean and parseable

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Added `--quiet` flag parsing and Logger configuration

---

### `filtered` Summary Count

**Added:** 2026-01-09

When using `--filter-out`, the summary now includes a `filtered` count showing how many failures matched the filter patterns.

**Output:**
```json
{
  "summary": {
    "total": 100,
    "failed": 50,
    "filtered": 40,
    ...
  }
}
```

**Behavior:**
- `filtered` only appears when `--filter-out` is used AND patterns match failures
- Shows how many of the `failed` count were filtered out
- Absent when no patterns provided or no matches (avoids noise)

**Files modified:**
- `lib/ex_unit_json/filters.ex` - Added `count_filtered_failures/2`
- `lib/ex_unit_json/formatter.ex` - Updated `build_summary/3` to include filtered count

---

### Fix: `--filter-out` Not Filtering Error Groups

**Fixed:** 2026-01-09

**Issue:** When using `--filter-out` with `--group-by-error`, filtered failures still appeared in `error_groups`. Expected behavior: filtered failures should be excluded from error groups entirely.

**Fix:** Added `Filters.reject_filtered_failures/2` function and updated `maybe_add_error_groups` to exclude tests matching filter_out patterns from groups.

**Files modified:**
- `lib/ex_unit_json/filters.ex` - Added `reject_filtered_failures/2`
- `lib/ex_unit_json/formatter.ex` - Updated `maybe_add_error_groups` to apply filter_out

---

### `--first-failure` Flag

**Added:** 2026-01-09

Quick iteration mode - outputs only the first failed test in detail while still running the full suite.

```bash
mix test.json --first-failure
```

**Use case:** When fixing failing tests one at a time, reduces output noise by showing only the first failure. Summary still reflects the full suite status.

**Behavior:**
- Runs all tests (full suite)
- Summary shows counts for all tests
- Tests array contains only the first failed test (by file, line, name order)
- Returns empty tests array if no failures

**Files modified:**
- `lib/ex_unit_json/config.ex` - Added `:first_failure` option
- `lib/mix/tasks/test_json.ex` - Added `--first-failure` flag parsing
- `lib/ex_unit_json/formatter.ex` - Updated filter logic
- `test/ex_unit_json/config_test.exs` - Added tests for first_failure?/0
- `test/mix/tasks/test_json_test.exs` - Added parsing and integration tests

---

## Bug Fixes

### Fix: Graceful error handling for file output

**Fixed:** 2026-01-09

**Issue:** When `--output` pointed to an invalid path (e.g., non-existent directory), the formatter would crash with `File.write!/2` raising an exception.

**Fix:** Replaced `File.write!/2` with `File.write/2` and graceful error handling:
- Prints clear error message to stderr with reason
- Tests continue to pass (exit code reflects test results, not file write)
- GenServer doesn't crash on file write failure

**Also improved:**
- Added integer guards to `extract_duration/1` for defensive programming
- Clarified `terminate/2` callback documentation (OTP compliance)

**Files modified:**
- `lib/ex_unit_json/formatter.ex` - Added `write_output/2` with error handling
- `test/mix/tasks/test_json_test.exs` - Updated test for graceful behavior

---

### Fix: Mix task not found with `only: :test` dependency config

**Fixed:** 2026-01-09

**Issue:** When configured with `only: :test`, the `mix test.json` task was not found:
```
** (Mix) The task "test.json" could not be found. Did you mean "test"?
```

**Cause:** Mix runs in the `:dev` environment by default. Mix tasks must be available in `:dev` to be discovered, but the formatter only needs to run in `:test`.

**Fix:** Updated installation instructions to use both environments:
```elixir
{:ex_unit_json, "~> 0.1.0", only: [:dev, :test], runtime: false}
```

**Files modified:**
- `README.md` - Updated installation instructions with explanation

---

### Fix: ExUnit flags (--only, --exclude, --seed, etc.) not passed through

**Fixed:** 2026-01-09

**Issue:** ExUnit filtering flags like `--only integration` weren't working:
```bash
mix test.json --only integration
# Expected: Only tests tagged @tag :integration run
# Actual: All tests ran
```

**Cause:** `OptionParser.parse/2` in non-strict mode treats unknown switches as boolean flags. So `["--only", "integration"]` became `{"--only", nil}` and `"integration"` was separated into remaining args, breaking the flag-value pairing.

**Fix:** Replaced OptionParser with explicit pattern matching that only consumes our three switches (`--summary-only`, `--failures-only`, `--output`) and passes everything else through unchanged:

```elixir
# Before (broken): OptionParser mangled unknown switches
{opts, remaining, passthrough} = OptionParser.parse(args, switches: @switches)

# After (fixed): Pattern matching preserves all unknown args
defp extract_json_opts(["--summary-only" | rest], opts, remaining), do: ...
defp extract_json_opts([arg | rest], opts, remaining), do: ...  # passthrough
```

**Files modified:**
- `lib/mix/tasks/test_json.ex` - New `extract_json_opts/1` function
- `test/mix/tasks/test_json_test.exs` - Added tests for --only and --exclude

**Also added:**
- `ensure_test_env!/0` - Clear error message when run in wrong environment

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

---

### Task 8: Output File Option & Polish

**Completed:** 2026-01-09

**What was done:**
- Verified `--output FILE` option already implemented in Mix task, Config, and Formatter
- Changed option parsing from `strict` to `switches` mode to allow passthrough of mix test options
- Added invalid file path edge case test
- Added golden test suite with 11 tests for JSON schema v1 conformance
- Complete README rewrite with usage examples and full schema documentation
- All tests passing (132 tests)

**Key implementation details:**
- `File.write!/2` raises on invalid paths (no directory, permission denied)
- Unknown options now pass through to mix test (not rejected)
- Golden tests verify schema structure for all test states
- README documents complete JSON schema v1 specification

**Files modified:**
- `lib/mix/tasks/test_json.ex` - Changed to switches mode for option passthrough
- `test/mix/tasks/test_json_test.exs` - Added invalid path test, updated option parsing tests
- `test/golden_test.exs` - New golden test suite (11 tests)
- `README.md` - Complete rewrite with documentation

**Verification:**
- `mix test` passes (132 tests)
- `mix hex.build` succeeds
- README complete with schema documentation and examples
