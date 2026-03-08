---
status: pending
priority: p2
issue_id: "011"
tags: [code-review, performance, server]
dependencies: []
---

# Debounce persistTracks() to coalesce rapid SQLite writes

## Problem Statement

Every `addToQueue` / `removeFromQueue` / `batchAddToQueue` call serializes the entire tracks array to JSON and writes synchronously to SQLite via `persistTracks()`. Since better-sqlite3 blocks the Node.js event loop, rapid queue mutations (e.g., batch-adding a playlist) stall WebSocket message processing for all connections.

## Findings

- `persistTracks()` called inline inside `handleMessage()` for every queue mutation
- Each call: JSON.stringify(tracks) + synchronous SQLite UPDATE
- At 100 tracks, ~20KB serialized per write
- `snapshotAndTeardown` and shutdown handler already do final saves, so no data loss risk from debouncing

## Proposed Solutions

### Option 1: Trailing debounce per station (1-2 seconds)

**Approach:** Schedule a delayed write per live session. Coalesces rapid mutations into single writes.

```javascript
function persistTracksDebounced(live) {
  if (live._persistTimer) clearTimeout(live._persistTimer);
  live._persistTimer = setTimeout(() => {
    live._persistTimer = null;
    stmtUpdateTracks.run(JSON.stringify(live.tracks), live.userId);
  }, 1500);
}
```

**Pros:** Simple, eliminates write storms during rapid additions
**Cons:** Up to 1.5s window where in-memory differs from SQLite (acceptable — live session is authoritative)
**Effort:** 15 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `server/index.js` — `persistTracks()` function and callers

Also noted by Performance Oracle:
- Nonce idempotency check is O(n) linear scan — consider `Set` for O(1)
- `GET /stations` parses full `tracks_json` for every idle station — consider `json_extract` in SQL or a `current_track_json` column

## Acceptance Criteria

- [ ] persistTracks uses trailing debounce
- [ ] snapshotAndTeardown flushes any pending debounced write
- [ ] Server tests pass
