---
title: "Stabilize and Test: Lock In What Works, Fix What Doesn't"
type: feat
date: 2026-03-27
---

# Stabilize and Test: Lock In What Works, Fix What Doesn't

## Overview

Pirate Radio's core flows work — creating stations, joining via code/dial, synchronized playback, and queue management. But the app is buggy, the most critical components have zero test coverage despite mocks being ready, and there's no CI. This plan fixes the known stability bugs, locks in what works with ~20 focused tests, and sets up CI.

## Problem Statement

- **SyncEngine** (460 lines, actor, NTP timing, drift correction, two-phase play) has **zero tests** — but `MockMusicSource`, `MockSessionTransport`, and `MockClockProvider` already exist and are unused.
- **SessionStore** (650+ lines, @Observable @MainActor) is where 10 of the 15 documented bug fixes lived — also untested.
- **No CI** — regressions are only caught manually.
- **Known bugs**: Task leaks in SyncEngine, dual queue advancement authority (client + server both advance), `djPlay()` sequencing race.
- **15 documented bug solutions** in `docs/solutions/` — none have regression tests to prevent recurrence.

## Proposed Solution

Two phases:

1. **Phase A: Fix + Test** — Fix stability bugs and write regression tests together
2. **Phase B: CI** — GitHub Actions for both Swift and Node test suites

Error surfacing (`try?` -> `do/catch`) and admin endpoint auth are real improvements but are separate tickets — they're features, not stability prerequisites.

---

## Phase A: Fix + Test

### A.1 Fix Task leaks in SyncEngine

`startListening()` (line ~208) and `startConnectionMonitoring()` (line ~442) spawn `Task` instances that are never stored or cancelled. Only `driftCheckTask` is properly cancelled in `stop()`.

**Fix:** Store all tasks as instance properties, cancel them in `stop()`. Also cancel previous tasks at the *start* of each method to avoid doubling up if `start()` is called twice.

```swift
// SyncEngine.swift
private var listeningTask: Task<Void, Never>?
private var monitoringTask: Task<Void, Never>?
private var driftCheckTask: Task<Void, Never>?

func stop() {
    listeningTask?.cancel()
    monitoringTask?.cancel()
    driftCheckTask?.cancel()
    listeningTask = nil
    monitoringTask = nil
    driftCheckTask = nil
}
```

**Files:** `PirateRadio/Core/Sync/SyncEngine.swift`

### A.2 Resolve dual queue advancement

Both the client (`SpotifyPlayer.onTrackEnded` -> `SessionStore.skipToNext()`) and server (`scheduleAdvancement()` timer) can advance the queue independently. This caused the double-play bug documented in `statesync-double-play-dj-and-syncengine.md`.

**Fix:** Server timer is authoritative. Remove client-side `onTrackEnded` -> `skipToNext()` path. The DJ client should only advance when it receives `stateSync` from the server with a new track.

**Note:** If a track has no `durationMs`, the server timer won't fire and the queue won't auto-advance. This is an acceptable contract — tracks without duration require manual skip.

**Files:** `PirateRadio/Core/Spotify/SpotifyPlayer.swift`, `PirateRadio/Core/Sync/SessionStore.swift`

### A.3 Fix `djPlay()` sequencing race

In `SyncEngine.djPlay()`, `lastProcessedSeq += 2` is set *after* the 1.5s `Task.sleep` and local play execution. Messages arriving during the sleep window with `seq = lastProcessedSeq + 1` will be processed when they shouldn't be.

**Fix:** Increment `lastProcessedSeq` *before* the sleep, not after.

**Files:** `PirateRadio/Core/Sync/SyncEngine.swift`

### A.4 SyncEngine unit tests (Swift Testing)

Using existing mocks. Accept real-time waits (~20s total for the suite — not worth a `Sleeper` abstraction for 10 tests).

