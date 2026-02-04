# ExUnitJSON

AI-friendly JSON test output for ExUnit.

ExUnitJSON provides structured JSON output from `mix test` for use with AI editors like Claude Code, Cursor, and other tools that benefit from machine-parseable test results.

## Features

- Drop-in replacement for `mix test` with JSON output
- **AI-optimized default**: Shows only failures (use `--all` for all tests)
- **Code coverage** available with `--cover` flag
- **Coverage gating** with `--cover-threshold N` (fails if overall coverage drops below N)
- All test states: passed, failed, skipped, excluded
- Detailed failure information with assertion values and stacktraces
- Filtering options: `--summary-only`, `--all`, `--failures-only`, `--first-failure`, `--filter-out`, `--group-by-error`, `--quiet`
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

### Default Behavior (v0.3.0+)

By default, `mix test.json` outputs only failed tests. This is optimized for AI agents
where passing tests are noise. When all tests pass, you get:

```json
{"version":1,"summary":{"total":50,"passed":50,"failed":0},"tests":[]}
```

Use `--all` to include all tests when needed.

### Recommended Workflow

```bash
# First run - see failures directly (default behavior)
mix test.json --quiet

# Iterate on failures (fast - only runs previously failed tests)
mix test.json --quiet --failed --first-failure

# Verify all failures fixed
mix test.json --quiet --failed --summary-only

# See all tests (when you need passing tests too)
mix test.json --quiet --all
```

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

# Suppress Logger output for cleaner JSON
mix test.json --quiet

# Write JSON to a file instead of stdout
mix test.json --quiet --output results.json

# Suppress the "use --failed" warning
mix test.json --quiet --no-warn

# Enable code coverage
mix test.json --quiet --cover

# Fail if overall coverage drops below threshold (requires --cover)
mix test.json --quiet --cover --cover-threshold 80

# Combine options
mix test.json --quiet --all --output all_results.json
```

All standard `mix test` options are also supported (file paths, line numbers, etc.).

### Code Coverage

Coverage is disabled by default for faster test runs. Use `--cover` to enable:

```bash
mix test.json --quiet --cover
```

The JSON output includes a `coverage` key:

```json
{
  "coverage": {
    "total_percentage": 92.5,
    "total_lines": 400,
    "covered_lines": 370,
    "threshold": 80,
    "threshold_met": true,
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
```

The `threshold` and `threshold_met` fields are only included when using `--cover-threshold`.

Use `--cover-threshold N` to fail the run when overall coverage drops below N:

```bash
mix test.json --quiet --cover --cover-threshold 80
```

Configure modules to ignore in `mix.exs`:

```elixir
def project do
  [
    # ...
    test_coverage: [
      ignore_modules: [MyApp.GeneratedModule]
    ]
  ]
end
```

### Iteration Workflow

When previous test failures exist (`.mix_test_failures`), a helpful tip is shown:

```
TIP: 3 previous failure(s) exist. Consider:
  mix test.json --failed
  mix test.json test/unit/ --failed
  mix test.json --only integration --failed
```

This warning is automatically skipped when:
- `--failed` is already used
- A specific file or directory is targeted
- `--only` or `--exclude` tag filters are used
- `--no-warn` flag is passed

### Strict Enforcement

For AI-assisted workflows where forgetting `--failed` wastes time, enable strict enforcement:

```elixir
# config/test.exs
config :ex_unit_json, enforce_failed: true
```

This will exit with an error instead of just warning, forcing the use of `--failed` or focused runs.

### Using with jq

For piping to jq, use `MIX_QUIET=1` to suppress compilation messages that would corrupt the JSON stream:

```bash
# Summary - pipes fine (MIX_QUIET=1 prevents compile output from breaking jq)
MIX_QUIET=1 mix test.json --quiet --summary-only | jq '.summary'

# Full test details - use file to avoid any piping issues
mix test.json --quiet --output /tmp/results.json
jq '.tests[] | select(.state == "failed")' /tmp/results.json
```

**Why `MIX_QUIET=1`?** When code changes trigger recompilation, Mix outputs messages like "Compiling 1 file (.ex)" to stdout before the JSON. This breaks jq parsing. The `--output FILE` approach avoids this entirely.

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
| `coverage` | object | Code coverage data (included with `--cover`) |

### Summary Object

```json
{
  "total": 10,
  "passed": 8,
  "failed": 1,
  "skipped": 1,
  "excluded": 0,
  "invalid": 0,
  "filtered": 0,
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
| `filtered` | integer | Failed tests matching `--filter-out` patterns (only present when non-zero) |
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

## Claude Code Integration

### Automatic Hook Setup

To enforce `mix test.json` usage in Claude Code, add this hook to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Check if this Bash command runs 'mix test' without '.json'. If it matches patterns like 'mix test', 'mix test --failed', 'mix test path/to/test.exs', etc. but does NOT use 'mix test.json', respond with: {\"decision\": \"block\", \"reason\": \"Use 'mix test.json' instead of 'mix test' for AI-friendly JSON output\"}. If the command uses 'mix test.json' or is not a mix test command, respond with: {\"decision\": \"allow\"}."
          }
        ]
      }
    ]
  }
}
```

This hook:
- Intercepts all Bash commands before execution
- Blocks `mix test` commands that don't use the `.json` variant
- Allows `mix test.json` and all non-test commands through

### Alternative: Command-Based Hook

For a faster, deterministic check, use a command hook with a bash script:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'read input; cmd=$(echo \"$input\" | jq -r \".tool_input.command\"); if echo \"$cmd\" | grep -qE \"^mix\\s+test(\\s|$)\" && ! echo \"$cmd\" | grep -qE \"^mix\\s+test\\.json\"; then echo \"{\\\"decision\\\": \\\"block\\\", \\\"reason\\\": \\\"Use mix test.json instead of mix test\\\"}\" >&2; exit 2; fi'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Hook Events Reference

| Event | When | Use Case |
|-------|------|----------|
| `PreToolUse` | Before tool runs | Block `mix test`, enforce `mix test.json` |
| `PostToolUse` | After tool runs | React to test results, trigger follow-up actions |
| `SessionStart` | Session begins | Load project context, set environment |

For comprehensive hook documentation, see the [Claude Code Hooks Guide](https://docs.anthropic.com/en/docs/claude-code/hooks).

## Requirements

- Elixir 1.18+ (uses built-in `:json` module)

## License

MIT License - see LICENSE file for details.
