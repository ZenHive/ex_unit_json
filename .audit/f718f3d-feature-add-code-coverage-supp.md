---
sha: f718f3dbabfd9c18deb2550b90db2cc602efe5c1
short_sha: f718f3d
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Feature: Add code coverage support (v0.4.0)

**Original commit:** f718f3d — `Feature: Add code coverage support (v0.4.0)`
**Author:** E.FU
**Files touched:** 11 (3 production: coverage.ex new, test_json.ex, mix.exs)
**LOC:** ±1105
**Source PR:** none (direct push to development)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | bug | lib/mix/tasks/test_json.ex (maybe_start_coverage) | `Coverage.start()` errors silently ignored → incomplete/empty coverage emitted without warning | applied (stderr warning) |
| 2 | 3 | bug | lib/mix/tasks/test_json.ex (run/1) | Internal `--exclude coverage_unit` injected before the failed-usage check → `--cover` suppressed the `--failed` TIP | applied (check uses user's original args) |
| 3 | — | bug | historical | Coverage started before compile on clean builds | historical-only (fixed by 59c399c) |
| 4 | — | bug | historical | `--cover --compact` decode crash | historical-only (fixed by 59c399c) |
| 5 | 4 | process | — | Direct push, no PR review trail | recorded only |

## Auto-applied fixes

- lib/mix/tasks/test_json.ex: coverage start failures now print a stderr warning
- lib/mix/tasks/test_json.ex: failed-usage check + hint now use the user's original args (passthrough), not coverage-modified args

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1, 2 (Codex-found, Claude-verified against HEAD; fixes applied)
Codex priority calibration: Codex rated finding 1 at 7; Claude rated 4 (rare failure mode — beam without debug info). Applied either way.
