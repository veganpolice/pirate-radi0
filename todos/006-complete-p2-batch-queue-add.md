---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, performance, swift]
dependencies: []
---

# Replace sequential addToQueue loop with batch API call

## Problem Statement

`PlaylistBrowser.playPlaylist` (NowPlayingView.swift lines 521-524) adds tracks sequentially with individual `await sessionStore.addToQueue(track:)` calls. For a 50-track playlist, this means 50 sequential network round-trips taking 10-30 seconds.

## Findings

- Sequential `for track in tracks[1...] { await sessionStore.addToQueue(track:) }` loop
- Server already has `batchAddToQueue` endpoint
- Client has `sendBatchAddToQueue` method
- The commit message `f645b03` mentions "fix playlist queue batch add" — may already be partially addressed

## Proposed Solutions

### Option 1: Use existing batchAddToQueue

**Approach:** Replace the sequential loop with a single `sessionStore.batchAddToQueue(tracks: Array(tracks[1...]))` call.

**Effort:** 15 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `PirateRadio/UI/NowPlaying/NowPlayingView.swift:521-524`

## Acceptance Criteria

- [ ] Playlist tracks added via single batch call
- [ ] Server receives and processes batch correctly
- [ ] Build succeeds

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Performance Oracle agent
