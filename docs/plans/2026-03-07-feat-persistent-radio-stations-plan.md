---
title: "feat: Persistent Radio Stations with Lazy Snapshot"
type: feat
date: 2026-03-07
brainstorm: docs/brainstorms/2026-03-07-persistent-stations-brainstorm.md
---

# Persistent Radio Stations with Lazy Snapshot

## Overview

Transform ephemeral sessions into permanent, always-on radio stations. Each user owns a station identified by a self-chosen FM frequency. Stations persist in SQLite across server restarts. Queues loop continuously. The server uses a "Lazy Snapshot" model — timers run only when someone is listening; idle stations store a snapshot and compute their current position on tune-in.

## Problem Statement

Stations don't feel permanent. They're in-memory session objects destroyed on disconnect or server restart. Frequencies reset. There's no way to see a friend's station when they're offline, and no way to tune into a station that isn't actively broadcasting.

## Data Model

A **Station** is a persistent SQLite row (one per user, never destroyed). A **live session** is the in-memory real-time state — created when the first listener tunes in, torn down when the last listener leaves. The station owns the data; the live session owns the WebSocket/timer state.

- **Boot:** Station snapshot → compute position → hydrate live session
- **Active:** Live session is authoritative (station row is stale)
- **Teardown:** Live session state → write snapshot to SQLite, tear down timers

**Tracks stored as JSON column** — one query to load, one to save. No separate table, no position management, no FK cascade. At 100 stations x 100 tracks the column is ~500KB total.

**Frequency stored as INTEGER (MHz x 10)** — 88.1 MHz → `881`. Eliminates floating-point comparison bugs in the UNIQUE constraint. Range: 881-1079, step 2 = 100 slots.

### Queue Model

Fixed ordered list of tracks (JSON). A cursor (index) wraps to 0 at the end. Tracks are never re-appended — the list is stable, the cursor moves.

### Lazy Snapshot Lifecycle

1. **Station goes idle** (last listener leaves): Save `{ trackIndex, elapsedMs, timestamp }` to SQLite. Tear down timers and live session.
2. **Someone tunes in**: Compute current position from snapshot + wall-clock elapsed (modular arithmetic skips full loops). Boot live session from computed position.
3. **Active**: Normal session behavior — timers running, WebSocket sync.
4. **Last listener leaves**: Back to step 1.

### Position Computation

Filter zero-duration tracks upfront, then: remaining time in snapshot track → modular arithmetic to skip full loops → walk forward through tracks. Clamp `snapshotTrackIndex` to `tracks.length - 1` (tracks may have been removed while idle). Clamp `snapshotElapsedMs` to track duration (track may have been replaced). O(n) where n ≤ 100, runs once per tune-in.

### DJ Rules

- Owner connected → owner is always DJ. No other user gets DJ on someone else's station.
- Owner not connected → `djUserId = null`. Server drives advancement autonomously. All control messages rejected.
- Listeners are passive — can only `addToQueue`.
- Join codes removed. Stations are public. Tuning uses `join-by-id`.

### Frequency Selection

- `POST /auth` returns `{ needsFrequency: true }` if user has no station.
- `POST /stations/claim-frequency` with `{ frequency: 881 }` → 201 or 409 Conflict.
- Client shows a dial-based picker. Taken frequencies visible from `GET /stations` data. No separate available-frequencies endpoint.

### GET /stations

Returns ALL registered stations (not just active). Query SQLite directly — 100 rows in <1ms, no cache needed. Includes `currentTrack` (from snapshot for idle stations), `trackCount`, `listenerCount`, `isLive`, `ownerConnected`.

---

## SQLite Schema

```sql
-- server/migrations/001-initial-schema.sql

CREATE TABLE IF NOT EXISTS stations (
  user_id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  frequency INTEGER NOT NULL UNIQUE CHECK(frequency >= 881 AND frequency <= 1079 AND frequency % 2 = 1),
  tracks_json TEXT NOT NULL DEFAULT '[]',
  snapshot_track_index INTEGER NOT NULL DEFAULT 0 CHECK(snapshot_track_index >= 0),
  snapshot_elapsed_ms INTEGER NOT NULL DEFAULT 0 CHECK(snapshot_elapsed_ms >= 0),
  snapshot_timestamp INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL DEFAULT (unixepoch('now') * 1000)
);
-- No explicit frequency index needed — UNIQUE constraint creates one.
```

### db.js

Export a factory function for testability. Production uses env var, tests pass `:memory:`.

