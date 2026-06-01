---
sha: 9bf7fe06fc5867a1919fb38c54bb510123e58f12
short_sha: 9bf7fe0
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Review: merge error_groups by pattern, sum filtered count, tighten rm errors

**Original commit:** 9bf7fe0 — `Review: merge error_groups by pattern, sum filtered count, tighten rm errors`
**Author:** E.FU
**Files touched:** 3 (2 production: formatter.ex, test_json.ex)
**LOC:** ±114
**Source PR:** #1 (review-fix commit on the umbrella-support branch)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | bug | lib/ex_unit_json/formatter.ex (merge_error_groups) | Merged groups not re-sorted by count desc — violates ErrorGroups' documented ordering invariant | applied |
| 2 | 5 | bug | lib/mix/tasks/test_json.ex | `File.rm` failure → stale merge (same as 18b9073 finding 3 — deduped) | applied (see 18b9073 report) |
| 3 | — | doc-gap | historical | No CHANGELOG entry for umbrella merge-behavior change | historical-only (documented under v0.4.3) |

## Auto-applied fixes

- lib/ex_unit_json/formatter.ex: count-desc sort added to merged error_groups; test added

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1, 2 (Codex-found, Claude-verified)
