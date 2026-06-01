---
sha: 59c399c4e52f7ab14a32d452a163d3203c884cbd
short_sha: 59c399c
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Fix: Coverage edge cases and default to --cover flag (v0.4.1)

**Original commit:** 59c399c — `Fix: Coverage edge cases and default to --cover flag (v0.4.1)`
**Author:** E.FU
**Files touched:** 16 (2 production: test_json.ex, coverage.ex)
**LOC:** ±448
**Source PR:** none (direct push to development)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5 | bug | lib/mix/tasks/test_json.ex:184 | `--cover` precompile always used `--no-warnings-as-errors`, ignoring user's `--warnings-as-errors` / `--no-compile` | applied (coverage_precompile_args/1 honors both) |
| 2 | 3 | doc-gap | README.md (coverage section) | `--cover --compact` incompatibility undocumented | applied |
| 3 | 4 | process | — | Direct push, no PR review trail | recorded only |

## Auto-applied fixes

- lib/mix/tasks/test_json.ex: new `coverage_precompile_args/1` — skips precompile on `--no-compile`, forwards `--warnings-as-errors`; unit tests added
- README.md + moduledoc: `--cover`/`--compact` incompatibility documented

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1 (Codex rated 8; Claude rated 5 — edge case, contained fix), 2
