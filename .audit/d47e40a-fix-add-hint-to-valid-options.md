---
sha: d47e40abe5572320cc0f7eb06e2b6afe12072b3e
short_sha: d47e40a
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Fix: Add hint to valid options and improve coverage to 97.8%

**Original commit:** d47e40a — `Fix: Add hint to valid options and improve coverage to 97.8%`
**Author:** E.FU
**Files touched:** 3 (config.ex, mix.exs, formatter_test.exs)
**LOC:** ±32
**Source PR:** none (direct push to development)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5 | doc-gap | CHANGELOG.md | User-visible bug fix (`:hint` stripped by validation → never appeared in output) had no changelog entry in any release | applied (added to v0.4.3 Internal section) |
| 2 | 4 | doc-gap | lib/ex_unit_json.ex | Output schema docs omitted the top-level `hint` key | applied |
| 3 | 4 | process | — | Direct push, no PR review trail | recorded only |

## Auto-applied fixes

- CHANGELOG.md (v0.4.3): documented the `:hint` validation fix
- lib/ex_unit_json.ex: `hint` added to the root schema table and example

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1 (flagged independently by both), 2
Codex-only findings (discarded): config.ex typespec gap (historical-only — fixed by b11972d)
