---
status: pending
priority: p2
issue_id: "008"
tags: [code-review, simplicity, dead-code, swift]
dependencies: []
---

# Clean up hotSeat/vote mock remnants

## Problem Statement

MockTimerManager still has `hotSeatRotation` case and `triggerHotSeatRotation` method. PirateRadioApp has a dead `break` handler for it. `startVoteEvents()` fires vote toasts with no backing UI.

## Proposed Solutions

### Option 1: Remove all mock remnants

**Approach:** Remove `hotSeatRotation` enum case, trigger method, dead break handler, and `startVoteEvents()`.

**Effort:** 15 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `PirateRadio/Core/Mock/MockTimerManager.swift` — remove hotSeat case, trigger, startVoteEvents
- `PirateRadio/App/PirateRadioApp.swift:109` — remove dead break handler

## Acceptance Criteria

- [ ] No hotSeat or vote references in mock infrastructure
- [ ] Build succeeds

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Code Simplicity Reviewer + Architecture Strategist agents
