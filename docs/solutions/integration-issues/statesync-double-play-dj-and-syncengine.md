---
title: "stateSync Double-Play: DJ + SyncEngine Both Triggering Playback"
category: integration-issues
tags: [sync, playback, stateSync, double-play, syncengine, sessionstore]
module: sync
symptoms: [audible-glitch, duplicate-prepare-commit, track-plays-twice]
date: 2026-02-28
---

# stateSync Double-Play: DJ + SyncEngine Both Triggering Playback

## Problem

When the server advanced the queue (via timer expiry or skip), the DJ client played the new track **twice** — once via `SyncEngine.handleStateSync()` (the correct, local-only playback path) and once via `SessionStore.handleStateSync()`, which called `play(track:)` -> `djPlay()` -> sent PREPARE+COMMIT back to the server. This caused audible glitches on the DJ device and leaked redundant DJ sync commands to every listener.

## Symptoms

- Audible glitch or restart stutter on the DJ device when the server advances the queue.
- Duplicate `PREPARE` and `COMMIT` messages appearing in WebSocket traffic after a server-initiated track change.
- The same track URI showing up twice in rapid succession in playback logs.
- Listeners occasionally receiving a second sync cycle (PREPARE+COMMIT) moments after the first, causing a brief playback hiccup.

## Root Cause

Two independent code paths both responded to incoming `stateSync` WebSocket messages with playback triggers:

**Path 1 — `SyncEngine.handleStateSync()` (lines ~413-437)**
Compares the incoming track against current state, then calls `musicSource.play()` locally. This path works for ALL clients (DJ and listeners). It calculates playback position from NTP-anchored timestamps and never sends anything back to the server. This is the correct path.

**Path 2 — `SessionStore.handleStateSync()` (lines ~305-308)**
Had an `if isDJ` guard that called `play(track:)` when the synced track differed from the local track. `play(track:)` re-entered `SyncEngine.djPlay()`, which sent PREPARE+COMMIT back to the server — treating a server-originated state change as if the DJ had initiated a new track selection.

```
Server advances queue
  -> stateSync message to DJ client
    -> SyncEngine.handleStateSync()  =>  musicSource.play()  [correct, local]
    -> SessionStore.handleStateSync()
         if isDJ { play(track:) }
           -> SyncEngine.djPlay()
             -> sends PREPARE to server   [incorrect, duplicate]
             -> sends COMMIT to server    [incorrect, duplicate]
             -> musicSource.play()        [second play call]
```

The net result: two `musicSource.play()` calls and a leaked PREPARE+COMMIT round-trip.

## Solution

Remove the DJ playback trigger from `SessionStore.handleStateSync()` entirely. Let `SyncEngine` own ALL playback decisions for every client role.

**In `SessionStore.handleStateSync()`:**

```swift
// BEFORE (broken):
if isDJ, let track = state.currentTrack, track.uri != currentTrack?.uri {
    play(track: track)
}

// AFTER (fixed):
// Playback is handled by SyncEngine.handleStateSync() for ALL clients
// (plays locally via musicSource.play without sending PREPARE+COMMIT back to server).
// No DJ-specific trigger needed here — removes double-play bug when server advances queue.
```

**Spotify wake fix — removed `!isDJ` guard on AppRemote reconnection:**

The existing AppRemote reconnection block (which wakes Spotify when the app returns from background) had a `!isDJ` guard, assuming the DJ would always have Spotify active. In practice the DJ can also return from background with a cold AppRemote. Removing the guard lets the DJ benefit from the same wake logic as listeners.

## Key Insight

In a server-authoritative sync system, there should be exactly **one** playback path per client. If two layers both trigger playback on the same inbound event, you get double-play. `SyncEngine` is the correct owner of playback because it:

1. Calculates seek position from NTP-anchored timestamps.
2. Calls `musicSource.play()` locally with no network side effects.
3. Applies uniformly to every client role (DJ, listener, late-joiner).

`SessionStore` should update **model state** (current track metadata, queue, member list) from `stateSync` but must never initiate playback directly.

## Prevention

- **Single-owner rule:** For any side-effectful action (playback, network writes), designate exactly one component as the owner. Document ownership in a comment at the call site.
- **Grep for duplicate triggers:** When adding a new message handler, search for other handlers of the same message type (`stateSync`, `queueUpdate`, etc.) to verify you are not duplicating side effects.
- **Trace test:** Before merging sync changes, enable verbose WebSocket logging and confirm that a server-initiated queue advance produces exactly one `musicSource.play()` call and zero outbound PREPARE/COMMIT messages on the DJ client.

## Related

- `PirateRadio/Core/Sync/SessionStore.swift` — `handleStateSync()` method
- `PirateRadio/Core/Sync/SyncEngine.swift` — `handleStateSync()` method, `djPlay()` method
- `docs/solutions/integration-issues/websocket-protocol-mismatch-silent-message-drop.md` — related WebSocket sync issue
- `docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md` — AppRemote wake logic that was also adjusted
