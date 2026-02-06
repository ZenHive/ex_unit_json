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
```

See [ExUnitJSON module docs](https://hexdocs.pm/ex_unit_json/ExUnitJSON.html) for full options and schema.
