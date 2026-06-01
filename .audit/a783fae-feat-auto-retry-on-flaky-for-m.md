---
sha: a783fae3c05f5b79840b7e7d988926b9c38df833
short_sha: a783fae
audited_at: 2026-06-01
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat: auto-retry-on-flaky for mix test.json (v0.5.0)

**Original commit:** a783fae — `feat: auto-retry-on-flaky for mix test.json (v0.5.0)`
**Author:** E.FU
**Files touched:** 13 (4 production: retry.ex new, test_json.ex, config.ex, ex_unit_json.ex)
**LOC:** ±1072
**Source PR:** #2 (feat: auto-retry-on-flaky) — Codex GH bot (1 P2 inline) + Copilot (1 inline)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 8 | bug | lib/ex_unit_json/retry.ex:63 | Invalid-state tests (setup_all casualties) unhandled in merge: healed invalids stayed in `tests` while result went green (`--all`); run-2 failures of previously-invalid tests silently dropped (default mode); `summary.invalid` stale on partial heal | applied (comprehensive fix) |
| 2 | 6 | doc-gap | README.md:28 | Codex CLI: "`~> 0.4` excludes v0.5.0" | **discarded — factually wrong**: `~> 0.4` ⇒ `>= 0.4.0 and < 1.0.0`, which includes 0.5.0 |

## 4-reasoner corroboration on finding 1

- **Codex GH bot (P2, retry.ex:64):** healed invalid tests remain in `tests` with `--all` → contradictory green result
- **Copilot (retry.ex:142):** `summary.invalid` only cleared when whole result is green → stale count on partial heal
- **Codex CLI (audit dispatch):** independently re-flagged the `--all` scenario at priority 8
- **Claude:** verified all three against HEAD + ExUnit 1.18.4 source (failures_manifest.ex records `:invalid` like `:failed`, so `--failed` re-runs invalid tests); also identified the third gap — invalid→failed in run 2 was silently hidden in default (failures-only) output, violating never-hide-failures

## Auto-applied fixes

- lib/ex_unit_json/retry.ex: run-1 invalid entries now resolve against run-2 state (healed → run-2 passing entry; re-failed → confirmed failure with run-2 detail; unresolved → stays invalid). Run-2 failures invisible to failures-only run-1 arrays are surfaced into `tests`. `summary.invalid`/`summary.passed` recomputed; `result` requires zero confirmed AND zero invalid. `retry.retried` now counts invalid tests too.
- test/ex_unit_json/retry_test.exs: 7 new tests covering --all heal, invalid→failed, failures-only surfacing, partial heal (Copilot's scenario), recurring setup_all, retried count
- Docs: moduledoc (ExUnitJSON + Mix.Tasks.Test.Json), README, CHANGELOG [Unreleased] all document the new invalid-resolution behavior

## PR / acceptance criteria

PR #2 stated criteria (confirmed/flaky classification, opt-outs, retry metadata, tests, quality gates):
all met by the merged code. The invalid-test edge case was flagged by bots post-merge and is fixed by
this audit. No unmet criteria → no rmap follow-ups.

## Bot-finding triage

Both single-bot findings were corroborated (bot + Codex CLI + Claude ≥ 2 reasoners) → auto-applied.
No uncorroborated bot bugs → no rmap follow-ups filed.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1
Codex-only findings (discarded as over-flag): 2 (version-requirement semantics error)
