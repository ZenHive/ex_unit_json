# AGENT.md - AI Editor Guide for ExUnitJSON

This file is for AI assistants (Claude Code, Cursor, Copilot, etc.) to understand
how to use ExUnitJSON effectively.

## Start Here (Default Workflow)

**Most common pattern - fast iteration on failures:**

```bash
# First run or after code changes
mix test.json --quiet --summary-only

# Iterating on failures (ALWAYS use --failed for speed)
mix test.json --quiet --failed --first-failure
```

**When NOT to use --failed:**
- After changing test infrastructure, fixtures, or shared setup code
- After adding new test files (new tests won't be in .mix_test_failures)
- When you want to verify a full green suite

---

## When to Use

Use `mix test.json` instead of `mix test` when:
- Running tests programmatically
- Analyzing test failures
- Iterating on fixes
- You need structured failure data

## Installation Reminder

Consuming projects must add to their `mix.exs`:

```elixir
def cli do
  [preferred_envs: ["test.json": :test]]
end
```

Without this, you'll get: `"mix test" is running in the "dev" environment`

## Quick Reference

### Fast iteration on failures
```bash
mix test.json --failed --quiet --first-failure
```
Returns only the first failure with clean JSON. Fix it, repeat.

### Overview of test health
```bash
mix test.json --quiet --summary-only
```
Returns just counts: total, passed, failed, skipped.

### Analyze failure patterns
```bash
mix test.json --failed --quiet --group-by-error --summary-only
```
Groups failures by error message. Shows which errors are most common.

### Filter known issues
```bash
mix test.json --quiet --group-by-error --filter-out "credentials" --filter-out "rate limit"
```
Excludes failures matching patterns. "filtered" count shows how many were excluded.

### Full failure details
```bash
mix test.json --failed --quiet --failures-only
```
Returns all failed tests with full assertion data and stacktraces.

## Key Flags

| Flag | Purpose |
|------|---------|
| `--quiet` | Always use. Suppresses Logger noise for clean JSON. |
| `--failed` | Only re-run previously failed tests. Fast iteration. |
| `--summary-only` | Just counts, no test details. Quick health check. |
| `--failures-only` | Only include failed tests in output. |
| `--first-failure` | Stop at first failure. Fastest iteration. |
| `--group-by-error` | Cluster failures by error message. Pattern detection. |
| `--filter-out "X"` | Exclude failures matching pattern. Can repeat. |
| `--output FILE` | Write to file instead of stdout. |

## Output Structure

```json
{
  "summary": {
    "total": 100,
    "passed": 80,
    "failed": 20,
    "filtered": 15,
    "result": "failed"
  },
  "error_groups": [
    {
      "pattern": "Connection refused",
      "count": 10,
      "example": {"file": "...", "line": 42, "name": "..."}
    }
  ],
  "tests": [...]
}
```

Notes:
- `filtered` only appears with `--filter-out`
- `error_groups` only appears with `--group-by-error`
- `tests` is omitted with `--summary-only`

## Recommended Workflows

### 1. Initial assessment
```bash
mix test.json --quiet --group-by-error --summary-only
```
See how many failures and what patterns exist.

### 2. Filter noise, see real issues
```bash
mix test.json --quiet --group-by-error --filter-out "credentials" --summary-only
```
Remove expected failures (missing credentials, rate limits, etc.)

### 3. Fix one at a time
```bash
mix test.json --failed --quiet --first-failure
```
Get the first failure, fix it, repeat until green.

### 4. Verify fix
```bash
mix test.json --failed --quiet --summary-only
```
Quick check if failure count decreased.

## Tips

- **Always use `--quiet`** - Logger output pollutes JSON
- **Use `--failed` for iteration** - Much faster than running all tests
- **`--group-by-error` reveals patterns** - 50 "connection refused" errors = 1 root cause
- **`--filter-out` is repeatable** - Add multiple patterns to exclude

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 2 | Test failures (JSON still valid, check `summary.result`) |

Note: Exit code 2 may trigger shell error display. Use `2>&1` to capture both streams.

## Common jq Patterns

```bash
# Pretty summary
mix test.json --quiet --summary-only | jq '.summary'

# Just error patterns and counts
mix test.json --quiet --group-by-error --summary-only | jq '.error_groups | map({pattern, count})'

# Top 5 error groups
mix test.json --quiet --group-by-error --summary-only | jq '.error_groups[:5]'

# Files with failures
mix test.json --quiet --failures-only | jq '.tests[].file' | sort -u

# Count failures per file
mix test.json --quiet --failures-only | jq '.tests | group_by(.file) | map({file: .[0].file, count: length})'
```

## Handling Large Output

For large test suites, output may exceed context limits:

1. **Quick health check**: Use `--summary-only`
2. **Write to file**: Use `--output /tmp/results.json` and read selectively with jq
3. **Reduce noise first**: Use `--filter-out` patterns before requesting full output

```bash
# Example: selective reading from file
mix test.json --quiet --output /tmp/results.json
jq '.error_groups[:5]' /tmp/results.json  # First 5 groups
jq '.tests | length' /tmp/results.json    # Just count
```

## Combining with ExUnit Flags

ExUnit flags work alongside ex_unit_json flags:

```bash
# Run only integration tests, show failures
mix test.json --only integration --quiet --failures-only

# Run specific file with JSON output
mix test.json test/my_test.exs --quiet --summary-only

# Seed for reproducibility
mix test.json --seed 12345 --quiet --failures-only
```

## Troubleshooting

### Mixed output (before --quiet existed)
If Logger output mixes with JSON:
```bash
mix test.json --summary-only 2>&1 | grep -E '^\{'
# Or
mix test.json --summary-only 2>&1 | tail -1
```

### Capturing both streams
```bash
mix test.json --quiet --summary-only 2>&1
```
