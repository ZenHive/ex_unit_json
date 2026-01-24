# AGENT.md - AI Editor Guide for ExUnitJSON

This file is for AI assistants (Claude Code, Cursor, Copilot, etc.) to understand
how to use ExUnitJSON effectively.

## Start Here (Default Workflow)

**v0.3.0+: Default shows only failures (AI-optimized)**

```bash
# First run - see failures directly (default behavior)
mix test.json --quiet

# Iterate on failures (ALWAYS use --failed for speed)
mix test.json --quiet --failed --first-failure

# See all tests when needed
mix test.json --quiet --all
```

When all tests pass, you get an empty tests array:
```json
{"version":1,"summary":{"total":50,"passed":50,"failed":0},"tests":[]}
```

**Automatic reminders:** If you forget `--failed` when failures exist, you'll see:
```
TIP: 3 previous failure(s) exist. Consider:
  mix test.json --failed
  mix test.json test/unit/ --failed
  mix test.json --only integration --failed
```

This warning is automatic - no flag needed. It's skipped when you're already being focused (using `--failed`, targeting files/dirs, or using tag filters).

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

### First run - see failures directly (DEFAULT)
```bash
mix test.json --quiet
```
Runs all tests, returns only failures with full details (v0.3.0+ default).

### Iterate on failures (fast)
```bash
mix test.json --quiet --failed --first-failure
```
Only runs previously failed tests, stops at first failure. Fix it, repeat.

### Verify all failures fixed
```bash
mix test.json --quiet --failed --summary-only
```
Quick check if failure count decreased after fixes.

### See all tests (when needed)
```bash
mix test.json --quiet --all
```
Returns all tests including passing. Use when you need full test details.

### Analyze failure patterns (large suites)
```bash
mix test.json --quiet --group-by-error --summary-only
```
Groups failures by error message. Shows which errors are most common.

### Filter known issues
```bash
mix test.json --quiet --filter-out "credentials" --filter-out "rate limit"
```
Excludes failures matching patterns. "filtered" count shows how many were excluded.

### Full suite health check
```bash
mix test.json --quiet --summary-only
```
Returns just counts: total, passed, failed, skipped. Use when you need total counts.

## Key Flags

| Flag | Purpose |
|------|---------|
| `--quiet` | Always use. Suppresses Logger noise for clean JSON. |
| `--failed` | Only re-run previously failed tests. Fast iteration. |
| `--summary-only` | Just counts, no test details. Quick health check. |
| `--all` | Include ALL tests (default shows only failures). |
| `--failures-only` | Only include failed tests in output. (DEFAULT in v0.3.0+) |
| `--first-failure` | Stop at first failure. Fastest iteration. |
| `--group-by-error` | Cluster failures by error message. Pattern detection. |
| `--filter-out "X"` | Exclude failures matching pattern. Can repeat. |
| `--output FILE` | Write to file instead of stdout. |
| `--no-warn` | Suppress the "use --failed" warning. |

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

### 1. First run - see failures directly (default)
```bash
mix test.json --quiet
```
Runs all tests, shows only failures (v0.3.0+ default). No extra flags needed.

### 2. Filter noise, see real issues
```bash
mix test.json --quiet --filter-out "credentials" --filter-out "rate limit"
```
Remove expected failures (missing credentials, rate limits, etc.)

### 3. Analyze failure patterns (large suites)
```bash
mix test.json --quiet --group-by-error --summary-only
```
Groups failures by error message. Use when you have many failures.

### 4. Fix one at a time
```bash
mix test.json --quiet --failed --first-failure
```
Get the first failure, fix it, repeat until green.

### 5. Verify fix
```bash
mix test.json --quiet --failed --summary-only
```
Quick check if failure count decreased.

### 6. See all tests (when needed)
```bash
mix test.json --quiet --all
```
Show all tests including passing. Use when investigating test coverage or structure.

## Tips

- **Always use `--quiet`** - Logger output pollutes JSON
- **Use `--failed` for iteration** - Much faster than running all tests
- **`--group-by-error` reveals patterns** - 50 "connection refused" errors = 1 root cause
- **`--filter-out` is repeatable** - Add multiple patterns to exclude

## Strict Enforcement

For projects where forgetting `--failed` is particularly costly, enable strict mode:

```elixir
# config/test.exs
config :ex_unit_json, enforce_failed: true
```

This will block full test runs when failures exist, requiring `--failed` or focused runs.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 2 | Test failures (JSON still valid, check `summary.result`) |

Note: Exit code 2 may trigger shell error display. Use `2>&1` to capture both streams.

## Using jq

For piping to jq, use `MIX_QUIET=1` to suppress compilation messages that would corrupt the JSON stream:

```bash
# Summary - pipes fine (MIX_QUIET=1 prevents compile output from breaking jq)
MIX_QUIET=1 mix test.json --quiet --summary-only | jq '.summary'
MIX_QUIET=1 mix test.json --quiet --group-by-error --summary-only | jq '.error_groups | map({pattern, count})'
MIX_QUIET=1 mix test.json --quiet --group-by-error --summary-only | jq '.error_groups[:5]'

# Full test details - use file (avoids piping issues entirely)
mix test.json --quiet --output /tmp/results.json
jq '.tests[] | select(.state == "failed")' /tmp/results.json
jq '.tests[].file' /tmp/results.json | sort -u
jq '.tests | group_by(.file) | map({file: .[0].file, count: length})' /tmp/results.json
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

### jq parse errors
If you get `jq: parse error`, compilation warnings or other output may be mixing with JSON. See "Using jq" section above - use `--output FILE` for full test output.

### Capturing both streams
```bash
mix test.json --quiet --summary-only 2>&1
```
