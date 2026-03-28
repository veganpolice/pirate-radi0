---
title: "feat: Walkie-talkie voice clips"
type: feat
date: 2026-03-27
---

# Walkie-Talkie Voice Clips

## Overview

Anyone tuned into a station can hold a push-to-talk button, record a short voice clip (max 10 seconds), and have it played to everyone else on the station within ~200-500ms of releasing the button. While the clip plays, Spotify music ducks. Clips are purely ephemeral — no persistence, no replay.

## Motivation

Pirate Radio is a shared listening experience but there's no way to communicate. Walkie-talkie clips add a voice layer that feels natural — like real radio chatter. It's fast, lightweight, and disappears after it's heard.

## Proposed Solution

Store-and-forward: record the full clip, compress to AAC (~40KB for 10s), send as a single binary WebSocket frame. The server relays to all station members. No streaming, no persistence, no new infrastructure.

## Technical Approach

### Protocol: Single Binary Frame

One binary WebSocket frame per clip, structured as:

```
[4 bytes: uint32 JSON length][JSON metadata bytes][AAC audio bytes]
```

The client packs metadata + audio into one frame. The server splits by reading the 4-byte header, validates, injects `senderName` from its member registry, repacks, and broadcasts the single frame to all other station members.

**Metadata (JSON portion):**
```json
{
  "type": "voiceClip",
  "clipId": "uuid",
  "durationMs": 4500
}
```

The server injects `senderId` and `senderName` from its member registry before relaying — the client does not send these fields. This is both simpler and more secure than trusting the client.

**Why single-frame?** Eliminates all pairing state: no `pendingVoiceClip` tracking, no timeouts for orphan metadata, no race conditions between text and binary frames, no `sendBinary` method on the transport protocol.

### Audio Recording Settings

```swift
let settings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
    AVSampleRateKey: 22050,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 32000,
    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
]
```

~40KB for 10 seconds. Well within the 512KB WebSocket maxPayload.

### Audio Session Management

Audio session category switching is inlined directly into `VoiceClipRecorder` and `VoiceClipPlayer` — no separate abstraction. When speed-volume control arrives, we'll extract the shared concern with two concrete use cases to guide the design.

| State | Category | Options | Spotify |
|-------|----------|---------|---------|
| Normal | `.playback` | `.mixWithOthers` | Full volume |
| Recording (PTT held) | `.playAndRecord` | `.duckOthers`, `.defaultToSpeaker`, `.allowBluetoothA2DP` | Ducked |
| Playing received clip | `.playback` | `.duckOthers` | Ducked |

**Critical transitions:**
- Must call `setActive(false, options: .notifyOthersOnDeactivation)` before switching back to normal mode to properly unduck Spotify.
- Must also deactivate when transitioning between non-normal states (e.g., recording → playingClip) to reset ducking properly.

### Architecture

Voice clips are a **parallel path** — they bypass `SyncMessage`/`SyncEngine` entirely since they don't participate in epoch/sequence ordering.

