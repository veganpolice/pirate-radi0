---
title: "fix: Spotify playback control reassertion"
type: fix
date: 2026-03-04
---

# fix: Spotify Playback Control Reassertion

## Overview

When the user switches to Spotify and back, Pirate Radio loses control of playback. Spotify keeps playing whatever it was playing instead of the station's track. The playback controls (skip, queue, restart) exist but don't work reliably because SPTAppRemote connection drops during app switching and is never properly re-established.

Root cause: `SPTAppRemotePlayerStateDelegate` is never wired, and there is no reconnection or mismatch detection logic.

## Problem Statement

Three interlocking bugs:

1. **No player state delegate** -- `SpotifyPlayer` has `handlePlayerStateChange()` but nobody conforms to `SPTAppRemotePlayerStateDelegate` and `appRemote.playerAPI?.delegate` is never set. The app is deaf to what Spotify is actually doing.

2. **No reconnection re-subscription** -- `subscribeToPlayerState()` runs once in `init()` with a 1-second sleep. When AppRemote disconnects (background) and reconnects (foreground), the subscription is lost. All state callbacks stop.

3. **No playback reassertion** -- When the user returns from Spotify, even if AppRemote reconnects, there is no code to check what Spotify is playing vs. what the station expects, and no code to force Spotify back to the correct track.

## Technical Approach

### Phase 1: Wire SPTAppRemotePlayerStateDelegate

The foundation -- without this, nothing else works.

**Problem:** `SpotifyPlayer` is a Swift `actor` and cannot directly conform to an ObjC protocol that calls from arbitrary threads.

**Solution:** Create a lightweight bridge class.

```swift
// SpotifyPlayer.swift — new inner class
final class PlayerStateBridge: NSObject, SPTAppRemotePlayerStateDelegate {
    private let player: SpotifyPlayer

    init(player: SpotifyPlayer) {
        self.player = player
    }

    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        Task { await player.handlePlayerStateChange(playerState) }
    }
}
```

**Wire it on every AppRemote connection:**

```swift
// SpotifyAuth.swift — appRemoteDidEstablishConnection
func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
    Task { @MainActor in
        isConnectedToSpotifyApp = true
        onAppRemoteConnected?()  // NEW callback
    }
}
```

```swift
// SessionStore.swift — in connectToSession(), after creating SpotifyPlayer
authManager.onAppRemoteConnected = { [weak self] in
    Task { await self?.handleAppRemoteReconnected() }
}
```

```swift
// SessionStore.swift — new method
func handleAppRemoteReconnected() async {
    guard let player = syncEngine?.musicSource as? SpotifyPlayer else { return }
    let bridge = player.stateBridge  // stored on SpotifyPlayer
    authManager.appRemote.playerAPI?.delegate = bridge
    authManager.appRemote.playerAPI?.subscribe(toPlayerState: { _, error in
        if let error { logger.error("playerState subscribe failed: \(error)") }
    })
    // Phase 2 adds mismatch check here
}
```

**Remove the sleep-and-subscribe** from `SpotifyPlayer.init()`. Subscription now happens reactively on every connection, not speculatively on init.

**Tasks:**
- [x] Create `PlayerStateBridge` (NSObject, SPTAppRemotePlayerStateDelegate) in `SpotifyPlayer.swift`
- [x] Store bridge as `nonisolated(unsafe) let stateBridge: PlayerStateBridge` on SpotifyPlayer
- [x] Add `onAppRemoteConnected: (() -> Void)?` callback on `SpotifyAuthManager` (`SpotifyAuth.swift`)
- [x] Fire `onAppRemoteConnected` from `appRemoteDidEstablishConnection` delegate method
- [x] Wire callback in `SessionStore.connectToSession()` to call `handleAppRemoteReconnected()`
- [x] In `handleAppRemoteReconnected()`: set `playerAPI?.delegate`, subscribe to playerState
- [x] Remove `subscribeToPlayerState()` from `SpotifyPlayer.init()` (no more sleep-and-hope)
- [x] Verify `handlePlayerStateChange` logs received state (track URI, isPaused, position)

