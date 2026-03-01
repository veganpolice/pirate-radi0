---
title: "feat: Station & Per-User Queue with Autonomous Playback"
type: feat
date: 2026-02-28
status: reviewed
---

# Station & Per-User Queue with Autonomous Playback

## Overview

Evolve the current ephemeral session model into per-user stations with autonomous queue advancement. The core change: when a broadcaster backgrounds the app, their station keeps playing. The server advances the queue using track-duration timers, and listeners stay synced via `stateSync`. This is the POC for testing whether **ambient social presence** is Pirate Radio's core differentiator.

## Problem Statement / Motivation

Today, Pirate Radio sessions die when the DJ leaves. Music is only happening during the narrow window when friends actively coordinate. This makes the app feel like a hassle compared to just opening Spotify solo.

The hypothesis: if stations play autonomously — like a real radio station that broadcasts whether you're in the room or not — friends will tune in habitually. The "leave your bedroom door open with music playing" feeling is what Spotify playlists can't replicate.

**Source:** [Opportunity Solution Tree](../brainstorms/2026-02-28-opportunity-solution-tree.md) — Opportunity 3, Solution 3 (Ambient Social Presence).

## Proposed Solution

### Architecture: Server-Side Duration Timer + stateSync

One path: server timer fires → server advances queue → broadcasts `stateSync` → clients play. When the broadcaster IS connected and triggers a skip manually, the existing PREPARE+COMMIT path handles that unchanged. No new message types needed.

```
BROADCASTER CONNECTED:
  Track ends → client detects → sends skip → server advances → PREPARE+COMMIT → all sync
  (existing behavior, unchanged)

BROADCASTER BACKGROUNDED:
  Track ends → server timer fires → server advances → stateSync → clients self-serve

BROADCASTER RETURNS:
  Reconnects WebSocket → receives stateSync → forces Spotify to correct track
  (existing reconnection flow, no new protocol needed)
```

### Data Model: Gradual Transformation, Not Big-Bang Refactor

Don't rename Session → Station yet. Add fields to the existing model to support station behavior. Prove the mechanics work, then rename later.

## Technical Approach

### Phase 1: Server-Side Queue Timer (Core Mechanic)

The minimum viable change that enables autonomous playback.

**Server changes** (`server/index.js`):

```javascript
// New: advancement timer per session
// session.advancementTimer = null (added to session object)

function scheduleAdvancement(session) {
  clearAdvancement(session);
  if (!session.currentTrack || !session.isPlaying) return;

  // Guard: durationMs must exist and be a number, otherwise skip scheduling.
  // Without this, setTimeout(fn, NaN) fires immediately and drains the queue.
  const durationMs = parseInt(session.currentTrack.durationMs);
  if (!durationMs || durationMs <= 0) return;

  // Account for elapsed time since position was last anchored.
  // positionMs is the position AT positionTimestamp, not "now".
  const elapsed = Date.now() - session.positionTimestamp;
  const currentPositionMs = session.positionMs + elapsed;
  const remainingMs = durationMs - currentPositionMs;

  if (remainingMs <= 0) {
    // Track already ended (e.g., resume after long pause calculation error)
    advanceQueue(session);
    return;
  }

  session.advancementTimer = setTimeout(() => {
    advanceQueue(session);
  }, remainingMs);
}

function clearAdvancement(session) {
  if (session.advancementTimer) {
    clearTimeout(session.advancementTimer);
    session.advancementTimer = null;
  }
}

function advanceQueue(session) {
  const nextTrack = session.queue.shift();
  if (nextTrack) {
    session.currentTrack = nextTrack;
    session.positionMs = 0;
    session.positionTimestamp = Date.now();
    session.isPlaying = true;
    session.epoch++;
    session.sequence = 0;
    // Keep session alive — prevents idle timeout from killing active stations
    session.lastActivity = Date.now();

    broadcastToSession(session, {
      type: "stateSync",
      data: sessionSnapshot(session),
      epoch: session.epoch,
      seq: session.sequence,
      timestamp: Date.now(),
    });

    scheduleAdvancement(session);
  } else {
    // Queue empty — station goes idle
    session.isPlaying = false;
    // Don't null currentTrack — keep it for "last played" context
    session.lastActivity = Date.now();

    broadcastToSession(session, {
      type: "stateSync",
      data: sessionSnapshot(session),
      epoch: session.epoch,
      seq: ++session.sequence,
      // Note: queue-empty path increments sequence without epoch bump
      // because this is a state change, not an authority change.
      timestamp: Date.now(),
    });
  }
}
```

