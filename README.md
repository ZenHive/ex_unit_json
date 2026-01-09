# ExUnitJSON

AI-friendly JSON test output for ExUnit.

ExUnitJSON provides structured JSON output from `mix test` for use with AI editors like Claude Code, Cursor, and other tools that benefit from machine-parseable test results.

## Features

- Drop-in replacement for `mix test` with JSON output
- All test states: passed, failed, skipped, excluded
- Detailed failure information with assertion values and stacktraces
- Filtering options: `--summary-only`, `--failures-only`, `--first-failure`, `--filter-out`, `--group-by-error`
- File output: `--output results.json`
- Deterministic test ordering for reproducible output
- No runtime dependencies (uses Elixir 1.18+ built-in `:json`)

## Installation

Add `ex_unit_json` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_unit_json, "~> 0.1.0", only: [:dev, :test], runtime: false}
  ]
end
```

Configure Mix to run `test.json` in the test environment:

```elixir
def cli do
  [preferred_envs: ["test.json": :test]]
end
```

**Note:** The `cli/0` configuration is required because Mix doesn't inherit `preferred_envs` from dependencies. Without it, you'll get an error prompting you to add this configuration.

## Usage

### Basic Usage

```bash
# Run all tests with JSON output
mix test.json

# Run specific file
mix test.json test/my_test.exs

# Run specific test by line number
mix test.json test/my_test.exs:42
```

### Options

```bash
# Output only the summary (no individual test results)
mix test.json --summary-only

# Output only failed tests
mix test.json --failures-only

# Output only the first failed test (quick iteration)
mix test.json --first-failure

# Mark failures matching pattern as filtered (can repeat)
mix test.json --filter-out "credentials" --filter-out "rate limit"

# Group failures by similar error message
mix test.json --group-by-error

# Write JSON to a file instead of stdout
mix test.json --output results.json

# Combine options
mix test.json --failures-only --output failures.json
```

All standard `mix test` options are also supported (file paths, line numbers, etc.).

## Output Schema v1

### Root Object

```json
{
  "version": 1,
  "seed": 12345,
  "summary": { ... },
  "tests": [ ... ],
  "error_groups": [ ... ],
  "module_failures": [ ... ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | integer | Schema version (currently 1) |
| `seed` | integer | Random seed used for test ordering |
| `summary` | object | Aggregate test statistics |
| `tests` | array | Individual test results (omitted with `--summary-only`) |
| `error_groups` | array | Failures grouped by message (only with `--group-by-error`) |
| `module_failures` | array | setup_all failures (only present when failures occur) |

### Summary Object

```json
{
  "total": 10,
  "passed": 8,
  "failed": 1,
  "skipped": 1,
  "excluded": 0,
  "invalid": 0,
  "duration_us": 123456,
  "result": "failed"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `total` | integer | Total number of tests |
| `passed` | integer | Tests that passed |
| `failed` | integer | Tests that failed |
| `skipped` | integer | Tests skipped with `@tag :skip` |
| `excluded` | integer | Tests excluded by tag filters |
| `invalid` | integer | Tests with invalid state |
| `duration_us` | integer | Total duration in microseconds |
| `result` | string | `"passed"` or `"failed"` |

### Test Object

```json
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
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Test name |
| `module` | string | Test module name |
| `file` | string | Source file path |
| `line` | integer | Line number |
| `state` | string | `"passed"`, `"failed"`, `"skipped"`, or `"excluded"` |
| `duration_us` | integer | Test duration in microseconds |
| `tags` | object | Test tags (filtered, no internal ExUnit keys) |
| `failures` | array | Failure details (empty for passing tests) |

### Failure Object

```json
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
```

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

```json
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
```

| Field | Type | Description |
|-------|------|-------------|
| `pattern` | string | First line of the error message (truncated at 200 chars) |
| `count` | integer | Number of failures with this error |
| `example` | object | One example test with this failure |

Groups are sorted by count (descending), so the most common errors appear first.

## Example Output

### Passing Test Suite

```json
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
```

### Failed Test Suite

```json
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
          "message": "Assertion with == failed\ncode:  5 - 3 == 3\nleft:  2\nright: 3",
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
```

## Programmatic Usage

You can also use the formatter directly in your test configuration:

```elixir
# In test/test_helper.exs
ExUnit.configure(formatters: [ExUnitJSON.Formatter])
ExUnit.start()
```

Or with options:

```elixir
Application.put_env(:ex_unit_json, :opts,
  summary_only: true,
  output: "test_results.json"
)
ExUnit.configure(formatters: [ExUnitJSON.Formatter])
ExUnit.start()
```

## Requirements

- Elixir 1.18+ (uses built-in `:json` module)

## License

MIT License - see LICENSE file for details.
