---
title: "feat: Wire queue management, skip, and auto-advance"
type: feat
date: 2026-02-14
---

# feat: Wire queue management, skip, and auto-advance

## Overview

The server already has `addToQueue`, `removeFromQueue`, and `skip` handlers. The client has the UI (QueueView, search, vote controls) and the data models (`Session.queue`, `Track`). But **nothing is wired together** — the "+" button plays immediately instead of enqueuing, skip is demo-only, auto-advance doesn't exist, and queue updates from the server are silently dropped.

This plan connects the existing pieces into a working end-to-end queue and playback lifecycle.

## Problem Statement

Right now the DJ can only play one track at a time by searching and tapping "+". There's no way to:
- Build a queue of upcoming tracks
- Skip to the next song
- Have songs auto-advance when one finishes
- Let crew members add songs to the queue
- See real playback progress

These are table-stakes for a group listening session.

## Proposed Solution

Wire the client to the server's existing queue protocol. Six changes, in priority order:

### Phase 1: Queue Add + Display (crew gets a queue)

**Files:** `SessionStore.swift`, `SyncEngine.swift`, `WebSocketTransport.swift`, `QueueView.swift`

#### 1a. Send `addToQueue` messages from the client

Add `SessionStore.addToQueue(track:)`:
```swift
// SessionStore.swift
func addToQueue(track: Track) async {
    // If nothing is playing, play immediately instead of queuing
    if session?.currentTrack == nil {
        await play(track: track)
        return
    }
    await syncEngine?.sendAddToQueue(track: track)
}
```

Add `SyncEngine.sendAddToQueue(track:)`:
```swift
// SyncEngine.swift
func sendAddToQueue(track: Track) async {
    let nonce = UUID().uuidString
    let msg = SyncMessage(
        id: UUID(),
        type: .addToQueue(track: track, nonce: nonce),
        sequenceNumber: 0,  // queue ops don't need sequencing
        epoch: currentEpoch,
        timestamp: clock.now()
    )
    try? await transport.send(msg)
}
```

Add the wire encoding in `WebSocketTransport.encodeForServer()`:
```swift
case .addToQueue(let track, let nonce):
    result["type"] = "addToQueue"
    result["data"] = [
        "track": [
            "id": track.id, "name": track.name, "artist": track.artist,
            "albumName": track.albumName, "albumArtURL": track.albumArtURL?.absoluteString ?? "",
            "durationMs": track.durationMs
        ],
        "nonce": nonce
    ]
```

Update `SyncMessage.SyncMessageType` to add the new case:
```swift
case addToQueue(track: Track, nonce: String)
```

#### 1b. Receive and display `queueUpdate` messages

Change `SyncMessage.SyncMessageType.queueUpdate` from `[String]` to `[Track]`:
```swift
case queueUpdate([Track])
```

Update `WebSocketTransport.translate()` for the `queueUpdate` case to decode full Track objects from the server JSON (the server already sends full track objects in `data.queue[]`).

Handle in `SessionStore.handleUpdate()` — replace the `break`:
```swift
case .queueUpdated(let tracks):
    session?.queue = tracks
```

#### 1c. Update QueueView "+" button

In `QueueView.swift`, change the non-demo "+" action from `sessionStore.play(track:)` to `sessionStore.addToQueue(track:)`. Remove the `dismiss()` so the user can keep adding tracks.

**Also:** Remove the DJ guard from `addToQueue` — any member can add. The server already allows it.

---

### Phase 2: Skip (DJ advances to next track)

**Files:** `SessionStore.swift`, `SyncEngine.swift`, `WebSocketTransport.swift`, `server/index.js`

#### 2a. Fix the server skip handler

The server's `skip` handler sends `playPrepare` but not `playCommit`. Fix: **don't have the server send play commands at all.** Instead, the server should:
1. Shift `queue[0]` into `currentTrack`
2. Increment epoch
3. Broadcast `stateSync` to all clients (not `playPrepare`)

This is simpler and matches the reconnect flow — every client already handles `stateSync`. The DJ client receives the stateSync, sees a new `currentTrack`, and initiates the two-phase `djPlay()` flow.

```javascript
// server/index.js — revised skip handler
case 'skip': {
    if (senderId !== session.djUserId) break;
    const nextTrack = session.queue.shift();
    if (!nextTrack) break;  // empty queue = no-op
    session.currentTrack = nextTrack;
    session.isPlaying = true;
    session.epoch++;
    session.sequence = 0;
    broadcastToSession(sessionId, sessionSnapshot(session));
    break;
}
```

#### 2b. Client skip method

