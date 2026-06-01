---
sha: b9ce7ef6c1867938f9df731c0b0ce65fcf9387aa
short_sha: b9ce7ef
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: clean
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Docs: Recommend --failures-only as default first run (v0.2.14)

**Original commit:** b9ce7ef — `Docs: Recommend --failures-only as default first run (v0.2.14)`
**Author:** E.FU
**Files touched:** 4 (AGENT.md, CHANGELOG.md, README.md, mix.exs)
**LOC:** ±117
**Source PR:** none (direct push to development)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | — | doc-gap | AGENT.md:67 | "--first-failure stops at first failure" — it filters output, doesn't stop execution | historical-only (AGENT.md replaced by AGENTS.md pointer file) |
| 2 | — | doc-gap | AGENT.md:146 | `--filter-out` described as removing failures; it marks them | historical-only |
| 3 | — | doc-gap | README.md:24 | Install snippet `~> 0.1.0` stale at v0.2.14 | historical-only (HEAD uses `~> 0.4`) |
| 4 | 4 | process | — | Direct push, no PR review trail | recorded only |

## Auto-applied fixes

(none — all findings superseded by later commits)

## Codex second-opinion

Status: dual-reviewer
All Codex findings confirmed historical-only; no fixes required at HEAD.
