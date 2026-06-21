# AGENTS.md - AI Editor Guide

AI-friendly JSON test output for ExUnit.

[Full Documentation (llms.txt)](https://hexdocs.pm/ex_unit_json/llms.txt)

## Quick Start

```bash
mix test.json --quiet
```

## Key Commands

```bash
# First run - see failures (default)
mix test.json --quiet

# Iterate on failures (fast)
mix test.json --quiet --failed --first-failure

# Health check
mix test.json --quiet --summary-only

# Coverage with a gate (exit 2 if under threshold)
mix test.json --quiet --cover --cover-threshold 80
```

## Features

- **Auto-retry on flaky** (default): failed tests re-run once; failures that heal are reported as `flaky[]` instead of blocking the run. Opt out with `--no-retry`.
- **Coverage**: `--cover` for per-module percentages + uncovered lines; `--cover-threshold N` to fail under N%.
- **Message tracing** (flight recorder): tag a test with `@tag trace_messages: true` (wire `setup {ExUnitJSON.Trace, :setup}` once into a shared case) and a failing test attaches the inter-process `send`/`receive` flow as a `"trace"` block. Failing tests only; zero-cost when untagged. Requires OTP 27+.

See [ExUnitJSON module docs](https://hexdocs.pm/ex_unit_json/ExUnitJSON.html) for full options and schema.
