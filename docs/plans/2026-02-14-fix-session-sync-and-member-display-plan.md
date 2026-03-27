---
title: Fix Session Sync — Member Display, Join Notifications, and Playback Relay
type: fix
date: 2026-02-14
---

# Fix Session Sync — Member Display, Join Notifications, and Playback Relay

## Overview

Three visible bugs that all trace back to a **fundamental client/server WebSocket protocol mismatch**: the iOS `SyncMessage` Codable struct expects a completely different JSON shape than what the Fly.io server actually sends. Every WebSocket message from the server is silently dropped by `JSONDecoder`, which means member joins, state syncs, and playback commands never reach the UI.

## Problem Statement

**What the user sees (from screenshot):**
1. Joiner sees the DJ's name as `1yarjhamxgjka2k0xcll5qow4` (raw Spotify user ID) instead of "Aaron Rosenberg"
2. Host never sees when someone joins the session
3. Joiners never hear the music the DJ is playing

**Root cause: Protocol format mismatch between client and server.**

The server sends messages like:
```json
{
  "type": "memberJoined",
  "data": { "userId": "abc", "displayName": "Aaron" },
  "epoch": 0,
  "seq": 1,
  "timestamp": 1707900000000
}
```

The client tries to decode `SyncMessage`:
```swift
struct SyncMessage: Codable {
    let id: UUID                    // Server doesn't send this
    let type: SyncMessageType       // Enum with associated values — different encoding
    let sequenceNumber: UInt64      // Server sends "seq", not "sequenceNumber"
    let epoch: UInt64
    let timestamp: UInt64
}
```

Mismatches:
- **`id: UUID`** — server never sends this field
- **`seq` vs `sequenceNumber`** — field name mismatch
- **`data` wrapper** — server wraps payloads in a `data` object; client expects enum associated values inline
- **`SyncMessageType` Codable encoding** — Swift enum with associated values encodes differently than `{ type: "memberJoined", data: {...} }`

Result: `JSONDecoder().decode(SyncMessage.self, from: data)` **always fails**, and the `guard let` in `WebSocketTransport.handleReceivedMessage()` silently returns. Zero server messages ever reach `SyncEngine.processMessage()`.

### Secondary Issues

Even if decoding worked:

1. **`JoinSessionResponse` lacks `djDisplayName`** (SessionStore:70) — the REST join endpoint returns only `djUserId`, so the joiner falls back to showing the raw ID
2. **`SyncMessageType.memberJoined(UserID)` carries no display name** (SessionTransport:32) — even if decoded, the enum only has the user ID
3. **`SessionStore.play(track:)` bypasses SyncEngine entirely** (SessionStore:148-158) — calls `appRemote.playerAPI?.play()` directly, never calls `syncEngine.djPlay(track:)`, so no `playPrepare`/`playCommit` messages are ever sent to listeners
4. **`stateSync` sent on join has member list with display names** (server:232, 526-544) — but client can't decode it

## Proposed Solution

Fix in three phases, each building on the previous:

### Phase 1: Fix the Wire Protocol (Client ↔ Server Decoding)

The server's message format is simple and well-structured. Rather than changing the server, **adapt the client to decode what the server actually sends**.

**1a. Create a `ServerMessage` struct that matches the server's JSON shape**

```swift
// PirateRadio/Core/Networking/ServerMessage.swift

/// Matches the exact JSON shape sent by the Fly.io backend.
/// The server sends: { type: String, data: {…}, epoch: UInt64, seq: UInt64, timestamp: UInt64 }
struct ServerMessage: Codable {
    let type: String
    let data: AnyCodable  // or use JSONValue enum
    let epoch: UInt64?
    let seq: UInt64?
    let timestamp: UInt64?
}
```

**1b. Add a message translator in `WebSocketTransport`**

Replace the current `handleReceivedMessage` to:
1. Decode the raw JSON as `ServerMessage` (flexible shape)
2. Map it to the internal `SyncMessage` type based on `type` string
3. Yield the translated `SyncMessage` to `messageContinuation`

This keeps `SyncEngine` unchanged — it still processes `SyncMessage` values.

**Key translations needed:**

