---
title: "Wire queue add/skip/auto-advance between client and server"
date: 2026-02-14
category: integration-issues
module: sync, queue, playback
tags: [websocket, queue, skip, auto-advance, stateSync, track, codable, swiftui, fly-io]
symptoms:
  - "'+' button in QueueView plays track immediately instead of adding to queue"
  - "Skip button is demo-only, does not send message to server"
  - "Queue updates from server are silently dropped"
  - "Progress bar starts at random position"
  - "Track ending does not advance to next queued track"
severity: feature-gap
---

# Wire queue add/skip/auto-advance between client and server

## Problem

Server had working `addToQueue`, `removeFromQueue`, and `skip` handlers. Client had the UI (QueueView search, queue list, vote controls) and models (`Session.queue: [Track]`). But nothing was wired:

- The "+" button called `play()` directly instead of `addToQueue()`
- `skipToNext()` was a synchronous demo-only method that mutated local state
- `.queueUpdated` case in `handleUpdate()` was `break` (no-op)
- `queueUpdate` and `stateSync` decoded queue as `[String]` (track IDs only), losing all track metadata
- `TrackProgressBar` initialized with `Double.random(in: 30_000...90_000)` and looped back to zero
- No track-end detection — songs ended silently with no auto-advance

## Root Cause

The protocol layer (`SessionTransport.swift`) defined `queueUpdate([String])` and `SessionSnapshot.queue: [String]`, but the server sends full track objects in both `queueUpdate` and `stateSync` payloads. The client stripped everything except the `id` field, making it impossible to display queue entries. Additionally, no client code existed to encode `addToQueue` messages or route skip commands through the SyncEngine.

## Solution

### 1. Protocol type changes (`SessionTransport.swift`)

Changed queue types from `[String]` to `[Track]` throughout:

```swift
// SyncMessageType
case addToQueue(track: Track, nonce: String)  // NEW
case queueUpdate([Track])                     // was [String]

// SessionSnapshot
let queue: [Track]                            // was [String]
```

### 2. SyncEngine queue/skip methods (`SyncEngine.swift`)

Added two new methods for client → server communication:

```swift
func sendAddToQueue(track: Track) async {
    let nonce = UUID().uuidString
    let msg = SyncMessage(
        id: UUID(),
        type: .addToQueue(track: track, nonce: nonce),
        sequenceNumber: 0, epoch: currentEpoch, timestamp: clock.now()
    )
    try? await transport.send(msg)
}

func sendSkip() async {
    let msg = SyncMessage(
        id: UUID(),
        type: .skip,
        sequenceNumber: 0, epoch: currentEpoch, timestamp: clock.now()
    )
    try? await transport.send(msg)
}
```

Updated `SessionUpdate.queueUpdated` from `[String]` to `[Track]`.

### 3. WebSocketTransport encode/decode (`WebSocketTransport.swift`)

**Encode** `addToQueue` with full track data + nonce:

```swift
case .addToQueue(let track, let nonce):
    result["type"] = "addToQueue"
    result["data"] = [
        "track": ["id": track.id, "name": track.name, ...],
        "nonce": nonce,
    ]
```

**Decode** queue as full Track objects using a shared helper:

```swift
private static func decodeTrackArray(_ value: JSONValue?) -> [Track] {
    guard let arr = value?.arrayValue else { return [] }
    return arr.compactMap { item -> Track? in
        guard let dict = jsonValueToAny(item) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(Track.self, from: data)
    }
}
```

This reuses the existing `jsonValueToAny` → `JSONDecoder` pattern from `translateStateSync`'s `currentTrack` parsing (see [websocket-protocol-mismatch-silent-message-drop.md](websocket-protocol-mismatch-silent-message-drop.md)).

### 4. SessionStore wiring (`SessionStore.swift`)

- `addToQueue(track:)` — if nothing playing, starts playback; otherwise sends to server
- `skipToNext()` — now `async`, DJ-only, sends skip via SyncEngine
- Old sync `skipToNext()` renamed to `demoSkipToNext()` for demo mode
- `.queueUpdated(let tracks)` handler now applies tracks to `session?.queue`
- `handleStateSync()` detects DJ track changes and triggers `play()`:

```swift
let previousTrackID = session?.currentTrack?.id
// ... apply snapshot ...
if isDJ, snapshot.playbackRate > 0,
   let track = snapshot.currentTrack,
   track.id != previousTrackID {
    Task { await play(track: track) }
}
```

- Also syncs `session?.queue = snapshot.queue` from stateSync

### 5. Server skip handler (`server/index.js`)

Changed skip from broadcasting `playPrepare` to broadcasting `stateSync`:

```javascript
case "skip":
    // Was: broadcastToSession(session, { type: "playPrepare", ... })
    // Now: broadcastToSession(session, { type: "stateSync", data: sessionSnapshot(session), ... })
```

This reuses the existing stateSync handling on all clients. The DJ receives it, sees a new `currentTrack`, and calls `play()` which runs the two-phase PREPARE/COMMIT flow. Sequence resets to 0 with the new epoch.

### 6. Auto-advance (`SpotifyPlayer.swift`)

Added `onTrackEnded` callback that fires when Spotify reports paused near duration end:

```swift
if playerState.isPaused,
   playerState.playbackPosition >= Int(playerState.track.duration) - 1000 {
    onTrackEnded?()
}
```

Wired in `SessionStore.connectToSession()` to call `skipToNext()`.

### 7. UI changes

- **QueueView "+"**: calls `addToQueue()` instead of `play()`, doesn't dismiss sheet
- **NowPlayingView skip**: async, disabled when queue empty
- **TrackProgressBar**: accepts `initialPositionMs` parameter (default 0), removed random init and loop-to-zero

## Key Pattern: stateSync as Skip Broadcast

The skip flow uses stateSync rather than playPrepare because:
1. All clients already handle stateSync (queue, members, track, position)
2. The DJ client detects the track change and initiates the two-phase play
3. Non-DJ clients get the new track info + updated queue in one message
4. Epoch increments, sequence resets — clean state boundary

## Prevention

- When adding new message types, update all three layers: protocol enum → SyncEngine switch → WebSocketTransport encode/decode
- Always decode server queue payloads as full Track objects, not just IDs — the server sends complete track data
- Test round-trip encoding by checking `queueUpdate` and `stateSync` tests pass with `[Track]`

## Related

- [websocket-protocol-mismatch-silent-message-drop.md](websocket-protocol-mismatch-silent-message-drop.md) — Anti-Corruption Layer pattern for server ↔ client translation
- [sptappremote-wake-spotify-before-play.md](sptappremote-wake-spotify-before-play.md) — ensure Spotify app is connected before play commands
- [ntp-anchored-visual-sync.md](../architecture-patterns/ntp-anchored-visual-sync.md) — derive position from NTP anchor (future: pass real position to TrackProgressBar)