Replace `SessionStore.skipToNext()` (currently demo-only) with a real implementation:
```swift
// SessionStore.swift
func skipToNext() async {
    guard isDJ else { return }
    guard session?.queue.isEmpty == false else { return }
    await syncEngine?.sendSkip()
}
```

Add `SyncEngine.sendSkip()`:
```swift
func sendSkip() async {
    let msg = SyncMessage(
        id: UUID(),
        type: .skip,
        sequenceNumber: 0,
        epoch: currentEpoch,
        timestamp: clock.now()
    )
    try? await transport.send(msg)
}
```

#### 2c. DJ reacts to stateSync with new track

In `SessionStore.handleStateSync()`, detect when the track changes and trigger playback:
```swift
// After updating session state from snapshot...
if snapshot.playbackRate > 0, let trackID = snapshot.trackID, isDJ {
    let trackChanged = session?.currentTrack?.id != trackID
    if trackChanged, let track = snapshot.currentTrack {
        // New track from skip — play it through SyncEngine
        Task { await play(track: track) }
    }
}
```

This reuses the existing `play()` method which already handles Spotify connection, two-phase play, and sync.

#### 2d. Disable skip button when queue is empty

In `NowPlayingView`, bind the skip button's disabled state:
```swift
Button { Task { await sessionStore.skipToNext() } }
    .disabled(sessionStore.session?.queue.isEmpty != false)
```

---

### Phase 3: Auto-advance (track ends, next plays automatically)

**Files:** `SpotifyPlayer.swift`, `SyncEngine.swift`, `SessionStore.swift`

#### 3a. Detect track completion in SpotifyPlayer

The `SpotifyPlayer` already has `handlePlayerStateChange(_ playerState:)` but it's never wired to detect track end. Add detection:
```swift
// SpotifyPlayer.swift — inside handlePlayerStateChange
if playerState.isPaused,
   playerState.playbackPosition >= playerState.track.duration - 1000 {
    // Track ended naturally
    onTrackEnded?()
}
```

Add `var onTrackEnded: (() -> Void)?` callback on `SpotifyPlayer`.

#### 3b. Wire track-ended to skip

In `SyncEngine`, when creating the `SpotifyPlayer`, set the callback:
```swift
// This is set up by SessionStore when creating the engine
```

Actually — `SpotifyPlayer` is created in `SessionStore.connectToSession()`. Add the wiring there:
```swift
player.onTrackEnded = { [weak self] in
    Task { @MainActor in
        await self?.skipToNext()
    }
}
```

This reuses the skip flow from Phase 2 — the DJ device detects track end and sends a skip, which triggers stateSync for all devices.

#### 3c. Wire SpotifyPlayer state delegate

The `SpotifyPlayer.subscribeToPlayerState()` calls `appRemote.playerAPI?.subscribe(toPlayerState:)` but the callback only logs. Wire it to actually call `handlePlayerStateChange()`:

```swift
// SpotifyPlayer.swift — subscribeToPlayerState()
appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] result, error in
    if let error {
        logger.error("Failed to subscribe: \(error.localizedDescription)")
    } else if let playerState = result as? SPTAppRemotePlayerState {
        self?.handlePlayerStateChange(playerState)
    }
})
```

Also subscribe in `SpotifyPlayer.play()` after successful playback starts, since the subscription may not persist across tracks.

---

### Phase 4: Real progress bar

**Files:** `TrackProgressBar.swift`, `NowPlayingView.swift`, `SessionStore.swift`

#### 4a. Expose current position from SessionStore

Add a computed property that derives position from the NTP anchor:
```swift
// SessionStore.swift
var currentPositionMs: Int {
    // SyncEngine stores the NTP anchor — expose it
    // For now, use a simple approach: track how long we've been playing
    guard let session, session.isPlaying else { return 0 }
    // This will be set by SyncEngine via a new callback
    return _currentPositionMs
}
private var _currentPositionMs: Int = 0
```

Or simpler: pass `elapsedMs` from `SyncEngine` via the existing `playbackStateChanged(isPlaying:positionMs:)` callback, and have TrackProgressBar use it as a starting point for its local timer.

#### 4b. Update TrackProgressBar

Remove the random initialization (line 74). Accept an `initialPositionMs` parameter:
```swift
TrackProgressBar(durationMs: track.durationMs, initialPositionMs: currentPositionMs, isPlaying: isPlaying, isDJ: isDJ)
```

The local timer continues ticking from `initialPositionMs` and resets when a new track starts.

---

### Phase 5: stateSync queue hydration

**Files:** `WebSocketTransport.swift`