| Server `type` | Server `data` | Maps to `SyncMessageType` |
|---|---|---|
| `"stateSync"` | `{ id, members, currentTrack, isPlaying, positionMs, positionTimestamp, epoch, sequence, ... }` | `.stateSync(SessionSnapshot)` |
| `"memberJoined"` | `{ userId, displayName }` | `.memberJoined(UserID)` → **extend to include displayName** |
| `"memberLeft"` | `{ userId }` | `.memberLeft(UserID)` |
| `"playPrepare"` | `{ trackId, prepareDeadline }` | `.playPrepare(trackID:prepareDeadline:)` |
| `"playCommit"` | `{ trackId, ntpTimestamp, ... }` | `.playCommit(trackID:startAtNtp:refSeq:)` |
| `"pause"` | `{ positionMs, ntpTimestamp }` | `.pause(atNtp:)` |
| `"resume"` | `{ positionMs, ntpTimestamp, executionTime }` | `.resume(atNtp:)` |
| `"seek"` | `{ positionMs }` | `.seek(positionMs:atNtp:)` |
| `"queueUpdate"` | `{ queue: [...] }` | `.queueUpdate([String])` |

**1c. Fix outgoing messages too**

When the client sends messages (from `SyncEngine.djPlay()`, etc.), they must match the server's expected format. The server checks `msg.type` and `msg.data` — so outgoing `SyncMessage` JSON encoding must produce `{ type: "playPrepare", data: { trackId: "...", ... } }` format, not Swift's default enum encoding.

Add a `toServerJSON()` method or custom `Codable` conformance on `SyncMessage`.

**Files to modify:**
- `PirateRadio/Core/Networking/WebSocketTransport.swift` — decode/encode translation
- `PirateRadio/Core/Protocols/SessionTransport.swift` — extend `memberJoined` to carry displayName

**New file:**
- `PirateRadio/Core/Networking/ServerMessage.swift` — server JSON shape

### Phase 2: Fix Member Display Names

**2a. Extend `SyncMessageType.memberJoined` to include display name**

```swift
// Before:
case memberJoined(UserID)

// After:
case memberJoined(userID: UserID, displayName: String)
```

Update `SyncEngine.processMessage()` (line 239-240) to pass the display name through.

**2b. Handle `stateSync` member list on join**

The server sends a `stateSync` to the joiner on WebSocket connect (server:232). This includes `members: [{ userId, displayName }]`.

Add a new `SessionUpdate` case or extend `stateSync` handling to:
1. Parse the member list from the snapshot
2. Replace the session's member list with actual display names
3. This fixes both the DJ name for the joiner AND sends the full member list

**2c. Add `djDisplayName` to `JoinSessionResponse`** (nice-to-have)

Update the server's `/sessions/join` endpoint to also return the DJ's display name:

```js
// server/index.js line 141-146
const djMember = session.members.get(session.djUserId);
res.json({
  id: session.id,
  joinCode: session.joinCode,
  djUserId: session.djUserId,
  djDisplayName: djMember?.displayName || session.djUserId,
  memberCount: session.members.size,
});
```

And update `JoinSessionResponse` on the client:
```swift
private struct JoinSessionResponse: Codable {
    let id: String
    let joinCode: String
    let djUserId: String
    let djDisplayName: String?  // new
    let memberCount: Int
}
```

Use `djDisplayName ?? djUserId` when creating the DJ member in `joinSession()`.

**Files to modify:**
- `PirateRadio/Core/Protocols/SessionTransport.swift` — extend memberJoined enum
- `PirateRadio/Core/Sync/SyncEngine.swift` — pass display name from decoded message
- `PirateRadio/Core/Sync/SessionStore.swift` — handle stateSync members, update JoinSessionResponse
- `server/index.js` — add djDisplayName to join response, ensure stateSync includes members

### Phase 3: Wire DJ Playback Through SyncEngine

**3a. Replace direct AppRemote play with `syncEngine.djPlay()`**

In `SessionStore.play(track:)`, after waking Spotify:

```swift
// Before (line 148-158):
appRemote.playerAPI?.play(uri, asRadio: false) { ... }

// After:
try await syncEngine?.djPlay(track: track)
```

This sends `playPrepare` + `playCommit` through the WebSocket, which the server broadcasts to all listeners. Listeners' `SyncEngine` instances receive the messages and call `SpotifyPlayer.play()` on their devices.

**3b. Ensure listeners also wake Spotify before playback**

When `SpotifyPlayer.play(trackID:at:)` is called on a listener device, SPTAppRemote must be connected. The player should handle the "not connected" case — either:
- Surface an error that the UI can show ("Open Spotify to listen")
- Or attempt `wakeSpotifyAndConnect()` automatically

For MVP: listeners need Spotify installed and the app must be woken on session join (not just on play). Add a Spotify wake step in `joinSession()` after connecting to WebSocket.

**3c. Handle `stateSync` for join-mid-song**

When a listener joins while music is playing, the server sends a `stateSync` with `currentTrack`, `positionMs`, and `positionTimestamp`. The `SyncEngine.handleStateSync()` already handles this (line 364-388) — it calculates current position and calls `musicSource.play()`. This should work once Phase 1 fixes decoding.

