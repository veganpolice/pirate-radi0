---
status: pending
priority: p2
issue_id: "018"
tags: [code-review, cleanup, client]
dependencies: []
---

# Remove Dead invalidJoinCode Error Case

## Problem Statement

`PirateRadioError.invalidJoinCode` is no longer thrown or used anywhere after join codes were removed. The case and its test remain as dead code.

## Findings

- Defined at `PirateRadioError.swift:16`
- Tested at `PirateRadioTests.swift:288`
- Never thrown in any production code path

**Source:** Pattern Recognition Specialist agent

## Acceptance Criteria

- [ ] `.invalidJoinCode` case removed from `PirateRadioError`
- [ ] Test reference removed
- [ ] Project compiles and tests pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-07 | Created from code review | Join codes fully removed in persistent-stations refactor |
