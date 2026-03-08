---
title: "Fix 'Session Not Found' Error and Simulator Testing Strategy"
type: fix
date: 2026-03-07
---

# Fix "Session Not Found" Error and Simulator Testing Strategy

## Overview

When tuning to a station, users see "Session not found. Check the code and try again." — even when the real problem is a network timeout, expired token, full station, or WebSocket failure. A catch-all in `joinSessionById` maps every error to `.sessionNotFound`. This plan fixes the error discrimination, updates stale copy, and introduces a mock boundary so the full tune-to-station flow can be tested on the iPhone simulator (where Spotify SDK is unavailable).

## Problem Statement

**Root cause:** `SessionStore.joinSessionById()` (line 238) wraps three distinct operations in a single `do/catch` that maps every thrown error to `.sessionNotFound`:

```swift
} catch {
    self.error = .sessionNotFound  // ← catch-all: network, auth, decode, full, timeout
}
```

**Compounding issues:**
1. `joinSessionByIdOnBackend()` (line 527-529) maps all non-200 HTTP statuses to `.sessionNotFound` — including 400 (bad request), 401 (expired token), and 409 (station full)
2. The `.sessionNotFound` error message says "Check the code" — referencing a removed join-by-code flow
3. WebSocket `.failed` states from reconnection exhaustion also surface as `.sessionNotFound`
4. No mock boundary exists for Spotify, so the tune-in flow cannot be tested on the simulator at all

## Proposed Solution

### Part A: Fix Error Discrimination

**A1. Differentiate HTTP responses in `joinSessionByIdOnBackend`**

`SessionStore.swift` lines 526-529 — replace the blanket non-200 check:

```swift
// Before
guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
    throw PirateRadioError.sessionNotFound
}

// After
guard let httpResponse = response as? HTTPURLResponse else {
    throw PirateRadioError.sessionNotFound
}
switch httpResponse.statusCode {
case 200: break
case 401: throw PirateRadioError.tokenExpired
case 404: throw PirateRadioError.sessionNotFound
case 409: throw PirateRadioError.sessionFull
default:
    print("[SessionStore] join-by-id unexpected status: \(httpResponse.statusCode)")
    throw PirateRadioError.notConnected  // don't repeat the lie — unknown status ≠ "not found"
}
```

**A2. Replace catch-all in `joinSessionById`**

`SessionStore.swift` lines 238-239 — preserve typed errors, handle cancellation silently, add fallback:

```swift
// Before
} catch {
    self.error = .sessionNotFound
}

// After
} catch is CancellationError {
    // Rapid station switching — silently discard cancelled tune attempts
    return
} catch let pirateError as PirateRadioError {
    self.error = pirateError
} catch let urlError as URLError {
    print("[SessionStore] joinSessionById network error: \(urlError)")
    self.error = .notConnected
} catch {
    print("[SessionStore] joinSessionById unexpected error: \(error)")
    self.error = .sessionNotFound
}
```

**A3. Update stale error copy**

`PirateRadioError.swift` line 45:

```swift
// Before
case .sessionNotFound:
    return "Session not found. Check the code and try again."

// After
case .sessionNotFound:
    return "Station not found. It may no longer be available."
```

### Part B: Simulator Mock

The goal: test the full tune-to-station flow (dial → HTTP join → WebSocket → stateSync → UI update) on the iPhone simulator, mocking only the Spotify playback boundary.

**Auth on simulator:** `getBackendToken()` calls `POST /auth` with `{spotifyUserId, displayName}` — pure HTTP, no Spotify SDK involvement. The simulator needs `authManager.userID` set, which `enableDemoMode()` already does (`userID = "demo-user-1"`). So auth works on simulator without additional mocking.

**B1. Create `MockMusicSource`**

`SyncEngine` already accepts `any MusicSource`. Create a mock conforming to the **actual** `MusicSource` protocol:

```
PirateRadio/Core/Mock/MockMusicSource.swift
```

