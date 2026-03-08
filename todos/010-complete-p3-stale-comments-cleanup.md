---
status: pending
priority: p3
issue_id: "010"
tags: [code-review, quality, cleanup]
dependencies: []
---

# Clean up stale comments and deliberation artifacts

## Problem Statement

Minor cleanup items: stale doc comment in QueueView, deliberation comments in server computePosition, mock data with out-of-band frequency.

## Findings

- `QueueView.swift:5` — doc comment still mentions "In collab mode: vote buttons and auto-sort by vote count"
- `server/index.js:819-823` — internal deliberation comments ("Actually, the plan says...")
- `MockData.swift:124` — DiscoverySession frequency "110.7 FM" exceeds FM band max of 107.9

## Proposed Solutions

### Option 1: Quick cleanup pass

**Effort:** 10 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `PirateRadio/UI/NowPlaying/QueueView.swift:5`
- `server/index.js:819-823`
- `PirateRadio/Core/Mock/MockData.swift:124`

## Acceptance Criteria

- [ ] Stale comments removed/updated
- [ ] Mock frequency corrected to valid range
- [ ] Build succeeds
