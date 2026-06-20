# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ExUnitJSON (v0.6.0) is an Elixir library published to Hex.pm that provides AI-friendly JSON test output for ExUnit. It's a drop-in replacement for `mix test` via `mix test.json`, outputting structured JSON for AI editors like Claude Code. No runtime dependencies — uses Elixir 1.18+ built-in `:json` module.

## Commands

```bash
# Run tests (standard)
mix test
mix test test/ex_unit_json_test.exs
mix test test/ex_unit_json_test.exs:5

# Run tests with JSON output (this project's own tool)
mix test.json --quiet
mix test.json --quiet --failed --first-failure   # iterate on failures
mix test.json --quiet --cover                     # with coverage

# Quality
mix format
mix credo
mix sobelow
mix dialyzer.json --quiet
mix doctor
mix docs

# Full quality gate (compile-warnings, format, credo+ex_slop, sobelow, doctor,
# ex_dna clones, reach arch+smells, dialyzer, test.json --cover)
mix ci
```

## Architecture

### Data Flow

```
mix test.json [flags]
  → Mix.Tasks.Test.Json parses JSON-specific flags, passes rest to mix test
  → Sets Application env :ex_unit_json :opts
  → mix test --formatter ExUnitJSON.Formatter [remaining args]
  → Formatter (GenServer) accumulates events via ExUnit callbacks
  → On suite_finished: Filters → Encodes → Outputs JSON
```

### Module Responsibilities

| Module | Role | Side Effects? |
|--------|------|--------------|
| `ExUnitJSON` | Documentation hub only — no implementation code | No |
| `ExUnitJSON.Formatter` | GenServer implementing ExUnit formatter. Accumulates test results, outputs JSON on suite finish | Yes (IO, Logger) |
| `ExUnitJSON.JSONEncoder` | Pure data transform: ExUnit structs → JSON-serializable maps. Handles truncation, path normalization, tag filtering | No |
| `ExUnitJSON.Config` | Reads/validates options from Application env | No |
| `ExUnitJSON.Filters` | Applies filtering logic (summary-only, first-failure, failures-only, filter-out patterns) | No |
| `ExUnitJSON.ErrorGroups` | Groups failures by first line of error message for `--group-by-error` | No |
| `ExUnitJSON.Coverage` | Wraps Erlang `:cover` module for per-module coverage with uncovered line numbers | Yes (:cover) |
| `ExUnitJSON.CompactOutput` | JSONL format with minimal keys (`f`, `n`, `s`, `e`, `x`) for `--compact` | No |
| `ExUnitJSON.Trace` | Test-side `setup` callback for `@tag trace_messages`. Starts a recorder tracing the test process tree | Yes (:trace, on_exit) |
| `ExUnitJSON.Trace.Recorder` | Per-test tracer process. Ring-buffers send/receive via OTP-27 trace sessions; snapshots mailboxes; writes to Store on test death | Yes (:trace, process) |
| `ExUnitJSON.Trace.Store` | Registered owner of a named ETS table handing trace data from test process to formatter | Yes (ETS) |
| `Mix.Tasks.Test.Json` | Mix task entry point. Parses flags, manages coverage lifecycle, delegates to `mix test` | Yes (subprocess) |

### Key Design Patterns

- **Codec boundary**: JSONEncoder returns plain maps; JSON serialization happens only in Formatter
- **Buffered output**: All results accumulated in GenServer state, output once at suite end (not streaming)
- **Application env for config**: Single-instance test runs make global state acceptable here
- **Pure core**: Encoder, Filters, ErrorGroups, CompactOutput are all pure functions — easy to test in isolation

### Test Structure

- **Unit tests** (`test/ex_unit_json/`): One test file per module
- **Golden tests** (`test/golden_test.exs`): Schema v1 validation against real test output
- **Integration test apps** (`test_apps/`): Separate Mix projects testing `--quiet`, coverage, and Phoenix integration via `System.cmd`
- Coverage tags: `coverage_test.exs` uses `@tag :coverage_unit` to exclude during coverage runs
- Tests modifying Application env use `async: false` with setup/teardown to restore state

### Modules Excluded from Coverage

`Mix.Tasks.Test.Json` and `ExUnitJSON.Coverage` are tested via subprocess integration tests (`System.cmd`), so Erlang's `:cover` can't track their execution. They're excluded in `mix.exs` `test_coverage/0`.

<!--
  Selective-load (Opus 4.8): Elixir Library template = floor only.
  Everything else (elixir-setup, ex-unit-json, dialyzer-json, code-style,
  development-commands/-philosophy, task-prioritization/-writing, workflow-philosophy,
  web-command) is skill-on-demand via the elixir / task-driver / dev-lifecycle plugins.
  Not a delegation repo (no Codex/Cursor) and not a presence repo — so delegation-rules
  and across-instances are intentionally omitted. Re-add an @-import only if Opus
  starts failing on that surface. See ~/.claude/setup-guide.md.
-->
@~/.claude/includes/critical-rules.md
