---
status: pending
priority: p3
issue_id: "009"
tags: [code-review, performance, swift, ui]
dependencies: []
---

# Cache effectiveDetents in FrequencyDial to reduce allocations during drag

## Problem Statement

`FrequencyDial.effectiveDetents` recomputes `stations.map(\.dialValue)` on every access — called 20x per body evaluation (tick marks) and 60+ times/sec during drag gestures, allocating new arrays each time.

## Proposed Solutions

### Option 1: Compute once as local let in body

**Approach:** `let resolvedDetents = stations.isEmpty ? detents : stations.map(\.dialValue)` at top of body, pass to checkDetentSnap.

**Effort:** 10 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `PirateRadio/UI/Components/FrequencyDial.swift:29-32`

## Acceptance Criteria

- [ ] effectiveDetents computed once per body evaluation
- [ ] Passed as parameter to checkDetentSnap
- [ ] Build succeeds

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Performance Oracle agent
