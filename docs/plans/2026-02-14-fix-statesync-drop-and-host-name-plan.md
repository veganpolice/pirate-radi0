---
title: Fix stateSync Dropped by Sequence Guard & Host Name Shows Raw ID
type: fix
date: 2026-02-14
---

# Fix stateSync Dropped by Sequence Guard & Host Name Shows Raw ID

## Overview

Two bugs remain after the WebSocket anti-corruption layer was wired up:

1. **Joiner sees host name as garbled characters** (raw Spotify user ID like `1yarjhamxgjka2k0xcll5qow4`)
2. **Joiner doesn't pick up the track the host is playing**

Both trace to the same root cause: the `stateSync` message is **silently dropped** by `SyncEngine.processMessage()`.

## Problem Statement

### Bug 1: stateSync dropped by sequence guard

The server sends `stateSync` on WebSocket connect:
```json
{ "type": "stateSync", "data": { "epoch": 0, "sequence": 3, "members": [...], "currentTrack": {...}, ... } }
```

Note: **no top-level `seq` or `epoch`** — those fields are nested inside `data`.

`WebSocketTransport.translate()` reads top-level fields:
```swift
let seq = msg.seq ?? 0    // nil → 0
let epoch = msg.epoch ?? 0 // nil → 0
```

So the resulting `SyncMessage` has `sequenceNumber: 0, epoch: 0`.

In `SyncEngine.processMessage()` (line 202):
```swift
guard message.sequenceNumber > lastProcessedSeq else { return }
```

`lastProcessedSeq` starts at 0. `0 > 0` is **false** → stateSync is silently dropped. The joiner never receives the current track, member list, or playback state.

### Bug 2: Host display name baked as raw ID into JWT

`SessionStore.getBackendToken()` (line 281-303) waits for `authManager.userID` but **not** `authManager.displayName`:

```swift
let body = ["spotifyUserId": userID, "displayName": authManager.displayName ?? userID]
//                                                   ^^^ may still be nil
```

If the Spotify profile hasn't finished loading, the raw user ID gets embedded in the JWT. The server then stores this as the host's `displayName` in the member entry. Even the stateSync snapshot carries the wrong name (though it's moot since stateSync is dropped anyway).

## Proposed Solution

### Fix 1: Exempt stateSync from sequence guard

In `SyncEngine.processMessage()`, process `stateSync` messages **before** the sequence validation. State syncs are full snapshots, not sequenced deltas — they should always be applied.

```swift
// SyncEngine.swift, processMessage()

// stateSync is a full snapshot — always process it regardless of sequence
if case .stateSync(let snapshot) = message.type {
    await handleStateSync(snapshot)
    onSessionUpdate?(.stateSynced(snapshot))
    return
}

// Epoch validation: ignore messages from old epochs
if message.epoch < currentEpoch { return }
if message.epoch > currentEpoch {
    currentEpoch = message.epoch
    lastProcessedSeq = 0
}

// Sequence validation: ignore already-processed messages
guard message.sequenceNumber > lastProcessedSeq else { return }
lastProcessedSeq = message.sequenceNumber

switch message.type { ... }
```

**File:** `PirateRadio/Core/Sync/SyncEngine.swift` — lines 190-236

### Fix 2: Wait for displayName before minting JWT

In `SessionStore.getBackendToken()`, also poll for `authManager.displayName`:

```swift
private func getBackendToken() async throws -> String {
    // Wait briefly for profile to load (userID AND displayName)
    if authManager.userID == nil || authManager.displayName == nil {
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(300))
            if authManager.userID != nil && authManager.displayName != nil { break }
        }
    }
    guard let userID = authManager.userID else {
        throw PirateRadioError.notAuthenticated
    }

    // ...
    let body = ["spotifyUserId": userID, "displayName": authManager.displayName ?? userID]
```

**File:** `PirateRadio/Core/Sync/SessionStore.swift` — lines 281-303

### Fix 3 (belt-and-suspenders): Add top-level seq/epoch to server's stateSync

On the server, include `seq` and `epoch` at the top level of the stateSync message so the client's sequence validation would also work:

```javascript
// server/index.js line 234
ws.send(JSON.stringify({
    type: "stateSync",
    data: sessionSnapshot(session),
    epoch: session.epoch,
    seq: session.sequence,
    timestamp: Date.now(),
}));
```

**File:** `server/index.js` — line 234

## Acceptance Criteria

- [x] Joiner receives `stateSync` and processes it (verify with console log)
- [x] Joiner sees host's actual display name (not raw Spotify user ID)
- [x] Joiner picks up the currently playing track when joining mid-song
- [x] Host still sees both members with correct names
- [x] Existing sequenced messages (playCommit, pause, etc.) still deduplicate correctly

## Files to Modify

| File | Change |
|------|--------|
| `PirateRadio/Core/Sync/SyncEngine.swift` | Exempt stateSync from sequence guard |
| `PirateRadio/Core/Sync/SessionStore.swift` | Wait for displayName in getBackendToken() |
| `server/index.js` | Add top-level seq/epoch to stateSync message |

## Risk Analysis

- **Fix 1 is safe**: stateSync always resets `currentEpoch` and `lastProcessedSeq` inside `handleStateSync()`, so subsequent sequenced messages are unaffected.
- **Fix 2 adds up to 3s wait**: Same polling budget already used for `userID`. In practice, `displayName` loads from the same `/v1/me` API call, so it arrives at the same time.
- **Fix 3 is additive**: Adding top-level fields to the server message doesn't break any existing behavior.
