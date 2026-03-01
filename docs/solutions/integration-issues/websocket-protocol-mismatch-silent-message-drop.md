---
title: "WebSocket protocol mismatch causes silent message drop — all sync fails"
date: 2026-02-14
category: integration-issues
tags: [websocket, sync, codable, json, protocol-mismatch, ios, fly-io]
module: PirateRadio.Core.Networking
symptoms:
  - "Joiner sees raw Spotify user ID instead of display name"
  - "Host never sees when someone joins the session"
  - "Listeners never hear the music the DJ is playing"
  - "No WebSocket errors in console — messages silently dropped"
  - "Session appears connected but no data flows"
  - "memberJoined, stateSync, playCommit events never reach SyncEngine"
severity: blocking
related:
  - docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md
  - docs/solutions/integration-issues/sptappremote-observable-integration.md
  - docs/plans/2026-02-14-fix-session-sync-and-member-display-plan.md
---

# WebSocket Protocol Mismatch Causes Silent Message Drop

## Problem

After connecting two devices to a session, three things fail simultaneously:
1. Joiner sees the DJ's name as a raw Spotify user ID (e.g., `1yarjhamxgjka2k0xcll5qow4`)
2. Host never sees the joiner appear in the member list
3. Listeners never hear the music the DJ plays

No errors appear in the console. The WebSocket connects successfully and the "connected" badge shows green. But **zero server messages reach the app's sync logic**.

## Root Cause

**Complete client/server JSON format mismatch.** The Fly.io server sends messages like:

```json
{
  "type": "memberJoined",
  "data": { "userId": "abc", "displayName": "Aaron" },
  "epoch": 0,
  "seq": 1,
  "timestamp": 1707900000000
}
```

But the iOS client tried to decode directly into `SyncMessage`:

```swift
struct SyncMessage: Codable {
    let id: UUID                    // Server doesn't send this
    let type: SyncMessageType       // Enum — encodes differently than {"type": "string"}
    let sequenceNumber: UInt64      // Server sends "seq", not "sequenceNumber"
    let epoch: UInt64
    let timestamp: UInt64
}
```

Four mismatches that each independently cause `JSONDecoder` to fail:

| Mismatch | Server sends | Client expects |
|----------|-------------|----------------|
| `id` field | Not present | `UUID` (required) |
| Message type | `"type": "memberJoined"` + `"data": {...}` | Swift enum with associated values (different encoding) |
| Sequence field | `"seq"` | `"sequenceNumber"` |
| Payload | Nested under `"data"` key | Inline as enum associated values |

The `guard let` in `handleReceivedMessage()` silently returned on every decode failure. No error was logged because the old code used `try?` without a print.

## Solution

**Anti-Corruption Layer pattern** — translate between server wire format and client domain types at the WebSocket transport boundary.

### 1. Created `ServerMessage` matching the server's actual JSON shape

```swift
// PirateRadio/Core/Networking/ServerMessage.swift

enum JSONValue: Codable, Sendable {
    case string(String), int(Int), double(Double), bool(Bool)
    case object([String: JSONValue]), array([JSONValue]), null
}

struct ServerMessage: Codable, Sendable {
    let type: String        // "memberJoined", "stateSync", etc.
    let data: JSONValue?    // Flexible payload
    let epoch: UInt64?
    let seq: UInt64?
    let timestamp: UInt64?
}
```

### 2. Added bidirectional translation in `WebSocketTransport`

**Incoming (server → client):**
```swift
// Decode flexible ServerMessage first
guard let serverMessage = try? JSONDecoder().decode(ServerMessage.self, from: data) else { return }

// Then translate to domain SyncMessage based on type string
guard let syncMessage = Self.translate(serverMessage, rawData: data) else { return }

messageContinuation.yield(syncMessage)
```

The `translate()` method switches on `msg.type` and extracts fields from the `data` JSONValue using typed accessors (`.stringValue`, `.doubleValue`, etc.).

**Outgoing (client → server):**
```swift
static func encodeForServer(_ message: SyncMessage) -> [String: Any] {
    var result: [String: Any] = [
        "seq": message.sequenceNumber,     // sequenceNumber → seq
        "epoch": message.epoch,
        "timestamp": message.timestamp,
    ]
    switch message.type {
    case .playPrepare(let trackID, let deadline):
        result["type"] = "playPrepare"
        result["data"] = ["trackId": trackID, "prepareDeadline": deadline]  // Nest under "data"
    // ... other cases
    }
    return result
}
```

### 3. Extended `memberJoined` to carry display name

```swift
// Before:
case memberJoined(UserID)

// After:
case memberJoined(userID: UserID, displayName: String)
```

### 4. Added `djDisplayName` to server join response

```javascript
// server/index.js — /sessions/join endpoint
const djMember = session.members.get(session.djUserId);
res.json({
    djDisplayName: djMember?.displayName || session.djUserId,
    // ... other fields
});
```

### 5. Routed DJ playback through SyncEngine

```swift
// Before: direct AppRemote call (only DJ hears music)
appRemote.playerAPI?.play(uri, asRadio: false)

// After: two-phase commit via WebSocket (all listeners hear music)
try await syncEngine?.djPlay(track: track)
```

## Key Field Mappings

| Server field | Client field | Notes |
|-------------|-------------|-------|
| `seq` | `sequenceNumber` | Name mismatch |
| `trackId` | `trackID` | camelCase vs all-caps ID |
| `data.userId` | `userID` | Nested under `data` |
| `data.positionMs` | `positionAtAnchor` | Also ms → seconds conversion |
| `data.positionTimestamp` | `ntpAnchor` | Direct mapping |
| `data.isPlaying` | `playbackRate` | `true` → `1.0`, `false` → `0.0` |

## Why It Was Hard to Find

1. **No errors logged** — the original code used `guard let ... = try? decode() else { return }` with no error logging
2. **Connection appeared healthy** — WebSocket connected fine, the "connected" badge was green
3. **Partial functionality worked** — session creation, join code, REST endpoints all worked. Only WebSocket messages failed.
4. **Swift enum Codable is opaque** — Swift's default Codable encoding of enums with associated values produces JSON that looks nothing like `{"type": "memberJoined", "data": {...}}`

## Prevention

- **Always log decode failures with the raw payload.** The fix added: `print("[WebSocket] Failed to decode: \(String(data: data, encoding: .utf8))")`
- **Add integration tests that encode a server-format JSON string and verify it decodes to the expected `SyncMessage`.** The test suite now includes `memberJoinedRoundTrip()`.
- **When building a client for an existing server, read the server code first.** Don't assume the server matches your Codable struct — verify with actual JSON.
- **Use an Anti-Corruption Layer** at protocol boundaries. Don't try to make domain types match wire format directly.

## Files

- `PirateRadio/Core/Networking/ServerMessage.swift` — JSONValue + ServerMessage (new)
- `PirateRadio/Core/Networking/WebSocketTransport.swift` — Translation layer (translate, encodeForServer, translateStateSync)
- `PirateRadio/Core/Protocols/SessionTransport.swift` — Extended memberJoined, SessionSnapshot.members
- `PirateRadio/Core/Sync/SyncEngine.swift` — Added .stateSynced SessionUpdate case
- `PirateRadio/Core/Sync/SessionStore.swift` — handleStateSync, djPlay routing, ensureSpotifyConnected
- `server/index.js` — djDisplayName in join response
