# ExUnitJSON

AI-friendly JSON test output for ExUnit.

ExUnitJSON provides structured JSON output from `mix test` for use with AI editors like Claude Code, Cursor, and other tools that benefit from machine-parseable test results.

[Full Documentation on HexDocs](https://hexdocs.pm/ex_unit_json)

## Features

- Drop-in replacement for `mix test` with JSON output
- **AI-optimized default**: Shows only failures (use `--all` for all tests)
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
| `--quiet` | Suppress Logger output for clean JSON |
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

All standard `mix test` flags are passed through (`--failed`, `--only`, `--exclude`, `--seed`, etc.).

### Code Coverage

```bash
mix test.json --quiet --cover
mix test.json --quiet --cover --cover-threshold 80
```

Coverage output includes total percentage, per-module breakdown, and uncovered line numbers. See [full documentation](https://hexdocs.pm/ex_unit_json) for schema details.

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
