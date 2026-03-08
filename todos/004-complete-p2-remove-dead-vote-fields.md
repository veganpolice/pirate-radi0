---
status: pending
priority: p2
issue_id: "004"
tags: [code-review, simplicity, dead-code, swift]
dependencies: []
---

# Remove dead vote/stats fields from Track and Session.Member

## Problem Statement

Vote fields on `Track` (`votes`, `isUpvotedByMe`, `isDownvotedByMe`) and stats fields on `Session.Member` (`votesCast`, `djTimeMinutes`) have no consumers after collaborative mode removal. `MemberProfileCard` still displays always-zero "Votes" and "DJ Time" stats — misleading to users.

## Findings

- `Track.swift` lines 10, 12-13: `votes`, `isUpvotedByMe`, `isDownvotedByMe` — no UI reads/writes
- `Session.Member` lines 19-21: `tracksAdded`, `votesCast`, `djTimeMinutes` — `votesCast` and `djTimeMinutes` always zero
- `MemberProfileCard.swift` line 68, 70 still displays "Votes" and "DJ Time" using these zero fields
- `SessionStore.toggleVote` (lines 544-574) and `clearCurrentTrack` (lines 599-601) — zero callers

## Proposed Solutions

### Option 1: Remove all dead fields and methods

**Approach:** Delete vote fields from Track, dead stats from Session.Member, dead methods from SessionStore, update MemberProfileCard.

**Effort:** 30 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `PirateRadio/Core/Models/Track.swift` — remove 3 vote fields
- `PirateRadio/Core/Models/Session.swift` — remove `votesCast`, `djTimeMinutes`
- `PirateRadio/Core/Sync/SessionStore.swift` — remove `toggleVote`, `clearCurrentTrack`
- `PirateRadio/UI/Components/MemberProfileCard.swift` — remove dead stats display

## Acceptance Criteria

- [ ] Vote fields removed from Track
- [ ] Dead stats removed from Session.Member
- [ ] Dead methods removed from SessionStore
- [ ] MemberProfileCard shows only live data
- [ ] Build succeeds

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Code Simplicity Reviewer + Architecture Strategist agents
