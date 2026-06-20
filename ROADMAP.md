# ex_unit_json

**Status:** Phase 2 In Progress (Published to Hex.pm)

> This roadmap is managed by [`rmap`](https://crates.io/crates/rmap). The task
> tables below are rendered from `roadmap/tasks.toml` (canonical source) — edit
> tasks there (or via `rmap` commands), then run `rmap render`. Prose outside the
> marker pairs is preserved.

## Project Overview

**Goal:** Provide AI-friendly JSON test output for ExUnit, enabling AI editors like Claude Code to efficiently parse and reason about test results.

**Target Users:**
- AI editors (Claude Code, Cursor, etc.)
- CI/CD systems needing structured test output
- Developers wanting machine-parseable test results

**Success Metrics:**
- Claude Code can parse output without grep/tail/sed
- All ExUnit test states correctly represented in JSON
- Package published to Hex.pm
- Stable JSON Schema v1 documented and enforced by tests

**Tech Stack:**
- Elixir 1.18+ (for built-in `:json` module)
- ExUnit (formatter API)
- No external dependencies for core functionality

<!-- FOCUS:BEGIN -->
**Focus phase:** 2 — Future Enhancements (10 of 20 done · 0 in progress)

**Last shipped:** Task 31 — BEAM message flight-recorder (@tag trace_messages) on 2026-06-20

**Up next:** Task 20 — Consistent failure_message field (Schema v2) [D:2/B:7/U:7 → Eff:3.5] 🎯
<!-- FOCUS:END -->

---

## Phase 1: MVP Core Features

**Goal:** Working JSON formatter with basic filtering options via `mix test.json`.

**Success Criteria:**
- [x] `mix test.json` outputs valid JSON with all test results
- [x] `--summary-only` flag works
- [x] `--failures-only` flag works
- [x] All edge cases handled (Unicode, long values, setup failures)
- [x] Tests pass with good coverage
- [x] Published to Hex.pm (v0.1.3)
- [x] Output ordering is deterministic (file, line, name)

The `ai_output` bundle folds in the former "Phase 1.5: AI-Friendly Enhancements"
(relative paths, tighter truncation, `--compact`), all shipped in the v0.1.x line.

<!-- TASKS:BEGIN phase=1 -->
> 11 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-mvp-core-features).
<!-- TASKS:END -->

---

## Phase 2: Future Enhancements

**Note:** Prioritized by ROI — `rmap` computes `Eff = (B+U)/(2·D)`. Done features
shipped across the v0.1.x–v0.5.0 line; pending features sorted by efficiency.

<!-- TASKS:BEGIN phase=2 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 13 | ✅ | 🎁 **output_fields** · Default to failures-only output [D:3/B:9/U:9 → Eff:3.0] 🎯 |
| Task 17 | ✅ | 🎁 **output_fields** · --first-failure quick-iteration mode [D:2/B:5/U:5 → Eff:2.5] 🎯 |
| Task 18 | ✅ | 🎁 **output_fields** · --filter-out 'pattern' [D:4/B:8/U:8 → Eff:2.0] 🎯 |
| Task 20 | ⬜ | 🎁 **output_fields** · Consistent failure_message field (Schema v2) [D:2/B:7/U:7 → Eff:3.5] 🎯 |
| Task 21 | ⬜ | 🎁 **output_fields** · --filter-in 'pattern' [D:2/B:5/U:5 → Eff:2.5] 🎯 |
| Task 22 | ⬜ | 🎁 **output_fields** · --min-duration MS filter [D:2/B:4/U:4 → Eff:2.0] 🎯 |
| Task 15 | ✅ | 🎁 **failed_iteration** · Warn-by-default for --failed usage [D:3/B:9/U:9 → Eff:3.0] 🎯 |
| Task 16 | ✅ | 🎁 **failed_iteration** · Smart --failed hint [D:2/B:6/U:6 → Eff:3.0] 🎯 |
| Task 19 | ✅ | 🎁 **error_grouping** · --group-by-error [D:6/B:7/U:7 → Eff:1.17] 📋 |
| Task 23 | ⬜ | 🎁 **error_grouping** · Error type classification [D:5/B:6/U:6 → Eff:1.2] 📋 |
| Task 24 | ⬜ | 🎁 **error_grouping** · --group-by TAG option [D:6/B:6/U:6 → Eff:1.0] 📋 |
| Task 12 | ✅ | 🎁 **infrastructure** · Umbrella project support [D:3/B:7/U:7 → Eff:2.33] 🎯 |
| Task 14 | ✅ | 🎁 **infrastructure** · Code coverage with --cover [D:5/B:7/U:7 → Eff:1.4] 📋 |
| Task 25 | ⬜ | 🎁 **future** · --list flag for test discovery [D:3/B:5/U:5 → Eff:1.67] 🚀 |
| Task 26 | ⬜ | 🎁 **future** · Captured logs inclusion (--include-logs) [D:4/B:5/U:5 → Eff:1.25] 📋 |
| Task 27 | ⬜ | 🎁 **future** · CI systems integration [D:4/B:5/U:5 → Eff:1.25] 📋 |
| Task 28 | ⬜ | 🎁 **future** · Custom output templates [D:6/B:4/U:4 → Eff:0.67] ⚠️ |
| Task 29 | ⬜ | 🎁 **future** · Optional Jason fallback [D:4/B:5/U:5 → Eff:1.25] 📋 |
| Task 30 | ✅ | 🎁 **failed_iteration** · Automatic retry-on-flaky (default ON) [D:7/B:9/U:9 → Eff:1.29] 📋 |
| Task 31 | ✅ | 🎁 **future** · BEAM message flight-recorder (@tag trace_messages) [D:7/B:6/U:5 → Eff:0.79] ⚠️ |
<!-- TASKS:END -->