```
┌───────────────────────────────────────────────────────────┐
│ iOS Client                                                │
│                                                           │
│  WalkieTalkieButton ──► VoiceClipRecorder                 │
│       (UI)                  (AVAudioRecorder + session)   │
│         │                       │                         │
│         ▼                       │                         │
│  SessionStore ◄─────────────────┘                         │
│    │       │                                              │
│    │       ├── send: WebSocketTransport.sendVoiceClip()   │
│    │       │         (packs single binary frame)          │
│    │       │                                              │
│    │       └── recv: WebSocketTransport.incomingVoiceClips│
│    │                 (separate AsyncStream)               │
│    │                       │                              │
│    │                       ▼                              │
│    │               VoiceClipPlayer                        │
│    │                 (AVAudioPlayer + session switching)   │
│    ▼                                                      │
│  NowPlayingView (button overlay)                          │
└──────────────────────┬────────────────────────────────────┘
                       │ WebSocket (single binary frame)
                       ▼
┌───────────────────────────────────────────────────────────┐
│ Server (index.js)                                         │
│                                                           │
│  ws.on("message") ──► Buffer.isBuffer(raw)?               │
│       │                                                   │
│       ├─ text: existing JSON.parse → handleMessage()      │
│       │                                                   │
│       └─ binary: read 4-byte header → parse JSON metadata │
│              → validate size ≤ 60KB, rate limit            │
│              → inject senderId + senderName                │
│              → repack and broadcastBinary to all           │
│                 members except sender                      │
└───────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Server — Voice Clip Relay

**Files:** `server/index.js`

- [x] Add binary frame detection in `ws.on("message")` — check `Buffer.isBuffer(raw)` **before** `JSON.parse`. Binary frames go to a new `handleVoiceClip()` function; text frames continue to the existing JSON path.
- [x] `handleVoiceClip(session, userId, raw)`:
  - Read first 4 bytes as uint32 → JSON metadata length
  - Slice and parse JSON metadata portion
  - Validate: `clipId` present, `durationMs` is finite and ≤ 10000, total frame ≤ 60KB
  - Rate limit: track `lastVoiceClipTime` per member, reject if < 15s since last clip. **Set rate limit timestamp on successful relay, not on receipt** — so failed sends don't consume the cooldown.
  - Inject `senderId` and `senderName` from the member registry (server-authoritative, not client-trusted)
  - Repack the frame with injected fields and broadcast
- [x] Add `broadcastBinaryToSession(session, buffer, excludeUserId)` helper — sends raw binary Buffer via `ws.send(buffer)` to all members except sender
- [x] Cap metadata string fields (`clipId` max 64 chars) to prevent oversized relay

**Tests:** `server/test.js`
- [x] Voice clip binary relay to other members (verify both metadata and audio data arrive correctly)
- [x] Sender exclusion (sender doesn't receive own clip)
- [x] Rate limiting (second clip within 15s rejected)
- [x] Oversized binary rejection (>60KB)
- [x] Binary frame without valid header (malformed) → ignored
- [ ] Concurrent clips from different members handled independently
- [ ] Member disconnect doesn't leave dangling state

### Phase 2: iOS — Record + Send

**New file:** `PirateRadio/Core/Audio/VoiceClipRecorder.swift`

- [x] `actor VoiceClipRecorder` — wraps `AVAudioRecorder`, records AAC/M4A to temp file
- [x] `startRecording()` — request mic permission (first time only), switch audio session to `.playAndRecord + .duckOthers + .defaultToSpeaker + .allowBluetoothA2DP`, start recording, enforce 10s max via Task timer
- [x] `stopRecording() -> Recording` — stop recorder, read file data, clean up temp file, deactivate session (`setActive(false, .notifyOthersOnDeactivation)`), restore to `.playback + .mixWithOthers`
- [x] Handle mic permission denied → throw `RecordingError.microphonePermissionDenied`
- [x] `struct Recording { let data: Data; let durationMs: Int }`

**Modified file:** `PirateRadio/Core/Networking/WebSocketTransport.swift`

- [x] Add `sendVoiceClip(clipId:durationMs:audioData:) async throws` — packs 4-byte header + JSON + audio into one binary frame, sends via `URLSessionWebSocketTask.send(.data(packed))`
- [x] No changes to `SyncMessage`, `SyncMessageType`, `translate()`, or `encodeForServer()` — voice clips are a parallel path

**Modified file:** `PirateRadio/Core/Protocols/SessionTransport.swift`

- [x] Add `sendVoiceClip(clipId:durationMs:audioData:) async throws` to `SessionTransport` protocol
- [x] Add stub to `MockSessionTransport`

**Modified file:** `PirateRadio/Resources/Info.plist`

- [x] Add `NSMicrophoneUsageDescription`: "Record voice clips to share with your crew"

### Phase 3: iOS — Receive + Play

**New file:** `PirateRadio/Core/Audio/VoiceClipPlayer.swift`

- [x] `@MainActor @Observable final class VoiceClipPlayer: NSObject, AVAudioPlayerDelegate`
- [x] `playClip(data: Data, senderName: String)` — switch audio session to `.playback + .duckOthers`, play AAC data via `AVAudioPlayer(data:)`, set delegate
- [x] `audioPlayerDidFinishPlaying` — deactivate session, restore `.playback + .mixWithOthers`, signal completion
- [x] If a clip is already playing when another arrives, drop the incoming one (simple; add queuing later if needed)
- [x] Expose `@Observable` state: `currentlyPlayingSender: String?` for the UI bubble

**Modified file:** `PirateRadio/Core/Networking/WebSocketTransport.swift`

- [x] In `handleReceivedMessage()`, when a `.data` message arrives that fails JSON decode: try reading as voice clip binary frame (4-byte header + JSON + audio)
- [x] Add `incomingVoiceClips: AsyncStream<IncomingVoiceClip>` — separate stream from `incomingMessages`, keeps SyncEngine untouched
- [x] Yield parsed voice clips to this stream

**Modified file:** `PirateRadio/Core/Sync/SessionStore.swift`

- [x] Add `voiceClipRecorder: VoiceClipRecorder` and `voiceClipPlayer: VoiceClipPlayer` properties
- [x] Subscribe to `transport.incomingVoiceClips` stream in `connectToStation()`
- [x] Add `startRecordingVoiceClip()` / `stopRecordingVoiceClip()` — use recorder, pack and send via transport
- [x] On incoming clip → forward to `VoiceClipPlayer`
- [x] Add `@Observable` state: `isRecordingVoiceClip: Bool`, `voiceClipCooldownActive: Bool`
- [x] Client-side 15s cooldown: disable PTT button after sending, show countdown. Server rate limit is the safety net, not the primary mechanism.

### Phase 4: iOS — Wire Up UI

**Modified file:** `PirateRadio/UI/Components/WalkieTalkieButton.swift`

- [x] Take `SessionStore` as `@Environment` dependency (wired up in `MegaphoneButton` instead — already in bottom bar)
- [x] Replace fake `startRecording()` with `sessionStore.startRecordingVoiceClip()`
- [x] Replace fake `stopRecording()` with `sessionStore.stopRecordingVoiceClip()`
- [x] Observe `sessionStore.voiceClipPlayer.currentlyPlayingSender` to show real incoming clip bubble
- [x] Observe `sessionStore.voiceClipCooldownActive` to disable PTT during cooldown
- [x] Keep existing UI: PTT gesture, waveform animation, progress ring, incoming bubble

**Modified file:** `PirateRadio/UI/NowPlaying/NowPlayingView.swift`

- [x] `MegaphoneButton` already in bottom bar — wired up with real SessionStore integration (no overlay needed)

## Acceptance Criteria

### Functional

- [ ] User can long-press the mic button to record up to 10 seconds of audio
- [ ] Recording auto-stops at 10 seconds
- [ ] On release, clip is sent to all other station members within ~500ms
- [ ] Receiving a clip ducks Spotify music and plays the voice audio
- [ ] Spotify volume restores after clip finishes playing
- [ ] Sender sees "Voice clip sent to crew!" toast
- [ ] Receiver sees incoming clip bubble with sender's name
- [ ] Rate limit: PTT button disabled for 15s after sending (with visible cooldown)
- [ ] Server rejects clips faster than 1 per 15s as safety net

### Non-Functional

- [ ] Clip latency (release-to-hear): < 500ms on typical connection
- [ ] Audio quality: clear voice at 32kbps AAC mono
- [ ] Works with AirPods / Bluetooth headphones
- [ ] Works when Spotify is not playing (clip still plays)
- [ ] Microphone permission requested on first PTT (not at app launch)

### Quality Gates

- [ ] Server tests pass: relay, sender exclusion, rate limit, size limit, malformed frame
- [ ] Wire protocol tests: voice clip binary frame pack/unpack round-trip (`WireProtocolTests.swift`)
- [ ] Manual test: record and receive on two devices

## Edge Cases

| Scenario | Behavior |
|---|---|
| Clip arrives while playing another | Drop incoming clip (simple; add queuing later if needed) |
| User sends while receiving | Allow — recording and playback use different audio session configs |
| Spotify not playing | Still play clip, audio session switch is harmless |
| AirPods / Bluetooth | `.allowBluetoothA2DP` routes mic + playback through AirPods |
| App backgrounded (sender) | PTT requires foreground — button isn't accessible |
| App backgrounded (receiver) | Clip plays via background audio mode |
| Network drops mid-send | Clip lost — single frame so it either arrives whole or not at all |
| Mic permission denied | Show toast, disable PTT button |
| Malformed binary frame | Server ignores; iOS ignores (fails header parse) |
| Recording → playingClip transition | Deactivate recording session first, then activate playingClip |

## Dependencies & Risks

- **AVAudioRecorder on simulator:** Recording won't work on the iOS Simulator — must test on device
- **Spotify SDK ducking behavior:** `.duckOthers` should duck Spotify via the system. If Spotify's own audio session fights back, we may need to use the Spotify SDK's volume control as a fallback.
- **Single binary frame atomicity:** WebSocket guarantees frames are delivered whole or not at all — no partial delivery concern.

## What We're NOT Building

- **AudioSessionManager abstraction** — inline audio session calls in recorder/player. Extract when speed-volume control gives us a second use case.
- **Clip queuing** — drop incoming clips if one is playing. Add queuing only if users report missed clips.
- **`format` field in protocol** — only AAC exists. Add when/if we support a second codec.
- **Voice clips in SyncMessage/SyncEngine** — parallel path via separate AsyncStream. Keeps the sync protocol clean.

## References

- Existing UI: `PirateRadio/UI/Components/WalkieTalkieButton.swift` (fake implementation)
- WebSocket transport: `PirateRadio/Core/Networking/WebSocketTransport.swift`
- Message types: `PirateRadio/Core/Protocols/SessionTransport.swift:22`
- SessionStore: `PirateRadio/Core/Sync/SessionStore.swift`
- Server message handling: `server/index.js:445`
- Server broadcast helper: `server/index.js:788`
- Audio session setup: `PirateRadio/App/AppDelegate.swift:29`
- Speed-volume spec: `.context/speed-volume-control-spec.md` (atlanta workspace)
- Exploration doc: `.context/walkie-talkie-exploration.md`