```javascript
export function createDatabase(dbPath) {
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('synchronous = NORMAL');
  db.pragma('foreign_keys = ON');
  db.exec(readFileSync(join(import.meta.dirname, 'migrations/001-initial-schema.sql'), 'utf8'));
  return db;
}
export default createDatabase(process.env.DB_PATH || '/data/pirate-radio.db');
```

### Shutdown Handler

Snapshot ALL active sessions, then checkpoint and close. Without this, every deploy loses playback state for active listeners.

```javascript
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    for (const [userId, session] of liveSessions) {
      saveSnapshot(userId, session); // write current position to SQLite
    }
    db.pragma('wal_checkpoint(TRUNCATE)');
    db.close();
    process.exit(0);
  });
}
```

### Dockerfile

Use `node:22-slim` (not Alpine — better-sqlite3 has musl/fcntl64 issues). Multi-stage build. Use `--omit=dev` not `--production` (deprecated).

### fly.toml

```toml
[mounts]
  source = "pirate_radio_data"
  destination = "/data"
```

Pre-deploy once: `fly volumes create pirate_radio_data --region sjc --size 1`

---

## Implementation Phases

### Phase 1: Full Server-Side Persistence

**Goal:** SQLite persistence, queue looping, lazy snapshot, frequency selection, DJ rules. The complete server-side feature in one shot.

**All existing in-memory sessions are lost on deploy. This is the current behavior — sessions are already ephemeral.**

**Files:**
- `server/package.json` — add `better-sqlite3`
- `server/db.js` (new) — factory function, PRAGMAs, schema
- `server/migrations/001-initial-schema.sql` (new)
- `server/index.js` — replace `userRegistry` with SQLite, persist tracks, looping cursor, snapshot save/load, `computePosition()`, `claim-frequency` endpoint, DJ rules, updated `GET /stations`
- `server/fly.toml` — add `[mounts]`
- `server/Dockerfile` — switch to `node:22-slim`, multi-stage build

**Tasks:**
- [x] `npm install better-sqlite3`
- [x] Create `server/db.js` with factory function (WAL, NORMAL sync, foreign_keys)
- [x] Create `server/migrations/001-initial-schema.sql` with CHECK constraints including `frequency % 2 = 1`
- [x] Add SIGTERM + SIGINT handler — snapshot active sessions, checkpoint, close
- [x] Update Dockerfile to `node:22-slim` + multi-stage, `--omit=dev`
- [x] Add `[mounts]` to `fly.toml`
- [x] Migrate `POST /auth` — `INSERT OR IGNORE` station row, return `{ needsFrequency }` if no station
- [x] Add `POST /stations/claim-frequency` — validate integer range + step, UNIQUE handles conflicts
- [x] Replace `userRegistry` lookups with `SELECT` from stations
- [x] Persist `addToQueue` / `batchAddToQueue` — read `tracks_json`, append, write back (transaction for batch)
- [x] Persist `removeFromQueue` — splice array, write back, adjust cursor if needed
- [x] Modify `advanceQueue` to wrap cursor: `(currentIndex + 1) % tracks.length`
- [x] When cursor wraps to 0, continue playing (no `isPlaying = false`)
- [x] On last listener disconnect: `snapshotAndTeardown` — save snapshot, clear BOTH timers, tear down live session
- [x] On tune-in to idle station: load snapshot + tracks, `computePosition()`, boot live session
- [x] Modify `POST /sessions/join-by-id` — if no live session exists, boot from snapshot
- [x] Implement `computePosition()` — filter zero-duration tracks, clamp index with `?? 0`, clamp elapsedMs, modular arithmetic
- [x] DJ rules: owner is DJ when connected, `null` when not, reject control messages when no DJ, no DJ promotion
- [x] `GET /stations` returns all stations from SQLite, merge live session data for active ones
- [x] Update `/health` — `SELECT 1` for DB check
- [x] Remove join code generation and `codeIndex` Map
- [x] Tests with `DB_PATH=:memory:`: persistence, looping, snapshot, computePosition (2hr idle, 30-day idle), frequency claiming

**Acceptance Criteria:**
- [x] Server restarts preserve stations, frequencies, and tracks
- [x] Queue loops seamlessly
- [x] Idle station tune-in plays correct track at correct position
- [x] Frequency selection works with 409 on conflict
- [x] Only owner gets DJ controls while connected
- [x] `GET /stations` returns all stations including idle ones
- [x] Existing tests pass

### Phase 2: Client UX + Cleanup

**Goal:** iOS app updates for the persistent station model. Dead code removal.

