---
status: pending
priority: p1
issue_id: "001"
tags: [code-review, architecture, correctness, swift]
dependencies: []
---

# Fix listener play() silent failure — optimistic state never reconciles

## Problem Statement

When a non-DJ listener joins a station with an empty queue and adds a track, `SessionStore.addToQueue` (line 308) calls `play(track:)` instead of sending the track to the queue. The `play()` method checks `isDJ || session?.members.isEmpty`, and when the user isn't the DJ, it sets optimistic local state (`session?.currentTrack = track`, `session?.isPlaying = true`) but the server rejects the `playPrepare` message (requires isDJ). The user sees a "playing" state with no actual playback.

## Findings

- `SessionStore.addToQueue` at line 308-311: when `currentTrack == nil`, it calls `play(track:)` instead of `sendAddToQueue`
- `play()` at line 254-258 sets optimistic state before server confirmation
- Server `playPrepare` handler requires `isDJ` — silently drops the message for non-DJs
- User gets stuck in a fake "playing" state that never reconciles

## Proposed Solutions

### Option 1: Always send addToQueue, let server handle first-track logic

**Approach:** When `currentTrack == nil` and user is not DJ, send `addToQueue` to server. Server's autonomous playback logic picks up the first track and starts playing.

**Pros:**
- Simple fix — one conditional change
- Server is already authoritative for autonomous playback

**Cons:**
- Slight delay before playback starts (server round-trip)

**Effort:** 15 minutes
**Risk:** Low

### Option 2: Guard play() on isDJ check

**Approach:** Add `guard isDJ` to the `currentTrack == nil` path. If not DJ, fall through to normal `sendAddToQueue`.

**Pros:**
- Explicit guard, easy to understand

**Cons:**
- Same as Option 1 essentially

**Effort:** 15 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `PirateRadio/Core/Sync/SessionStore.swift:308-311` — the `addToQueue` method

## Acceptance Criteria

- [ ] Non-DJ listener adding track to empty station sends addToQueue (not play)
- [ ] Server autonomous playback picks up the first track
- [ ] No optimistic state set for non-DJ play attempts
- [ ] Build succeeds

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Architecture Strategist agent

**Actions:**
- Traced the addToQueue → play() → server rejection flow
- Identified optimistic state that never reconciles
- Confirmed server requires isDJ for playPrepare
