---
sha: b11972da6257170820e141f52de00ca46c776264
short_sha: b11972d
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Chore: prepare v0.4.2 release

**Original commit:** b11972d — `Chore: prepare v0.4.2 release`
**Author:** E.FU
**Files touched:** 12 (2 production: config.ex, ex_unit_json.ex)
**LOC:** ±101
**Source PR:** none (direct push to development)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | doc-gap | lib/ex_unit_json/config.ex:47 | `hint: boolean()` typespec — actual stored value is a String.t() hint message | applied |
| 2 | 2 | cosmetic | .sobelow-skips:2 | Stale line refs (fingerprint-matched, sobelow passes) | skipped (cosmetic; sobelow --skip exits 0) |
| 3 | 4 | process | — | Direct push, no PR review trail | recorded only |

## Auto-applied fixes

- lib/ex_unit_json/config.ex: `:hint` typespec corrected to `String.t()`; option doc clarified

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1
Codex-only findings (dropped, cosmetic): 2