**Success criteria:** After connecting to a station and playing a track, `handlePlayerStateChange` fires on every Spotify state change. After backgrounding and returning, callbacks resume.

---

### Phase 2: Detect Track Mismatch and Reassert Control

Now that we receive `playerStateDidChange`, use it to detect when Spotify deviates from the station's track.

**Mismatch detection in SpotifyPlayer:**

```swift
// SpotifyPlayer.swift — enhanced handlePlayerStateChange
func handlePlayerStateChange(_ playerState: SPTAppRemotePlayerState) {
    let spotifyTrackURI = playerState.track.uri  // "spotify:track:ABC123"
    let spotifyTrackID = spotifyTrackURI.replacingOccurrences(of: "spotify:track:", with: "")

    // Update internal state
    self.lastKnownTrackID = spotifyTrackID
    self.lastKnownIsPaused = playerState.isPaused

    // Existing: track-end detection for onTrackEnded
    // ...existing code...

    // NEW: mismatch detection
    if let expectedTrackID = self.expectedTrackID,
       spotifyTrackID != expectedTrackID,
       !playerState.isPaused {
        // Debounce: ignore during track transitions
        let timeSinceLastPlay = ContinuousClock.now - lastPlayCommandTime
        if timeSinceLastPlay > .seconds(3) {
            onTrackMismatch?()
        }
    }
}
```

**Set expectedTrackID when SyncEngine plays:**

```swift
// SpotifyPlayer.swift — in beginPlayback()
self.expectedTrackID = trackID
self.lastPlayCommandTime = ContinuousClock.now
```

**Reassertion in SessionStore:**

```swift
// SessionStore.swift — wire mismatch handler in connectToSession()
player.onTrackMismatch = { [weak self] in
    Task { @MainActor in
        await self?.reassertPlayback()
    }
}

// SessionStore.swift — new method
func reassertPlayback() async {
    guard let session, session.isPlaying,
          let track = session.currentTrack else { return }
    logger.info("Track mismatch detected — reasserting station playback")
    // Use existing catch-up mechanism
    await syncEngine?.retryCatchUpPlayback()
}
```

**On foreground reconnect — also reassert:**

```swift
// SessionStore.swift — in handleAppRemoteReconnected() (add after subscribe)
await reassertPlayback()
```

This handles both scenarios:
- User played something in Spotify then returned -> mismatch detection -> reassert
- User just backgrounded and returned without touching Spotify -> foreground reassert confirms correct track

**Tasks:**
- [x] Add `expectedTrackID: String?` and `lastPlayCommandTime` to SpotifyPlayer
- [x] Set `expectedTrackID` in `beginPlayback()` and clear in `stop()`
- [x] Add `onTrackMismatch: (() -> Void)?` callback on SpotifyPlayer
- [x] In `handlePlayerStateChange`: compare Spotify's track URI vs `expectedTrackID`, debounce 3s
- [x] Wire `onTrackMismatch` in `SessionStore.connectToSession()`
- [x] Add `reassertPlayback()` to SessionStore — calls `syncEngine?.retryCatchUpPlayback()`
- [x] Call `reassertPlayback()` at end of `handleAppRemoteReconnected()`
- [x] Add toast: "Tuning back to [station name]..." when reassertion occurs
- [ ] Test: play track -> switch to Spotify -> play different song -> return -> station track reasserted

**Success criteria:** When the user switches to Spotify, plays something else, and returns, Pirate Radio forces Spotify back to the station's current track at the correct position within 3 seconds.

---

### Phase 3: Fix Double-Advance Race Condition

Wiring `playerStateDidChange` properly will make `onTrackEnded` actually fire for the first time. This creates a race: both the server timer and the client can trigger track advancement.

**Solution:** Remove client-side `onTrackEnded` -> `skipToNext()`. The server is authoritative for queue advancement via `advancementTimer`. The client should never initiate skips based on Spotify state — only on explicit user action (skip button tap).

```swift
// SessionStore.swift — in connectToSession(), REMOVE this:
// player.onTrackEnded = { [weak self] in
//     Task { @MainActor in await self?.skipToNext() }
// }
```