**Files:**
- `PirateRadio/Core/Models/Station.swift` — new API fields
- `PirateRadio/Core/Models/Session.swift` — `djUserID` becomes optional, remove `DJMode` enum / hot-seat fields
- `PirateRadio/Core/Sync/SessionStore.swift` — `claimFrequency()`, updated `fetchStations`, updated tune-in flow
- `PirateRadio/UI/Onboarding/FrequencyPickerView.swift` (new)
- `PirateRadio/UI/Home/DialHomeView.swift` — all stations on dial, live/idle/empty visual states
- `PirateRadio/UI/NowPlaying/NowPlayingView.swift` — conditional DJ controls, Auto-DJ indicator

**Tasks:**
- [x] Update `Station.swift` — add `trackCount`, `isLive`, `ownerConnected`, `listenerCount`
- [x] Make `djUserID` optional in `Session.swift` — handle `null` in `SyncEngine` and `SessionStore`
- [x] Update `fetchStations()` for new response shape
- [x] Create `FrequencyPickerView.swift` — dial-based picker (use `.task` for async, not `.onAppear`)
- [x] Wire frequency picker into onboarding flow
- [x] Show all stations on dial — live (glowing), idle (dimmer), empty (no tracks)
- [x] Show "Auto-DJ" indicator when `djUserId == null`
- [x] DJ controls visible only when `djUserId == currentUserId`
- [x] Replace "Start Broadcasting" with "Tune to My Station"
- [x] Auto-tune to own station on launch
- [x] Check generation counter after each `await` in extended tune-in flow
- [x] Ensure snapshot resume goes through `SyncEngine` (single playback owner)
- [x] Call `ensureSpotifyConnected` before playback on idle station resume
- [x] Update `ServerMessage` decode layer for `djUserId: null` and new station fields
- [x] **Cleanup:** Remove `DJMode` enum, `hotSeatSongsPerDJ`, `hotSeatSongsRemaining`
- [x] **Cleanup:** Remove join code UI components
- [ ] **Cleanup:** Remove `driftReport` handler if unused

**Acceptance Criteria:**
- [x] Frequency picker shown for new users
- [x] All stations visible on dial with live/idle/empty distinction
- [x] DJ controls work correctly (owner only, while connected)
- [ ] Tuning into idle stations works end-to-end (Spotify wakes, correct position) — needs live testing
- [x] Dead code (join codes, hot-seat, drift report) removed

---

## Risks

| Risk | Mitigation |
|------|------------|
| SQLite corruption on crash | WAL mode + SIGTERM handler snapshots and checkpoints |
| Fly.io volume loss | Daily auto-snapshots (5-day retention). Acceptable for hobby project. |
| 100-station cap | Intentional. Expand to 0.1 steps (200 slots) later if needed. |
| Auth trust model (no Spotify verification) | Known. Acceptable for friends. Harden later. |
| `setTimeout(NaN)` drains queue | Guard with `Number.isFinite()` — documented learning |
| Snapshot index out of bounds | Clamp with `Math.max(0, Math.min(idx ?? 0, len - 1))` |
| `snapshotElapsedMs` > track duration | Clamp with `Math.max(0, duration - elapsed)` |
| Deploy loses active session state | SIGTERM handler snapshots all active sessions before closing |

## Institutional Learnings

Keep these in mind during implementation — each one burned us before:

- `setTimeout(NaN)` drains queue instantly — guard all durations
- Queue payloads must carry full Track objects, not just IDs
- Share cached backend token — don't create redundant `/auth` calls
- Generation counter for tune-in — check after each `await` in the extended flow
- Single playback owner — snapshot resume goes through `SyncEngine`, not `SessionStore`
- Wake Spotify before play — idle resume is a cold-start entry point
- `ServerMessage` decode layer — new fields need explicit handling, `try?` hides mismatches
- `.task` not `.onAppear` for async work in new SwiftUI views
- Eager state init on relaunch — don't rely on `.onChange` for already-true values

## References

- Brainstorm: `docs/brainstorms/2026-03-07-persistent-stations-brainstorm.md`
- Server: `server/index.js`, Tests: `server/test.js`
- iOS: `Station.swift`, `Session.swift`, `SessionStore.swift`, `SyncEngine.swift`, `DialHomeView.swift`
- Fly config: `server/fly.toml`, Dockerfile: `server/Dockerfile`
- better-sqlite3: `github.com/WiseLibs/better-sqlite3` — use transactions for batches, WAL + NORMAL sync
- Fly.io SQLite: volumes are single-machine, run migrations at startup not release_command
- Docker: `node:22-slim` not Alpine for native modules