| Test | What it verifies |
|------|-----------------|
| `djPlay sends PREPARE then COMMIT` | Two-phase protocol sequencing |
| `djPlay increments lastProcessedSeq by 2` | Sequencing bookkeeping (validates A.3 fix) |
| `listener handles stateSync with catch-up` | Position calculation from NTP anchor |
| `stale epoch messages are ignored` | Epoch/sequence filtering |
| `out-of-order sequence messages are ignored` | Sequence filtering |
| `pause and resume round-trip` | Playback state transitions |
| `drift > 500ms triggers hard seek` | Tier 3 drift correction |
| `drift < 50ms is ignored` | Tier 1 drift correction |
| `stop cancels all tasks` | Resource cleanup (validates A.1 fix) |
| `stateSync resets epoch on new session` | Epoch management |
| `memberJoined and memberLeft update state` | Member management |

**Files:** `PirateRadioTests/SyncEngineTests.swift` (new)

### A.5 SessionStore state logic tests (Swift Testing)

No protocol extraction needed — use `SpotifyAuthManager()` + `enableDemoMode()` (the existing demo pattern at line ~571 of SessionStore.swift). Test only the pure state logic, not the full transport/auth flows:

| Test | What it verifies |
|------|-----------------|
| `handleUpdate with memberJoined deduplicates` | Member deduplication |
| `handleUpdate with stateSync replaces members` | State sync member handling |
| `handleUpdate with stateSync promotes new DJ` | DJ promotion |

**Files:** `PirateRadioTests/SessionStoreTests.swift` (new)

### A.6 WebSocketTransport smoke tests (Swift Testing)

3-4 tests for the trickiest message types that go through the production `ServerMessage` + `JSONValue` path (not the `ServerEnvelope` path the existing wire protocol tests use):

| Test | What it verifies |
|------|-----------------|
| `stateSync with full payload translates correctly` | Most complex message type |
| `queueUpdate with Track array translates correctly` | Array-of-objects deserialization |
| `memberJoined translates correctly` | Field mapping (userId -> userID) |
| `unknown message type does not crash` | Graceful handling |

**Files:** `PirateRadioTests/WebSocketTransportTests.swift` (new)

### A.7 Server test expansion

Add to existing `server/test.js`:

| Test | What it verifies |
|------|-----------------|
| `DJ disconnect promotes next member` | DJ promotion |
| `Reconnecting member replaces old WS` | Member replacement (line ~344) |
| `Grace period keeps session alive` | 5-min grace timer |
| `Session destroyed after idle timeout` | 30-min idle cleanup |
| `addToQueue nonce deduplication` | Idempotency mechanism |

**Files:** `server/test.js`

---

## Phase B: CI Pipeline

### B.1 GitHub Actions for server tests

```yaml
# .github/workflows/server-tests.yml
name: Server Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - run: cd server && npm ci && npm test
```

### B.2 GitHub Actions for Swift tests

```yaml
# .github/workflows/ios-tests.yml
name: iOS Tests
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen generate
      - run: xcodebuild -resolvePackageDependencies -scheme PirateRadio
      - run: |
          xcodebuild test \
            -scheme PirateRadio \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -resultBundlePath TestResults \
            | xcpretty
```

**Note:** iOS tests run on push to main + PRs only (not every branch push) to conserve macOS runner minutes. SPM dependency resolution is a separate step for clearer failure attribution. Pin xcodegen version if phantom failures appear.

### B.3 Branch protection

Enable required status checks on `main` for both workflows.

**Files:** `.github/workflows/server-tests.yml` (new), `.github/workflows/ios-tests.yml` (new)

---

## On-Device Playback Checklist

Not a "phase" — just run this when TestFlighting:

**Session Lifecycle:**
- [ ] Create station -> join code displayed
- [ ] Second device joins via code -> both see each other in members
- [ ] DJ picks track -> both devices play in sync (within ~500ms)
- [ ] DJ skips -> both devices advance
- [ ] DJ pauses -> both devices pause
- [ ] DJ resumes -> both devices resume from same position
- [ ] Listener leaves -> DJ sees member count decrease
- [ ] DJ leaves -> listener sees DJ promotion or session end

