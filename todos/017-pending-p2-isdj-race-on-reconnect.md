---
status: pending
priority: p2
issue_id: "017"
tags: [code-review, architecture, client]
dependencies: []
---

# Fix isDJ Race When Owner Reconnects to Idle Station

## Problem Statement

When a station owner reconnects to their own idle station, `djUserID` is `nil` until `stateSync` arrives from the server. During this window, `isDJ` returns `false` and the owner cannot play, skip, or add-to-queue-and-auto-play.

## Findings

- `isDJ` at line 257: `return session.djUserID == userID` — false when `djUserID` is nil
- `play()` guard: `isDJ || (session?.members.isEmpty == true)` — members is NOT empty (owner added in joinSessionById)
- Window lasts from `connectToSession` completion until first `stateSync` arrives

**Source:** Architecture Strategist agent

## Proposed Solutions

### Option A: Extend isDJ to check isCreator as fallback
```swift
var isDJ: Bool {
    guard let session, let userID = authManager.userID else { return false }
    return session.djUserID == userID || (isCreator && session.djUserID == nil)
}
```
- Effort: Trivial
- Risk: Low

### Option B: Set djUserID eagerly in joinSessionById when isCreator
- Effort: Trivial
- Risk: May conflict with server's stateSync

## Acceptance Criteria

- [ ] Owner can play a track immediately after tuning to their own idle station

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-07 | Created from code review | Found by architecture-strategist agent |
