---
sha: 18b907367aedd034012a2267396b553e085e98fb
short_sha: 18b9073
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Add umbrella project support for mix test.json

**Original commit:** 18b9073 — `Add umbrella project support for mix test.json`
**Author:** talkingdonkeyz
**Files touched:** 13 (2 production: formatter.ex, test_json.ex)
**LOC:** ±335
**Source PR:** #1 (Add umbrella project support) — no bot reviews, no inline comments

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 6 | bug | lib/ex_unit_json/formatter.ex (write_output) | Umbrella + `--compact` + `--output`: merge path `:json.decode`s the first app's JSONL → GenServer crash | applied (JSONL concatenation merge) |
| 2 | 4 | bug | lib/ex_unit_json/formatter.ex (merge_tests) | Umbrella + `--first-failure`: each app contributes its own "first failure" | applied (cap re-applied across merge) |
| 3 | 5 | bug | lib/mix/tasks/test_json.ex (maybe_clear_output_file) | `File.rm` failure → warning only → stale JSON merged into new run | applied (truncate fallback, raise if both fail) |
| 4 | — | bug | historical | Duplicate error_groups across apps; `filtered` count dropped | historical-only (fixed by 9bf7fe0) |
| 5 | — | doc-gap | historical | No CHANGELOG entry in this commit | historical-only (documented under v0.4.3) |

## Auto-applied fixes

- lib/ex_unit_json/formatter.ex: `merge_existing_output/2` — compact (JSONL) outputs concatenate; JSON documents merge as before; test added
- lib/ex_unit_json/formatter.ex: `--first-failure` capped across the merged document; test added
- lib/mix/tasks/test_json.ex: `clear_output_file/1` (public for testing) — rm → truncate fallback → raise; 4 unit tests added

## PR / acceptance criteria

PR #1 had no stated acceptance criteria and no bot reviews. The umbrella support itself was verified
merged and working (covered by golden_test.exs integration test). All gaps found were edge-case
combinations (compact/first-failure/locked-file) not covered by the original PR scope.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1, 2, 3 (all Codex-found, Claude-verified with named triggering inputs)
