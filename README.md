# ExUnitJSON

AI-friendly JSON test output for ExUnit.

ExUnitJSON provides structured JSON output from `mix test` for use with AI editors like Claude Code, Cursor, and other tools that benefit from machine-parseable test results.

[Full Documentation on HexDocs](https://hexdocs.pm/ex_unit_json)

## Features

- Drop-in replacement for `mix test` with JSON output
- **AI-optimized default**: Shows only failures (use `--all` for all tests)
- **Automatic retry-on-flaky** (default): re-runs failed tests once; failures that heal are reported as `flaky` instead of blocking (`--no-retry` to opt out)
- **Code coverage** with `--cover` and **coverage gating** with `--cover-threshold N`
- Detailed failure information with assertion values and stacktraces
- Filtering: `--summary-only`, `--first-failure`, `--filter-out`, `--group-by-error`
- File output: `--output results.json`
- Deterministic test ordering for reproducible output
- No runtime dependencies (uses Elixir 1.18+ built-in `:json`)

## Installation

Add `ex_unit_json` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false}
  ]
end
```

Configure Mix to run `test.json` in the test environment:

```elixir
def cli do
  [preferred_envs: ["test.json": :test]]
end
```

## Usage

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

### Options

| Flag | Description |
|------|-------------|
| `--quiet` | Suppress Logger output and TIP warnings for clean JSON piping |
| `--all` | Include all tests (default shows only failures) |
| `--summary-only` | Output only the summary, no individual tests |
| `--first-failure` | Output only the first failed test |
| `--filter-out PATTERN` | Mark matching failures as filtered (repeatable) |
| `--group-by-error` | Group failures by similar error message |
| `--output FILE` | Write JSON to file instead of stdout |
| `--cover` | Enable code coverage |
| `--compact` | Output JSONL with minimal keys (compact format) |
| `--cover-threshold N` | Fail if coverage below N% (requires `--cover`) |
| `--no-warn` | Suppress the "use --failed" tip |
| `--no-retry` | Disable automatic retry of failed tests |

All standard `mix test` flags are passed through (`--failed`, `--only`, `--exclude`, `--seed`, etc.).

### Automatic Retry (Flaky Healing)

When a run has failures, `mix test.json` re-runs only the previously-failed tests once and merges the results:

- **confirmed** — failed both runs → stays red (`tests`), exits non-zero.
- **flaky** — failed then passed → moved to a top-level `flaky` array (named, never hidden) and no longer blocks the run.

When every first-run failure heals, `summary.result` is `"passed"` and the exit code is `0`, so an AI agent isn't blocked by an intermittent async/GenServer/LiveView failure — while each flaky test is still surfaced. A `retry` metadata object (`retried`/`confirmed`/`flaky`) is added when a retry runs. Tests invalidated by a flaky `setup_all` resolve to their retry state (passed or failed) instead of staying `invalid`.

Retry is skipped for `--no-retry`, `config :ex_unit_json, retry: false`, `--failed`, `--summary-only`, `--first-failure`, `--compact`, `--group-by-error`, `--filter-out`, a `file:line` target, or umbrella projects. A green suite never triggers a second run.

```elixir
# Disable globally in config/test.exs
config :ex_unit_json, retry: false
```

### Code Coverage

```bash
mix test.json --quiet --cover
mix test.json --quiet --cover --cover-threshold 80
```

Coverage output includes total percentage, per-module breakdown, and uncovered line numbers. Coverage cannot be combined with `--compact` (a warning is printed and coverage data is omitted). See [full documentation](https://hexdocs.pm/ex_unit_json) for schema details.

### Using with jq

```bash
# Summary (MIX_QUIET=1 prevents compile output from breaking jq)
MIX_QUIET=1 mix test.json --quiet --summary-only | jq '.summary'

# Full details via file (avoids piping issues entirely)
mix test.json --quiet --output /tmp/results.json
jq '.tests[] | select(.state == "failed")' /tmp/results.json
```

## Requirements

- Elixir 1.18+ (uses built-in `:json` module)

## License

MIT