In `translateStateSync()`, decode the queue as full Track objects instead of just IDs:
```swift
var queueTracks: [Track] = []
if let queueArray = d["queue"]?.arrayValue {
    for item in queueArray {
        if let trackData = try? JSONSerialization.data(withJSONObject: jsonValueToAny(item) ?? [:]) {
            if let track = try? JSONDecoder().decode(Track.self, from: trackData) {
                queueTracks.append(track)
            }
        }
    }
}
```

Change `SessionSnapshot.queue` from `[String]` to `[Track]`.

Update `SessionStore.handleStateSync()` to use the full Track array:
```swift
session?.queue = snapshot.queue
```

---

## Technical Considerations

- **Wire format gotcha:** Server sends `trackId` (camelCase), client Track model uses `id`. The `WebSocketTransport` Anti-Corruption Layer already handles this pattern — follow the same approach for queue messages. Always log decode failures with raw payload.
- **SPTAppRemote must be connected** before any play/skip. The `ensureSpotifyConnected()` pattern (wake + poll for 10s) must wrap all playback-initiating paths.
- **Sequence numbers:** Queue operations (`addToQueue`, `skip`) use seq 0 since they're fire-and-forget to the server. The server's response (`stateSync` or `queueUpdate`) carries the authoritative state.
- **NTP anchor for progress:** Compute position from `NTPAnchoredPosition.positionAt(ntpTime:)` — this is consistent across devices and already synced.

## Acceptance Criteria

- [ ] DJ can search and add tracks to queue (track appears in queue list for all members)
- [ ] Crew members can search and add tracks to queue
- [ ] Queue updates from server are displayed in real-time for all devices
- [ ] DJ can tap skip to advance to the next queued track
- [ ] All crew members hear the new track after skip (via sync)
- [ ] Skip button is disabled when queue is empty
- [ ] When a track finishes, the next track plays automatically
- [ ] Progress bar shows real playback position, not a random fake
- [ ] Queue state survives reconnection (stateSync includes full queue)
- [ ] First track added when nothing is playing starts immediately

## Dependencies & Risks

- **Server change required:** The skip handler needs to broadcast `stateSync` instead of `playPrepare`. This is a ~10 line change in `server/index.js`.
- **Type change:** `SyncMessage.SyncMessageType.queueUpdate` changes from `[String]` to `[Track]`. Update all switch cases.
- **`SessionSnapshot.queue` type change** from `[String]` to `[Track]`. Update `translateStateSync` and any consumers.
- **SpotifyPlayer delegate wiring** is a known gap (callbacks exist but aren't connected). This is required for auto-advance but can be deferred if Phase 3 is too risky.
- **Track.Codable conformance** must handle the server's JSON shape (e.g., `albumArtURL` as string, missing vote fields). May need custom `init(from decoder:)` or a separate server DTO.

## Deferred (Not in This Plan)

- **Voting:** Server has no vote concept. Keep votes client-only for now.
- **Hot Seat rotation:** Needs DJ rotation logic on skip/auto-advance. Separate feature.
- **Collaborative sort-by-votes on server:** Server `skip` does `queue.shift()` regardless of votes. A server-side sort requires vote tracking.
- **Remove from queue:** Server handler exists but not prioritized for v1 flow.
- **NowPlayingBridge next/previous:** Lock screen controls for skip. Wire after skip works.
- **Duplicate track prevention:** Nice-to-have, not blocking.

## References

### Key Files
- `PirateRadio/Core/Sync/SessionStore.swift` — main orchestrator, add `addToQueue()`, update `skipToNext()`
- `PirateRadio/Core/Sync/SyncEngine.swift` — add `sendAddToQueue()`, `sendSkip()`
- `PirateRadio/Core/Networking/WebSocketTransport.swift` — encode new message types, decode full Track in queueUpdate
- `PirateRadio/Core/Spotify/SpotifyPlayer.swift` — wire player state delegate, add track-end detection
- `PirateRadio/UI/NowPlaying/QueueView.swift:175` — change "+" from `play()` to `addToQueue()`
- `PirateRadio/UI/NowPlaying/NowPlayingView.swift:348` — wire skip button
- `PirateRadio/UI/Components/TrackProgressBar.swift:74` — remove random position
- `PirateRadio/Core/Protocols/SessionTransport.swift:31` — update `queueUpdate` type
- `server/index.js:408` — fix skip handler

### Institutional Learnings
- `docs/solutions/integration-issues/websocket-protocol-mismatch-silent-message-drop.md` — Anti-Corruption Layer pattern for wire format
- `docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md` — always check AppRemote before play
- `docs/solutions/integration-issues/spotify-token-refresh-in-profile-fetch.md` — use `getAccessToken()` not raw token
- `docs/solutions/architecture-patterns/ntp-anchored-visual-sync.md` — derive position from NTP anchor