**Hook into existing handlers:**

- `playCommit` handler → call `scheduleAdvancement(session)`
- `skip` handler → call `scheduleAdvancement(session)` (after shifting queue)
- `pause` handler → call `clearAdvancement(session)`
- `resume` handler → call `scheduleAdvancement(session)` (elapsed-time calculation handles the rest)
- `destroySession()` → call `clearAdvancement(session)` before deleting from map
- Idle timeout cleanup → call `clearAdvancement(session)`

**Single-user station survival:** Currently, if the broadcaster is the only member and they background (WebSocket dies), `session.members.size === 0` triggers `destroySession`. This kills the "leave your bedroom door open" use case. Fix: add a grace period before destroying memberless sessions:

```javascript
// In ws.on("close") handler, replace immediate destroy with:
if (session.members.size === 0) {
  // Grace period: keep station alive for 5 min if queue has tracks
  if (session.queue.length > 0 || session.isPlaying) {
    session.destroyTimeout = setTimeout(() => {
      destroySession(session.id);
    }, 5 * 60 * 1000); // 5 minutes
  } else {
    destroySession(session.id);
  }
}

// Cancel grace period if someone reconnects:
// In session join handler:
if (session.destroyTimeout) {
  clearTimeout(session.destroyTimeout);
  session.destroyTimeout = null;
}
```

**Tasks:**
- [x] Add `advancementTimer` and `destroyTimeout` fields to session object (`server/index.js:~40`)
- [x] Implement `scheduleAdvancement()`, `clearAdvancement()`, `advanceQueue()` with elapsed-time calculation and `durationMs` guard
- [x] Hook `scheduleAdvancement` into `playCommit` handler (`server/index.js:~380`)
- [x] Hook `scheduleAdvancement` into `skip` handler (`server/index.js:~430`)
- [x] Hook `clearAdvancement` into `pause` handler
- [x] Hook `scheduleAdvancement` into `resume` handler
- [x] Hook `clearAdvancement` into `destroySession()` and idle timeout cleanup
- [x] Add 5-minute grace period for memberless sessions with active queues
- [x] Cancel grace period when a member joins/reconnects
- [x] Add `advanceQueue` tests: timer fires → queue shifts → stateSync broadcast → next timer scheduled
- [x] Add edge case tests: queue empty → station idle, pause → timer cleared, resume → timer reset, missing durationMs → timer not set, memberless grace period

**Success criteria:** Server advances queue on a timer without any client interaction. Single-user stations survive backgrounding for at least 5 minutes.

---

### Phase 2: All Clients Play on stateSync

One change: remove the `isDJ` guard so all clients play new tracks on stateSync.

**The bug to avoid:** `SessionStore.handleStateSync()` currently calls `play(track:)` which goes through `SyncEngine.djPlay()` — sending PREPARE+COMMIT back to the server. If a listener calls this, they send DJ commands that get silently rejected. Listeners need a local-only playback path.

**The fix:** `SyncEngine.handleStateSync()` at lines 413-437 already plays locally via `musicSource.play()` without sending sync messages. It already calculates position from `positionAtAnchor` + elapsed time. This works for ALL clients.

The problem is `SessionStore.handleStateSync()` at line 305-308 ALSO triggers `play(track:)` for the DJ, causing a double-play. Solution: remove the playback trigger from `SessionStore.handleStateSync()` entirely. Let `SyncEngine` own all playback decisions.

```swift
// SessionStore.swift ~line 305-308 — REMOVE this block:
// if isDJ, snapshot.playbackRate > 0,
//    let track = snapshot.currentTrack,
//    track.id != previousTrackID {
//     Task { await play(track: track) }
// }

// SyncEngine.handleStateSync already handles playback for all clients.
// No change needed there — it already plays for everyone.
```

**Tasks:**
- [x] Remove the DJ playback trigger from `SessionStore.handleStateSync()` (`SessionStore.swift:~305-308`)
- [x] Verify `SyncEngine.handleStateSync()` plays for all clients (it already does — `lines 413-437`)
- [ ] Test: server timer advances queue → listener receives stateSync → Spotify plays new track at correct position
- [ ] Test: DJ receives stateSync from server-initiated advance → plays correctly without sending duplicate PREPARE+COMMIT