---

## Technical Decisions

### Architecture Patterns
- **GenServer Formatter:** Accumulate all results, output at end (buffered, not streaming)
- **Separate Encoder:** JSON encoding logic isolated for testability
- **Application.get_env for Options:** Pass options from Mix task to formatter
- **Config Module:** Centralize option parsing/validation in `ExUnitJSON.Config`
- **Codec Boundary:** Encoder returns plain maps/lists; actual JSON serialization only in formatter

### Key Libraries/Dependencies
- **Primary:** Elixir 1.18+'s built-in `:json` module (no runtime dependencies)
- **Fallback (planned — Task 29, not yet implemented):** Optional `Jason` fallback for earlier Elixir versions
- **ex_doc:** Documentation only (dev dependency)

### Compatibility
- **Elixir 1.18+:** Required (native `:json`)
- **Earlier versions:** Not yet supported — planned via the optional Jason fallback (Task 29)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ExUnit formatter API changes | Low | Medium | Pin to stable API, test against multiple Elixir versions |
| Large test suites produce huge JSON | Medium | Low | Add `--failures-only` flag, consider streaming in Phase 2 |
| Non-serializable values in assertions | Medium | Medium | Robust `inspect/1` fallback for all values |
| Users without Elixir 1.18 | Medium | Medium | Provide Jason fallback and document compatibility |

---

## Open Questions

- [x] Hex package vs Elixir core? → Hex package
- [x] Streaming vs buffered JSON? → Buffered (with filtering options)
- [x] Should we truncate very long assertion values? → Yes, with sensible, documented defaults
- [ ] Include captured logs by default or opt-in? → Opt-in (planned for Phase 2)

---

## References

- [ExUnit.Formatter docs](https://hexdocs.pm/ex_unit/ExUnit.Formatter.html)
- [ExUnit source - CLIFormatter](https://github.com/elixir-lang/elixir/blob/main/lib/ex_unit/lib/ex_unit/cli_formatter.ex)

---

## Output Schema v1

Root
- version: integer (1)
- seed: integer
- summary: object
- tests: array of test objects (omitted with `--summary-only`; filtered with `--failures-only`)
- flaky: array of test/module objects that failed then passed on retry (only when a retry healed something)
- retry: object — `ran`/`passes`/`retried`/`confirmed`/`flaky` (only when a retry ran)
- module_failures: array of setup_all failure objects (only when present)
- error_groups: array of error group objects (only with `--group-by-error`)
- coverage: object (only with `--cover`)
- hint: string (only when previous failures exist and auto-retry is off)

Summary
- total: integer
- passed: integer
- failed: integer (confirmed failures, after retry if one ran)
- skipped: integer
- excluded: integer
- invalid: integer (tests invalidated by a setup_all failure)
- filtered: integer (only with `--filter-out`, when non-zero)
- flaky: integer (only when a retry ran)
- duration_us: integer (microseconds)
- result: string ("passed" | "failed")

Test
- name: string
- module: string
- file: string
- line: integer
- state: string ("passed" | "failed" | "skipped" | "excluded" | "invalid")
- duration_us: integer (microseconds)
- tags: object (filtered)
- failures: array of failure objects (only when failed)

Failure
- kind: string (e.g., "error", "exit", "throw", "assertion")
- message: string
- assertion: object (optional; for assertion errors)
  - left: string (inspected/truncated)
  - right: string (inspected/truncated)
  - expr: string
- stacktrace: array of frames

Frame
- file: string
- line: integer
- module: string (optional)
- function: string (optional)
- arity: integer (optional)
- app: string (optional)

Truncation limits (internal encoder constants, not emitted in output)
- value_char_limit: 500
- expr_char_limit: 200
- collection_item_limit: 50
- printable_limit: 500

Error Group (only with `--group-by-error`)
- pattern: string (first line of error message, max 200 chars)
- count: integer
- example: object
  - name: string
  - module: string
  - file: string
  - line: integer

Ordering
- Tests are sorted by `file`, then `line`, then `name` for determinism.

Versioning
- Breaking schema changes bump `version` and are noted in CHANGELOG.
