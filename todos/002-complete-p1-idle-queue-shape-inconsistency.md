---
status: pending
priority: p1
issue_id: "002"
tags: [code-review, architecture, correctness, server]
dependencies: []
---

# Fix idle station snapshot queue shape inconsistency

## Problem Statement

`idleStationSnapshot` (server/index.js line ~1002) returns the full `tracks` array as `queue`, while `liveSessionSnapshot` returns `getUpcomingQueue(live)` which excludes the current track. When a station transitions from idle to live on first tune-in, the queue suddenly shrinks by one element, potentially causing UI flicker.

## Findings

- `idleStationSnapshot` returns raw `tracks` array as `queue` field
- `liveSessionSnapshot` returns `getUpcomingQueue(live)` which slices out the current track
- Client receives different queue shapes depending on idle vs live state
- Transition from idle → live causes the queue to lose one element (the current track)

## Proposed Solutions

### Option 1: Make idleStationSnapshot return upcoming queue only

**Approach:** In `idleStationSnapshot`, slice the tracks array to exclude the current track (at `snapshotTrackIndex`), matching the `getUpcomingQueue` shape.

**Pros:**
- Consistent queue shape in both states
- Client code doesn't need to handle two formats

**Cons:**
- Minor complexity in snapshot function

**Effort:** 15 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `server/index.js` — `idleStationSnapshot` function (~line 1002)

## Acceptance Criteria

- [ ] Idle station snapshot queue excludes current track (matches live format)
- [ ] Server tests pass
- [ ] No UI flicker on idle → live transition

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Architecture Strategist agent

**Actions:**
- Compared idleStationSnapshot and liveSessionSnapshot queue shapes
- Identified inconsistency in queue contents