**Spotify App Lifecycle:**
- [ ] Force-quit Spotify -> app shows "Connecting to Spotify..." (not silent failure)
- [ ] Return to Pirate Radio -> Spotify reconnects and resumes playback
- [ ] Lock phone for 2+ minutes -> unlock -> playback still in sync
- [ ] Switch to another app for 30s -> return -> playback still in sync
- [ ] Spotify Premium expires mid-session -> clear error (not crash)

**Queue Management:**
- [ ] Add 3+ tracks to queue -> queue displays correctly on both devices
- [ ] Skip through queue -> server advances correctly
- [ ] Let track play to completion -> auto-advances to next
- [ ] Empty queue -> playback stops cleanly

**Error States:**
- [ ] Join with invalid code -> clear error message
- [ ] Join expired session -> clear error message
- [ ] No network -> reconnection indicator shown, auto-reconnects when restored
- [ ] Spotify not installed -> clear error message (not crash)
- [ ] Server restarts during active session -> client reconnects and resumes

**Use the monitoring dashboard** (`open monitor/index.html`) during testing to verify server-side state matches client.

---

## Acceptance Criteria

### Phase A (Fix + Test)
- [x] `SyncEngine.stop()` cancels all spawned tasks
- [x] Queue advancement is server-authoritative only
- [x] `djPlay()` increments seq before the sleep, not after
- [x] SyncEngine has 11 unit tests passing
- [x] SessionStore has 3 state logic tests passing
- [x] WebSocketTransport has 4 smoke tests passing
- [x] Server has 5 new tests passing
- [x] All tests pass: `xcodebuild test` and `npm test`

### Phase B (CI)
- [x] Push to main / PR triggers both test suites
- [ ] Branch protection requires passing checks (enable after first green run)

---

## Future Work (separate tickets)

- **Error surfacing**: Replace `try?` with `do/catch` in SyncEngine, add `.playbackError(Error)` to `SessionUpdate`, wire to UI
- **Admin endpoint auth**: Add bearer token to `/admin/sessions`, update monitoring dashboard
- **Tier 2 drift correction**: Currently a placeholder (50-500ms drift logged but not corrected) — implement rate adjustment via Spotify SDK
- **Deprecate `ServerEnvelope`**: After WebSocketTransport smoke tests are in place, consolidate the two deserialization paths
- **`SyncCommand` / `SyncMessage` consolidation**: Two redundant command types coexist

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| SpotifyiOS SDK may not resolve in CI | SPM should handle it; mock-only tests don't invoke the real SDK. Separate dependency resolution step for clarity. |
| `Task.sleep` in SyncEngine makes tests slow | Accept ~20s total runtime. Not worth an abstraction for 11 tests. |
| macOS CI runners burn free minutes fast | iOS tests only on push to main + PRs, not every branch push |

## References

### Documented Bug Solutions
- `docs/solutions/integration-issues/statesync-double-play-dj-and-syncengine.md` — dual advancement bug
- `docs/solutions/integration-issues/websocket-protocol-mismatch-silent-message-drop.md` — protocol mismatch pattern
- `docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md` — Spotify app lifecycle
- `docs/solutions/integration-issues/queue-skip-wiring-client-server.md` — queue skip wiring
- `docs/solutions/runtime-errors/observable-environment-race-on-launch.md` — crash on launch

### Key Files
- `PirateRadio/Core/Sync/SyncEngine.swift` — core sync actor, primary test target
- `PirateRadio/Core/Sync/SessionStore.swift` — state management, test via demo mode
- `PirateRadio/Core/Networking/WebSocketTransport.swift` — production deserialization path
- `PirateRadio/Core/Mocks/` — existing mock implementations ready for use
- `server/index.js` — single-file server
- `server/test.js` — existing server test suite to expand