**Success criteria:** When the server timer advances the queue, all connected clients automatically play the new track. No double-play, no leaked DJ commands from listeners.

---

### Phase 3: Verify Foreground Reconciliation (Not New Code)

The existing reconnection flow should already handle this. Phase 3 is verification, not implementation.

**What already exists:**
1. `WebSocketTransport` reconnects with exponential backoff on disconnect
2. Server sends `stateSync` to newly connected clients
3. `SyncEngine.handleStateSync()` plays the server-authoritative track at the correct position
4. SPTAppRemote wake pattern: check `isConnectedToSpotifyApp`, wake if needed (`docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md`)

**What to verify:**
- Broadcaster backgrounds for 5 minutes
- Server advances 1-2 tracks via timer
- Spotify autoplays its own queue on the broadcaster's device
- Broadcaster foregrounds → app reconnects → stateSync arrives → Spotify is forced to the server-authoritative track

**If it works:** Done. No new code.

**If it breaks:** Fix the existing `handleStateSync` path. The most likely failure point is SPTAppRemote not being connected after background — apply the existing wake pattern.

**Tasks:**
- [ ] Integration test: background broadcaster 2+ minutes → server advances → foreground → verify correct track plays
- [ ] Verify SPTAppRemote reconnection on foreground (apply wake pattern if needed)
- [x] Add "Your station ran out of music" toast when broadcaster returns to an idle station (queue empty)
- [x] Add Spotify Premium guard in `play()` — show toast if SPTAppRemote fails with a permissions error

**Success criteria:** Broadcaster can background for 5+ minutes, return, and seamlessly resume with the correct track playing.

---

## Acceptance Criteria

### Functional Requirements

- [ ] Server advances queue when track duration elapses, with no client interaction needed
- [ ] Listeners automatically play new tracks when server advances the queue
- [ ] Broadcaster can background the app and station continues for at least 5 minutes (queue permitting)
- [ ] Single-user stations survive backgrounding (5-minute grace period)
- [ ] Broadcaster returning from background reconnects and plays the correct track
- [ ] "Station ran out of music" feedback when queue empties while backgrounded

### Non-Functional Requirements

- [ ] No memory leaks from orphaned timers (cleared on session destroy)
- [ ] `advanceQueue` updates `lastActivity` so idle timeout doesn't kill active stations

### Quality Gates

- [ ] Server advancement tested with mock timers
- [ ] Foreground reconciliation tested with real background/foreground cycle
- [ ] Grace period tested: solo station survives background, destroyed after 5 min with no reconnect

## Dependencies & Prerequisites

- **Spotify Premium** required for all playback. Add a guard + toast for free-tier users.
- **In-memory server state** accepted. Deploys will kill stations. Known limitation.
- **No database** needed for POC. Persistence is a separate workstream.
- **Existing WebSocket infrastructure** handles reconnection with exponential backoff.

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Server timer drift from real Spotify playback | Medium | Low | Elapsed-time calculation accounts for anchor time. Acceptable for POC — within a few seconds is fine. |
| Spotify autoplay interference after track ends | High | Medium | `handleStateSync` force-plays server-authoritative track on any track change. |
| iOS kills WebSocket quickly in background | Certain | Low | Expected. Server timer is the whole point. |
| Fly.io deploy kills all stations | Certain | Medium | Accepted for POC. Add persistence in follow-up. |
| Single-user station destroyed on background | High | High | 5-minute grace period for memberless sessions with active queues. |
| Race: broadcaster reconnects during server advancement | Low | Medium | Server is authoritative. Epoch increment prevents double-skip. Client yields to stateSync. |
| Missing `durationMs` drains queue instantly | Low | Critical | `parseInt` guard + early return in `scheduleAdvancement`. |
| Full-queue broadcast size (200 tracks = ~60KB) | Low | Low | Acceptable for POC. Delta updates are a future optimization. |

## Implementation Order

```
Phase 1 (Server Timer + Grace Period)    ← Core mechanic, ~30 LOC server
    ↓
Phase 2 (All Clients Play on stateSync)  ← 1-line removal + verification
    ↓
Phase 3 (Verify Foreground Reconcile)    ← Testing, minimal new code
```

