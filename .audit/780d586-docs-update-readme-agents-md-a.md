---
sha: 780d58682764c1c638fa9855aa12a438143a82bb
short_sha: 780d586
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Docs: Update README, AGENTS.md, and moduledoc for v0.4.1

**Original commit:** 780d586 — `Docs: Update README, AGENTS.md, and moduledoc for v0.4.1`
**Author:** E.FU
**Files touched:** 5 (1 production: lib/ex_unit_json.ex moduledoc)
**LOC:** ±1249
**Source PR:** none (direct push to development)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | doc-gap | lib/ex_unit_json.ex (Test Object) | `state` enum omitted `"invalid"` (encoder emits it; summary counts it) | applied |
| 2 | 4 | doc-gap | lib/ex_unit_json.ex (Root Object) | Top-level `hint` key undocumented | applied |
| 3 | 3 | doc-gap | lib/ex_unit_json.ex | `module_failures` object shape never documented | applied (new Module Failure Object section) |
| 4 | 4 | doc-gap | lib/ex_unit_json.ex (coverage example) | Plain `--cover` example included `threshold`/`threshold_met` | applied |
| 5 | 3 | doc-gap | lib/ex_unit_json.ex (Quick Start) | All-pass example showed minimal shape; actual output includes seed + full summary | applied |
| 6 | 4 | process | — | Direct push, no PR review trail | recorded only |

## Auto-applied fixes

- lib/ex_unit_json.ex: `"invalid"` added to state enum; `hint` row + Module Failure Object section added; coverage and Quick Start examples corrected

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1, 2, 3, 4, 5 (all Codex-found, Claude-verified, all still present at HEAD)
