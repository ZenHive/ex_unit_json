---
sha: 7f39134d1e7e26b0bf93437fe31f9b0032b660d3
short_sha: 7f39134
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Breaking: Default to failures-only output (v0.3.0)

**Original commit:** 7f39134 — `Breaking: Default to failures-only output (v0.3.0)`
**Author:** E.FU
**Files touched:** 12 (3 production: filters.ex, config.ex, test_json.ex)
**LOC:** ±296
**Source PR:** none (direct push to development)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | doc-gap | lib/ex_unit_json/filters.ex:30 | `filter_tests/2` Priority docs still said "Default - Returns all tests" after the default flipped | applied |
| 2 | 3 | doc-gap | lib/ex_unit_json/formatter.ex:7 | Moduledoc said "outputs … all test results"; default filters to failures since this commit | applied |
| 3 | 6 | test-integrity | test/mix/tasks/test_json_test.exs:1348 | Option-parsing tests exercised a copied parser, not production code (this commit added `--all` in both places) | applied (parse_json_opts/1 exposed; copy deleted) |
| 4 | 4 | process | — | Direct push, no PR review trail | recorded only |

## Auto-applied fixes

- lib/ex_unit_json/filters.ex: Priority docs now state failures-only is the default since v0.3.0
- lib/ex_unit_json/formatter.ex: moduledoc clarifies default output filtering
- lib/mix/tasks/test_json.ex: `parse_json_opts/1` (+ `focused_run?/1`) exposed as `@doc false` public functions for testing
- test/mix/tasks/test_json_test.exs: ~70-line copied parser deleted; tests now call the production parser

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1, 2, 3 (parser duplication independently flagged by Claude and Codex)
Codex-only findings (discarded): README `~> 0.1.0` snippet (historical-only); README:307 passing-suite example (historical-only)