```swift
import Foundation

final class MockMusicSource: MusicSource, Sendable {
    func play(trackID: String, at position: Duration) async throws {
        print("[MockMusicSource] play \(trackID) at \(position)")
    }

    func pause() async throws {
        print("[MockMusicSource] pause")
    }

    func seek(to position: Duration) async throws {
        print("[MockMusicSource] seek to \(position)")
    }

    func currentPosition() async throws -> Duration {
        return .zero
    }

    var playbackStateStream: AsyncStream<PlaybackState> {
        // Never-ending stream that emits nothing — SyncEngine won't crash,
        // it just won't receive playback state updates from "Spotify"
        AsyncStream { _ in }
    }
}
```

**B2. Use `#if targetEnvironment(simulator)` at the call site**

No factory pattern needed. Just wrap the one line in `connectToSession` (line 332):

```swift
// In connectToSession:
#if targetEnvironment(simulator)
let player = MockMusicSource()
#else
let player = SpotifyPlayer(appRemote: authManager.appRemote)
#endif
```

This eliminates any new API surface on `SessionStore`. The compile-time check is safer than a runtime factory — impossible to accidentally ship `MockMusicSource` in a device build.

**B3. Handle `PlayerStateBridge` and `onAppRemoteConnected` on simulator**

On the simulator, `PlayerStateBridge` receives a `MockMusicSource` and `authManager.onAppRemoteConnected` will never fire (no Spotify app). Both are inert and safe — no crashes, no dangling state. The `#if` guard can also skip the `player.setOnTrackMismatch` callback and the `authManager.isConnectedToSpotifyApp` check:

```swift
#if !targetEnvironment(simulator)
await player.setOnTrackMismatch { [weak self] in
    Task { @MainActor in
        await self?.reassertPlayback()
    }
}
#endif
```

## Acceptance Criteria

- [x] Network errors show "Not connected to session" instead of "Session not found"
- [x] Expired token errors show "Your session has expired" instead of "Session not found"
- [x] Full station errors show "This session is full" instead of "Session not found"
- [x] `CancellationError` from rapid station switching is silently discarded (no error shown)
- [x] `.sessionNotFound` copy no longer references "the code"
- [x] `MockMusicSource` conforms to actual `MusicSource` protocol (including `playbackStateStream`)
- [x] Simulator builds use `MockMusicSource` via `#if targetEnvironment(simulator)`
- [ ] The tune-to-station flow completes on the simulator (HTTP join + WebSocket connect + stateSync received)
- [x] All error paths log the actual underlying error for debugging

## Files to Modify

| File | Change |
|------|--------|
| `PirateRadio/Core/Sync/SessionStore.swift` | Error discrimination in `joinSessionById` (A2) and `joinSessionByIdOnBackend` (A1); `#if simulator` in `connectToSession` (B2, B3) |
| `PirateRadio/Core/Models/PirateRadioError.swift` | Update `.sessionNotFound` description (A3) |
| `PirateRadio/Core/Mock/MockMusicSource.swift` | **New** — mock music source for simulator (B1) |

## Future Work (separate tasks)

- Server-side tests for HTTP error codes (400/401/404/409) on `join-by-id`
- Integration test suite with real local server + `MockMusicSource`
- WebSocket close code 4009 → `.sessionFull` propagation (needs typed close code, not string matching)
- Token refresh callback for WebSocket reconnection with expired JWT

## References

- Brainstorm: `docs/brainstorms/2026-03-07-persistent-stations-brainstorm.md`
- Institutional learning: `docs/solutions/integration-issues/websocket-protocol-mismatch-silent-message-drop.md` — always log decode failures
- Institutional learning: `docs/solutions/runtime-errors/observable-environment-race-on-launch.md` — eager init pattern
- `SyncEngine` already accepts `any MusicSource` — the mock boundary exists, just needs wiring
- `MusicSource` protocol: `PirateRadio/Core/Protocols/MusicSource.swift`