**Files to modify:**
- `PirateRadio/Core/Sync/SessionStore.swift` — use syncEngine.djPlay() instead of direct AppRemote
- `PirateRadio/Core/Sync/SessionStore.swift` — wake Spotify on join

## Acceptance Criteria

- [x] All WebSocket messages from server decode successfully (add logging to verify)
- [x] When a user joins, the host's UI shows them with correct display name
- [x] When a joiner enters a session, they see the DJ's actual display name (not raw ID)
- [x] When the DJ plays a song, `playPrepare` + `playCommit` messages are sent via WebSocket
- [x] Listeners receive playback commands and hear the same song
- [x] Joining mid-song starts playback at the correct position (via stateSync)
- [x] "connected" badge continues to work

## Implementation Order

1. **Phase 1 first** — without this, nothing else works. The protocol mismatch blocks all sync.
2. **Phase 2 next** — member display names. Quick win once messages flow.
3. **Phase 3 last** — playback sync through SyncEngine. Most impactful for the full experience.

## Critical Implementation Details (from SpecFlow Analysis)

### Exact Field Mappings: Server → Client

**`stateSync` data → `SessionSnapshot`:**
```
data.currentTrack?.id     → trackID: String?
data.positionMs / 1000.0  → positionAtAnchor: Double (seconds)
data.positionTimestamp     → ntpAnchor: UInt64
data.isPlaying ? 1.0 : 0.0 → playbackRate: Double
data.queue.map { $0.id }  → queue: [String]
data.djUserId             → djUserID: UserID
data.epoch                → epoch: UInt64
data.sequence             → sequenceNumber: UInt64
```

**`stateSync` also carries `members: [{ userId, displayName }]`** — this must be parsed and used to replace the session's member list (including fixing DJ display name).

### Outgoing Message Encoding

Client must encode outgoing messages to match server expectations. Example for `playPrepare`:
```json
{
  "type": "playPrepare",
  "data": { "trackId": "abc123", "prepareDeadline": 1707900001500 },
  "seq": 1,
  "epoch": 0,
  "timestamp": 1707900000000
}
```

Key field name mappings (client → server):
- `sequenceNumber` → `seq`
- `trackID` → `trackId` (camelCase, not all-caps ID)
- Omit `id: UUID` (server doesn't use it)
- Nest payload data under `data` key

### No AnyCodable Dependency

Use a lightweight custom `JSONValue` enum instead of a third-party library:
```swift
enum JSONValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool)
    case object([String: JSONValue]), array([JSONValue]), null
}
```

### Deduplicate `memberJoined` Events

Before appending in `handleUpdate()`, check if member already exists:
```swift
case .memberJoined(let userID, let name):
    if let idx = session?.members.firstIndex(where: { $0.id == userID }) {
        session?.members[idx].displayName = name
        session?.members[idx].isConnected = true
    } else {
        session?.members.append(Session.Member(id: userID, displayName: name, ...))
    }
```

### Listener Spotify Wake Strategy

- **On join when music is playing**: If `stateSync` shows `isPlaying: true` and `currentTrack != nil`, wake Spotify immediately so the listener can hear the current song
- **On join when idle**: Don't wake Spotify (no need to interrupt the user)
- **On first `playCommit` received**: Wake Spotify if not already connected

### Cancel Pending Play on Rapid DJ Actions

Store a `currentPlayTask` in `SyncEngine`. When `djPlay()` is called, cancel the previous task before starting the new two-phase commit. This prevents interleaved `playPrepare`/`playCommit` for different tracks.

## Risk Analysis

- **Server changes may need redeployment** — the `djDisplayName` addition to the join endpoint requires deploying the server to Fly.io. All other server changes are additive (no breaking changes).
- **Spotify app must be running on listener device** — SPTAppRemote requires the Spotify app. If a listener doesn't have Spotify installed, playback will fail silently. Per documented learning, wake Spotify before playing.
- **NTP clock sync** — the `KronosClock` must sync before playback commands work. This is already handled in `SyncEngine.start()`.

## References

- `PirateRadio/Core/Networking/WebSocketTransport.swift` — where decoding fails silently
- `PirateRadio/Core/Protocols/SessionTransport.swift` — SyncMessage/SyncMessageType definitions
- `PirateRadio/Core/Sync/SyncEngine.swift` — message processing, djPlay two-phase commit
- `PirateRadio/Core/Sync/SessionStore.swift:148-158` — direct AppRemote play bypassing SyncEngine
- `PirateRadio/Core/Sync/SessionStore.swift:68-73` — DJ name fallback to raw ID
- `server/index.js:232-241` — server stateSync + memberJoined broadcast
- `docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md` — wake Spotify before play