**Total: 3 phases, ~12 tasks.** Ship in ~1 week, then dogfood with friends via TestFlight.

## What We're NOT Building (YAGNI)

- **Planet system** — use existing sessions for now
- **Dial UI** — share join codes in group chat for the POC
- **Station discovery API** — friends know each other, share codes directly
- **Playlist import** — manually add tracks to queue (already works). Build after validating the core hypothesis.
- **Frequency assignment** — no station identity system yet
- **Spotify handoff** — broadcaster must use Pirate Radio to manage queue
- **Database persistence** — in-memory is fine for testing the hypothesis
- **DJ modes** — station owner always controls the queue
- **Session → Station rename** — evolve, don't refactor
- **Shazam capture** — separate spike
- **`playbackReport` message** — existing stateSync reconnection is sufficient. Add only if drift proves problematic in testing.
- **`replaceQueue` message** — use existing `addToQueue` in a loop. Atomic replacement is premature.
- **Delta queue updates** — broadcast full queue. Optimize when queue churn is high.
- **Auto-refresh station list** — not building station list yet
- **Performance targets for timer accuracy** — test first, set bars later

## Future Work (After POC Validates)

If friends actually tune in and leave stations running:

1. **Playlist import** — `getUserPlaylists` + `getPlaylistTracks` Spotify API, simple picker UI
2. **Station discovery** — `GET /stations` endpoint (auth-gated), replace DiscoveryView mock data, join via join code (not session ID, to preserve security)
3. **Persistence** — Redis or SQLite so deploys don't kill stations
4. **Planet system** — persistent friend groups, deep link invites
5. **Dial UI** — the full radio dial vision

## Success Metrics (Dogfooding)

After shipping to your friend group via TestFlight:

- Do friends leave stations running when they close the app?
- Do friends tune in to stations when they see someone's live?
- Does it feel different from sharing a Spotify playlist?
- How many tune-ins per week per person?

If the answer to question 3 is "yes" — build the rest. If "no" — rethink.

## References & Research

### Internal References
- OST: `docs/brainstorms/2026-02-28-opportunity-solution-tree.md`
- Vision brainstorm: `docs/brainstorms/2026-02-28-planets-stations-vision-brainstorm.md`
- Server session model: `server/index.js:35-50`
- Server queue handlers: `server/index.js:408-466`
- Server session destroy: `server/index.js:526` — must add `clearAdvancement` here
- Server ws.close handler: `server/index.js:269-298` — add grace period here
- Client session store: `PirateRadio/Core/Sync/SessionStore.swift:1-30, 178-190, 305-308`
- Sync engine stateSync handler: `PirateRadio/Core/Sync/SyncEngine.swift:413-437` — already plays for all clients
- Spotify player state machine: `PirateRadio/Core/Spotify/SpotifyPlayer.swift:14-27, 149-170`
- WebSocket transport: `PirateRadio/Core/Networking/WebSocketTransport.swift:309-364`
- Track model: `PirateRadio/Core/Models/Track.swift:1-37`

### Institutional Learnings
- Queue updates must use full Track objects, not just IDs (`docs/solutions/integration-issues/websocket-protocol-mismatch-silent-message-drop.md`)
- Use stateSync as broadcast mechanism for skip, not playPrepare (`docs/solutions/integration-issues/`)
- SPTAppRemote is IPC — check `isConnected` before play, wake if needed (`docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md`)
- `@Observable` breaks `lazy var` — use `@ObservationIgnored` (`docs/solutions/runtime-errors/observable-environment-race-on-launch.md`)
- Anti-Corruption Layer at WebSocket boundary (`docs/solutions/integration-issues/websocket-protocol-mismatch-silent-message-drop.md`)

### Review Feedback Incorporated
- **DHH reviewer:** Cut `playbackReport`, simplify playlist picker, honest YAGNI list, queue-empty UX, Spotify Premium guard
- **Kieran reviewer:** Fixed `positionMs` staleness bug, `durationMs` guard, double-play fix (remove DJ playback from SessionStore), single-user station destruction, `lastActivity` in advanceQueue, `clearAdvancement` in destroySession
- **Simplicity reviewer:** Cut Phases 4 & 5 to Future Work, collapsed Phase 3 to verification, reduced 28 tasks → 12 tasks, ~355 LOC not written
