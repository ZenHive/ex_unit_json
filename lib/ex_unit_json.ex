defmodule ExUnitJSON do
  @moduledoc """
  AI-friendly JSON test output for ExUnit.

  ExUnitJSON provides structured JSON output from `mix test` for use with AI editors
  like Claude Code, Cursor, and other tools that benefit from machine-parseable test results.

  ## Features

  - Drop-in replacement for `mix test` with JSON output
  - **AI-optimized default**: Shows only failures (use `--all` for all tests)
  - **Automatic retry-on-flaky** (default): failed tests are re-run once; failures
    that heal are surfaced as `flaky` instead of blocking (opt out with `--no-retry`)
  - **Code coverage** available with `--cover` flag
  - **Coverage gating** with `--cover-threshold N` (fails if overall coverage drops below N)
  - All test states: passed, failed, skipped, excluded, invalid
  - Detailed failure information with assertion values and stacktraces
  - Filtering options: `--summary-only`, `--all`, `--failures-only`, `--first-failure`, `--filter-out`, `--group-by-error`, `--quiet`, `--compact`
  - File output: `--output results.json`
  - Deterministic test ordering for reproducible output
  - No runtime dependencies (uses Elixir 1.18+ built-in `:json`)

  ## Installation

  Add `ex_unit_json` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false}
        ]
      end

  Configure Mix to run `test.json` in the test environment:

      def cli do
        [preferred_envs: ["test.json": :test]]
      end

  **Note:** The `cli/0` configuration is required because Mix doesn't inherit `preferred_envs`
  from dependencies. Without it, you'll get an error prompting you to add this configuration.

  ## Quick Start

  By default, `mix test.json` outputs only failed tests. This is optimized for AI agents
  where passing tests are noise. When all tests pass, you get an empty `tests` array:

      {"version":1,"seed":12345,"summary":{"total":50,"passed":50,"failed":0,"skipped":0,
       "excluded":0,"invalid":0,"duration_us":54321,"result":"passed"},"tests":[]}

  Use `--all` to include all tests when needed.

  ### Recommended Workflow

      # First run - see failures directly (default behavior)
      mix test.json --quiet

      # Iterate on failures (fast - only runs previously failed tests)
      mix test.json --quiet --failed --first-failure

      # Verify all failures fixed
      mix test.json --quiet --failed --summary-only

      # See all tests (when you need passing tests too)
      mix test.json --quiet --all

  ## Options

      # Default: Output only failed tests (AI-optimized)
      mix test.json --quiet

      # Output ALL tests (passing + failed)
      mix test.json --quiet --all

      # Output only the summary (no individual test results)
      mix test.json --quiet --summary-only

      # Output only the first failed test (quick iteration)
      mix test.json --quiet --first-failure

      # Mark failures matching pattern as filtered (can repeat)
      mix test.json --quiet --filter-out "credentials" --filter-out "rate limit"

      # Group failures by similar error message
      mix test.json --quiet --group-by-error

      # Write JSON to a file instead of stdout
      mix test.json --quiet --output results.json

      # Suppress the "use --failed" warning
      mix test.json --quiet --no-warn

      # Enable code coverage
      mix test.json --quiet --cover

      # Fail if overall coverage drops below threshold (requires --cover)
      mix test.json --quiet --cover --cover-threshold 80

      # Output JSONL with minimal keys (compact format)
      mix test.json --quiet --compact

      # Disable automatic retry of failed tests
      mix test.json --quiet --no-retry

  All standard `mix test` options are also supported (file paths, line numbers, etc.).

  ## Automatic Retry (Flaky Healing)

  By **default**, when a run has failures, `mix test.json` re-runs only the
  previously-failed tests once (in a subprocess, using ExUnit's `--failed`) and
  merges the results:

  - **confirmed** — failed both runs → stays in `tests`, stays red, exits non-zero.
  - **flaky** — failed then passed → moved to a top-level `flaky` array (never
    hidden) and no longer blocks the run.

  When every first-run failure heals, the result goes `"passed"` and the exit code
  is `0`, so an AI agent isn't blocked by a flake — while each flaky test is still
  named in the output. This is the fix for the common loop where an agent treats an
  intermittent async/GenServer/LiveView failure as a real regression.

  Tests invalidated by a flaky `setup_all` failure resolve to their retry state:
  when the module heals on run 2, each of its tests becomes passed (counted in
  `summary.passed`) or failed (a confirmed failure) instead of staying
  `"invalid"`.

  Retry is skipped (run-1 output reported unchanged) for `--no-retry`,
  `config :ex_unit_json, retry: false`, `--failed`, `--summary-only`,
  `--first-failure`, `--compact`, `--group-by-error`, `--filter-out`, a `file:line`
  target, or umbrella projects. A green suite never triggers a second run.

      # Disable globally in config/test.exs
      config :ex_unit_json, retry: false

  ## Code Coverage

  Coverage is disabled by default for faster test runs. Use `--cover` to enable:

      mix test.json --quiet --cover

  The JSON output includes a `coverage` key:

      {
        "coverage": {
          "total_percentage": 92.5,
          "total_lines": 400,
          "covered_lines": 370,
          "modules": [
            {
              "module": "MyApp.Users",
              "file": "lib/my_app/users.ex",
              "percentage": 95.0,
              "covered_lines": 38,
              "uncovered_lines": [45, 67]
            }
          ]
        }
      }

  The `threshold` and `threshold_met` fields are only included when using `--cover-threshold`.

  Configure modules to ignore in `mix.exs`:

      def project do
        [
          # ...
          test_coverage: [
            ignore_modules: [MyApp.GeneratedModule]
          ]
        ]
      end

  ## Iteration Workflow

  When previous test failures exist (`.mix_test_failures`), a helpful tip is shown:

      TIP: 3 previous failure(s) exist. Consider:
        mix test.json --failed
        mix test.json test/unit/ --failed
        mix test.json --only integration --failed

  This warning is automatically skipped when:
  - `--failed` is already used
  - A specific file or directory is targeted
  - `--only` or `--exclude` tag filters are used
  - `--no-warn` flag is passed

  ### Strict Enforcement

  For AI-assisted workflows where forgetting `--failed` wastes time, enable strict enforcement:

      # config/test.exs
      config :ex_unit_json, enforce_failed: true

  This will exit with an error instead of just warning, forcing the use of `--failed` or focused runs.

  ## Using with jq

  For piping to jq, use `MIX_QUIET=1` to suppress compilation messages that would corrupt the JSON stream:

      # Summary - pipes fine (MIX_QUIET=1 prevents compile output from breaking jq)
      MIX_QUIET=1 mix test.json --quiet --summary-only | jq '.summary'

      # Full test details - use file to avoid any piping issues
      mix test.json --quiet --output /tmp/results.json
      jq '.tests[] | select(.state == "failed")' /tmp/results.json

  **Why `MIX_QUIET=1`?** When code changes trigger recompilation, Mix outputs messages like
  "Compiling 1 file (.ex)" to stdout before the JSON. This breaks jq parsing.
  The `--output FILE` approach avoids this entirely.

  ## Output Schema v1

  ### Root Object

      {
        "version": 1,
        "seed": 12345,
        "summary": { ... },
        "tests": [ ... ],
        "flaky": [ ... ],
        "retry": { ... },
        "error_groups": [ ... ],
        "module_failures": [ ... ],
        "hint": "..."
      }

  | Field | Type | Description |
  |-------|------|-------------|
  | `version` | integer | Schema version (currently 1) |
  | `seed` | integer | Random seed used for test ordering |
  | `summary` | object | Aggregate test statistics |
  | `tests` | array | Individual test results (omitted with `--summary-only`) |
  | `flaky` | array | Tests that failed then passed on retry (only present when a retry healed something) |
  | `retry` | object | Retry metadata (only present when a retry ran) |
  | `error_groups` | array | Failures grouped by message (only with `--group-by-error`) |
  | `module_failures` | array | setup_all failures (only present when failures occur) |
  | `coverage` | object | Code coverage data (included with `--cover`) |
  | `hint` | string | Suggestion to use `--failed` (only present when previous failures exist and auto-retry is off) |

  ### Module Failure Object

  Each `module_failures` entry describes a `setup_all` failure:

      {
        "name": "MyApp.FlakyTest",
        "file": "test/my_app/flaky_test.exs",
        "state": "failed",
        "failures": [ ... ]
      }

  | Field | Type | Description |
  |-------|------|-------------|
  | `name` | string | Test module name |
  | `file` | string | Source file path |
  | `state` | string | Always `"failed"` |
  | `failures` | array | Failure details (same shape as test failures) |

  ### Retry Object

  Present only when an automatic retry ran (a first run had failures):

      {
        "ran": true,
        "passes": 1,
        "retried": 3,
        "confirmed": 2,
        "flaky": 1
      }

  | Field | Type | Description |
  |-------|------|-------------|
  | `ran` | boolean | Always `true` when present |
  | `passes` | integer | Number of retry passes (currently always 1) |
  | `retried` | integer | Number of failed tests, invalid tests, and failed modules re-run |
  | `confirmed` | integer | Failures that recurred (still red) |
  | `flaky` | integer | Failures that healed on retry |

  The `flaky` array contains full test objects (run-1 failure detail preserved);
  flaky module failures additionally carry `"scope": "module"`.

  ### Summary Object

      {
        "total": 10,
        "passed": 8,
        "failed": 1,
        "skipped": 1,
        "excluded": 0,
        "invalid": 0,
        "filtered": 0,
        "flaky": 0,
        "duration_us": 123456,
        "result": "failed"
      }

  | Field | Type | Description |
  |-------|------|-------------|
  | `total` | integer | Total number of tests |
  | `passed` | integer | Tests that passed |
  | `failed` | integer | Confirmed failures (after retry, if one ran) |
  | `skipped` | integer | Tests skipped with `@tag :skip` |
  | `excluded` | integer | Tests excluded by tag filters |
  | `invalid` | integer | Tests with invalid state |
  | `filtered` | integer | Failed tests matching `--filter-out` patterns (only present when non-zero) |
  | `flaky` | integer | Failures that healed on retry (only present when a retry ran) |
  | `duration_us` | integer | Total duration in microseconds |
  | `result` | string | `"passed"` or `"failed"` (`"passed"` when all failures healed) |

  ### Test Object

      {
        "name": "test addition works",
        "module": "MyApp.CalculatorTest",
        "file": "test/calculator_test.exs",
        "line": 10,
        "state": "passed",
        "duration_us": 1234,
        "tags": {},
        "failures": []
      }

  | Field | Type | Description |
  |-------|------|-------------|
  | `name` | string | Test name |
  | `module` | string | Test module name |
  | `file` | string | Source file path |
  | `line` | integer | Line number |
  | `state` | string | `"passed"`, `"failed"`, `"skipped"`, `"excluded"`, or `"invalid"` (setup_all failed) |
  | `duration_us` | integer | Test duration in microseconds |
  | `tags` | object | Test tags (filtered, no internal ExUnit keys) |
  | `failures` | array | Failure details (empty for passing tests) |

  ### Failure Object

      {
        "kind": "assertion",
        "message": "Assertion with == failed",
        "assertion": {
          "expr": "1 == 2",
          "left": "1",
          "right": "2"
        },
        "stacktrace": [
          {
            "file": "test/calculator_test.exs",
            "line": 15,
            "module": "MyApp.CalculatorTest",
            "function": "test addition works",
            "arity": 1
          }
        ]
      }

  | Field | Type | Description |
  |-------|------|-------------|
  | `kind` | string | `"assertion"`, `"error"`, `"exit"`, or `"throw"` |
  | `message` | string | Error message |
  | `assertion` | object | Assertion details (only for assertion failures) |
  | `stacktrace` | array | Stack frames |

  ### Stacktrace Frame

  | Field | Type | Description |
  |-------|------|-------------|
  | `file` | string | Source file |
  | `line` | integer | Line number |
  | `module` | string | Module name (optional) |
  | `function` | string | Function name (optional) |
  | `arity` | integer | Function arity (optional) |
  | `app` | string | Application name (optional) |

  ### Error Group Object

  When using `--group-by-error`, failures are grouped by their error message:

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

  | Field | Type | Description |
  |-------|------|-------------|
  | `pattern` | string | First line of the error message (truncated at 200 chars) |
  | `count` | integer | Number of failures with this error |
  | `example` | object | One example test with this failure |

  Groups are sorted by count (descending), so the most common errors appear first.

  ## Examples

  ### Passing Test Suite

      {
        "version": 1,
        "seed": 12345,
        "summary": {
          "total": 3,
          "passed": 3,
          "failed": 0,
          "skipped": 0,
          "excluded": 0,
          "invalid": 0,
          "duration_us": 5432,
          "result": "passed"
        },
        "tests": [
          {
            "name": "test addition",
            "module": "MyApp.MathTest",
            "file": "test/math_test.exs",
            "line": 5,
            "state": "passed",
            "duration_us": 1234,
            "tags": {},
            "failures": []
          }
        ]
      }

  ### Failed Test Suite

      {
        "version": 1,
        "seed": 67890,
        "summary": {
          "total": 2,
          "passed": 1,
          "failed": 1,
          "skipped": 0,
          "excluded": 0,
          "invalid": 0,
          "duration_us": 3456,
          "result": "failed"
        },
        "tests": [
          {
            "name": "test subtraction",
            "module": "MyApp.MathTest",
            "file": "test/math_test.exs",
            "line": 10,
            "state": "failed",
            "duration_us": 2000,
            "tags": {},
            "failures": [
              {
                "kind": "assertion",
                "message": "Assertion with == failed\\ncode:  5 - 3 == 3\\nleft:  2\\nright: 3",
                "assertion": {
                  "expr": "5 - 3 == 3",
                  "left": "2",
                  "right": "3"
                },
                "stacktrace": [
                  {
                    "file": "test/math_test.exs",
                    "line": 12,
                    "module": "MyApp.MathTest",
                    "function": "test subtraction",
                    "arity": 1
                  }
                ]
              }
            ]
          }
        ]
      }

  ## Programmatic Usage

  You can also use the formatter directly in your test configuration:

      # In test/test_helper.exs
      ExUnit.configure(formatters: [ExUnitJSON.Formatter])
      ExUnit.start()

  Or with options:

      Application.put_env(:ex_unit_json, :opts,
        summary_only: true,
        output: "test_results.json"
      )
      ExUnit.configure(formatters: [ExUnitJSON.Formatter])
      ExUnit.start()

  ## Modules

    * `ExUnitJSON.Formatter` - The ExUnit formatter GenServer
    * `ExUnitJSON.JSONEncoder` - Converts ExUnit structs to JSON maps
    * `ExUnitJSON.Config` - Configuration handling
    * `ExUnitJSON.Filters` - Test filtering logic
    * `ExUnitJSON.Retry` - Merges a run with its retry to classify flaky vs confirmed
    * `ExUnitJSON.ErrorGroups` - Groups failures by error message
    * `ExUnitJSON.Coverage` - Code coverage collection
    * `ExUnitJSON.CompactOutput` - Compact JSONL output format
    * `Mix.Tasks.Test.Json` - Mix task entry point (`mix test.json`)

  ## Requirements

  - Elixir 1.18+ (uses built-in `:json` module)

  ## License

  MIT License - see LICENSE file for details.
  """
end