The server timer already handles auto-advance. When it fires:
1. Server advances queue, broadcasts `stateSync`
2. Client receives `stateSync` -> `SyncEngine.handleStateSync()` plays new track
3. `expectedTrackID` updates -> mismatch detection stays quiet

**Tasks:**
- [x] Remove `onTrackEnded` -> `skipToNext()` wiring from `SessionStore.connectToSession()`
- [x] Keep `onTrackEnded` callback on SpotifyPlayer for potential future use (just don't wire it)
- [ ] Verify: track ends naturally -> server timer fires -> stateSync -> new track plays -> no double-skip

**Success criteria:** When a track ends, exactly one queue advancement occurs (server-initiated), and the next track plays on all clients.

---

## Acceptance Criteria

- [ ] `playerStateDidChange` callbacks fire reliably during playback
- [ ] After backgrounding and returning, `playerStateDidChange` callbacks resume (re-subscription)
- [ ] Switching to Spotify, playing a different song, and returning -> Pirate Radio forces the station's track
- [ ] Skip button works: tapping it advances to the next queued track on all devices
- [ ] Restart (seek to 0) works: tapping it restarts the current track
- [ ] Pause/resume works after returning from background
- [ ] No double-skip when tracks end naturally (server-only advancement)
- [ ] Toast shows "Tuning back to [station name]..." on reassertion
- [ ] Controls work even after multiple background/foreground cycles

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `playerAPI` object changes across reconnects | Medium | High | Re-set delegate and re-subscribe on every `appRemoteDidEstablishConnection` |
| Mismatch false positive during track transitions | High | Medium | 3-second debounce after any play command |
| Force-play jarring if user intentionally paused | Medium | Low | Only reassert when station `isPlaying == true` |
| Spotify Premium required for force-play | Low | Medium | Reuse existing Premium guard + toast |
| Rapid background/foreground toggles | Low | Low | `onAppRemoteConnected` callback is idempotent — re-subscribing is harmless |

## Files to Modify

| File | Change |
|------|--------|
| `PirateRadio/Core/Spotify/SpotifyPlayer.swift` | Add `PlayerStateBridge`, `expectedTrackID`, `onTrackMismatch`, remove init-time subscribe |
| `PirateRadio/Core/Spotify/SpotifyAuth.swift` | Add `onAppRemoteConnected` callback, fire from delegate |
| `PirateRadio/Core/Sync/SessionStore.swift` | Wire `onAppRemoteConnected`, `onTrackMismatch`, add `handleAppRemoteReconnected()`, `reassertPlayback()`, remove `onTrackEnded` skip wiring |
| `PirateRadio/App/PirateRadioApp.swift` | No change needed — existing scenePhase handler calls `connectAppRemote()` which triggers the callback chain |

## References

### Internal References
- SpotifyPlayer state machine: `PirateRadio/Core/Spotify/SpotifyPlayer.swift`
- SpotifyAuth AppRemote lifecycle: `PirateRadio/Core/Spotify/SpotifyAuth.swift`
- SessionStore playback orchestration: `PirateRadio/Core/Sync/SessionStore.swift`
- SyncEngine catch-up playback: `PirateRadio/Core/Sync/SyncEngine.swift` (retryCatchUpPlayback)
- Scene phase handler: `PirateRadio/App/PirateRadioApp.swift`

### Institutional Learnings
- SPTAppRemote wake pattern: `docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md`
- Observable + ObjC delegate bridging: `docs/solutions/integration-issues/sptappremote-observable-integration.md`
- Double-play prevention (single-owner rule): `docs/solutions/integration-issues/statesync-double-play-dj-and-syncengine.md`
- Token refresh for API calls: `docs/solutions/integration-issues/spotify-token-refresh-in-profile-fetch.md`

### Spotify SDK
- SPTAppRemotePlayerStateDelegate: `playerStateDidChange(_ playerState:)` fires on every playback state change
- Must set `appRemote.playerAPI?.delegate` AND call `subscribe(toPlayerState:)` on every connection
- Delegate called from arbitrary threads — bridge to MainActor with `nonisolated` + `Task`
