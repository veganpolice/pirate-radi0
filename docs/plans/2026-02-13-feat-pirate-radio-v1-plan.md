---
title: "feat: Pirate Radio v1 — Synchronized Group Listening for iOS"
type: feat
date: 2026-02-13
deepened: 2026-02-13
---

# Pirate Radio v1 — Synchronized Group Listening for iOS

## Enhancement Summary

**Deepened on:** 2026-02-13
**Research agents used:** Architecture Strategist, Performance Oracle, Security Sentinel, Simplicity Reviewer, Pattern Recognition Specialist, Race Condition Reviewer, + 3 domain-specific researchers

### Key Improvements
1. **Scope reduction for MVP:** Ship Solo DJ only, cut to 3 phases, validate sync before adding features
2. **Sync engine hardened:** Two-phase prepare/commit, NTP-anchored positions, playback rate adjustment (not seek) for drift, per-device latency calibration
3. **Race conditions mitigated:** Epoch numbering, monotonic sequence numbers, nonces for idempotency, message ordering buffer, Spotify SDK state machine wrapper
4. **Security architecture defined:** Keychain token storage, JWT-based backend auth, WebSocket authentication, session access control with rotatable join codes
5. **Background execution de-risked:** Silent audio session prototype moved to Phase 1
6. **UI hero moment identified:** Frequency-dial "tuning" interaction for session join — the moment that sells the app

### Critical Corrections from Original Plan
- **500ms lead time is insufficient.** Spotify `play()` latency is 150-800ms. Increased to 1500-2000ms.
- **Seek-based drift correction causes audible glitches.** Use playback rate adjustment (1.01x/0.99x) for drift <500ms.
- **Token refresh is not Phase 6.** OAuth tokens expire in 1 hour. This is Phase 1 or the app breaks during any normal session.
- **Background execution must be validated in Phase 1.** iOS suspends backgrounded apps within seconds. Without a silent audio session trick, the sync engine dies when the screen locks.
- **Custom ping-pong protocol is unnecessary.** Kronos alone achieves 10-50ms, well within the 300ms sync target.

---

## Overview

Pirate Radio is an iOS app that lets a crew of skiers/snowboarders listen to the same music in sync through their own earbuds. One person DJs from Spotify while everyone hears the same track at the same time. Wrapped in a retro-pirate-radio-meets-neon-ski-lodge aesthetic with glove-friendly controls.

## Architecture Pivot from Brainstorm

The brainstorm chose "Pirate Stream" (DJ relays audio to listeners). **This violates Spotify's Developer Policy**, which explicitly prohibits streaming from one source to multiple listeners. The architecture must be **Coordinated Playback**: each user authenticates with their own Spotify Premium account and streams independently; the app synchronizes what plays and when across all devices.

This is architecturally simpler (no audio encoding/relaying) but sync precision is bounded by Spotify's API response times (~150-800ms). Research shows NTP-based clock sync can achieve 10-50ms precision over cellular, so the total sync gap will be roughly **200-400ms** — noticeable if standing next to someone, but acceptable when spread across a mountain.

**Tradeoff accepted:** Every listener needs Spotify Premium. This is a real limitation, but it's the only compliant path. The v2 roadmap adds direct audio sources (uploaded tracks, SoundCloud) where we own the pipeline for tighter sync.

## Technical Approach

### System Architecture

```
┌─────────────────────────────────────────────┐
│             Pirate Radio Backend             │
│                (Node.js)                     │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Session   │  │ Sync     │  │ Message   │  │
│  │ Manager   │  │ Clock    │  │ Relay     │  │
│  └──────────┘  └──────────┘  └───────────┘  │
│         WebSocket (WSS) connections          │
└──────────┬──────────┬──────────┬────────────┘
           │          │          │
     ┌─────┴──┐ ┌─────┴──┐ ┌────┴───┐
     │ DJ     │ │Listener│ │Listener│
     │ iPhone │ │ iPhone │ │ iPhone │
     │        │ │        │ │        │
     │Spotify │ │Spotify │ │Spotify │
     │  App   │ │  App   │ │  App   │
     └────────┘ └────────┘ └────────┘
```

**Each device:**
- Runs Pirate Radio app + Spotify app in background
- Authenticates with own Spotify Premium account
- Streams audio from Spotify's CDN independently
- Connects to backend via authenticated WSS for coordination

**Backend (lightweight Node.js coordinator):**
- Manages sessions (create, join, leave)
- Broadcasts timestamped sync commands
- Manages the shared queue and DJ state
- Serves as NTP-like clock reference via ping-pong protocol
- Issues its own JWTs for authentication (Spotify tokens never leave devices)

### Research Insights: Backend Choice

**Decision: Node.js over Vapor.**
- The backend is ~100-200 lines of WebSocket relay code. Vapor adds Swift-on-server complexity (Linux toolchain, Docker, Vapor-specific abstractions) for zero user-facing benefit.
- Node.js with `ws` + `express` deploys to Fly.io in minutes.
- A single Fly.io instance handles thousands of WebSocket connections. For sessions of 2-10 devices, this handles hundreds of concurrent sessions.
- In-memory session state is correct at this scale. Skip Redis.

**Fly.io configuration:**
```toml
[services.concurrency]
  type = "connections"
  hard_limit = 2000
  soft_limit = 1500
```

### Sync Engine Design

#### Two-Phase Coordinated Playback

```
Phase 1: PREPARE
  Server → All: { type: "prepare_play", seq: 47, trackId: "spotify:track:xxx",
                   prepareDeadline: ntpNow() + 2000 }
  Devices: preload track via Spotify SDK, warm connection, respond ACK/NACK

Phase 2: COMMIT (after quorum ACKs)
  Server → All: { type: "commit_play", seq: 48, refSeq: 47,
                   startAtNtp: ntpNow() + 1500 }
  Devices: schedule playback at exact NTP-aligned local time
  Late devices: IGNORE commit, request full state resync instead
```

**Why two-phase:** The original plan used a simple "play at time T" with 500ms lead time. Research shows Spotify's `play()` latency ranges 150-800ms (cache-dependent). 500ms is insufficient. The prepare phase pre-warms the track, and the 1500ms commit lead time absorbs worst-case latency.

#### Clock Sync

- **Kronos only.** The original plan added a custom ping-pong protocol on top. This is unnecessary — Kronos achieves 10-50ms over cellular, well within the 300ms target. The custom protocol saves ~10-20ms, which Spotify's own jitter swamps.
- Re-sync on network change: listen for `NWPathMonitor` events, trigger fresh Kronos burst (5-8 samples over 2-3s).
- Statistical filtering: take 10+ samples, discard outliers beyond 1.5x IQR, use median.

#### Drift Correction (Three-Tier)

```
Tier 1: IGNORE    (drift < 50ms)   — inaudible, do nothing
Tier 2: RATE ADJ  (50ms-500ms)     — play at 1.02x or 0.98x to converge gradually
Tier 3: HARD SEEK (drift > 500ms)  — unavoidable, will cause brief audio glitch
```

**Why not just seek?** Seek on Spotify SDK flushes the audio buffer, causing a 50-200ms audible glitch. With 30s drift checks on 10 devices, the group would hear multiple glitches per minute. Playback rate adjustment is inaudible.

**Cooldown:** After any correction, ignore drift reports for 500ms to prevent feedback loops.

**Adaptive frequency:** 5s intervals for first minute (drift most likely), relaxing to 15s once stable (3 consecutive checks <50ms drift).

#### Per-Device Latency Calibration

During first few play commands in a session, measure delta between `play()` call and Spotify SDK's `playerStateDidChange` callback. Store as per-device offset. Factor into sync calculations. This is the single highest-impact optimization for sync quality.

#### NTP-Anchored Positions (Never Send Absolute)

All position data uses NTP anchors so it never goes stale in transit:

```swift
struct NTPAnchoredPosition: Codable {
    let trackId: String
    let positionAtAnchor: Double    // seconds
    let ntpAnchor: UInt64           // NTP timestamp in ms
    let playbackRate: Double        // 0.0 = paused, 1.0 = normal

    func positionAt(ntpTime: UInt64) -> Double {
        let elapsed = Double(ntpTime - ntpAnchor) / 1000.0
        return positionAtAnchor + (elapsed * playbackRate)
    }
}
```

### Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| iOS minimum | iOS 17+ | Required for `@Observable`, Metal shaders in SwiftUI, `.sensoryFeedback` |
| Architecture | MVVM + `@Observable` + shared `SessionStore` | Native, lightweight; shared store prevents cross-feature state fragmentation |
| Audio control | SpotifyiOS SDK (App Remote) | Controls playback in Spotify app |
| Track search/metadata | Spotify Web API | Full catalog access, search, playlists |
| Backend | Node.js with `ws` + `express` | Simplest path; ~200 lines of code; deploys in minutes |
| Clock sync | Kronos only | Achieves 10-50ms; custom ping-pong unnecessary for 300ms target |
| Real-time comms | WebSocket (WSS only) | Low overhead, bidirectional, TLS enforced |
| Dependencies | SPM only | CocoaPods is legacy in 2026 |
| Auth tokens | iOS Keychain | `kSecAttrAccessibleAfterFirstUnlock` for background refresh |
| Backend auth | JWT (Pirate Radio-issued) | Spotify tokens never leave device |

### Core Protocols (Define in Phase 1)

```swift
// Abstracts Spotify for testability and future music sources
protocol MusicSource: Sendable {
    func play(trackID: String, at position: Duration) async throws
    func pause() async throws
    func seek(to position: Duration) async throws
    func currentPosition() async throws -> Duration
    var playbackStateStream: AsyncStream<PlaybackState> { get }
}

// Abstracts WebSocket for testability and future P2P transport
protocol SessionTransport: Sendable {
    func connect(to session: SessionID) async throws
    func disconnect() async
    func send(_ message: SyncMessage) async throws
    var incomingMessages: AsyncStream<SyncMessage> { get }
    var connectionState: AsyncStream<ConnectionState> { get }
}

// Abstracts NTP clock for deterministic testing
protocol ClockProvider: Sendable {
    func now() -> UInt64  // NTP-synchronized millisecond timestamp
    var estimatedOffset: Duration { get }
}
```

### Race Condition Defenses (Built Into Protocol)

Every message in the system carries:

```swift
struct SyncCommand: Codable, Sendable, Identifiable {
    let id: UUID                    // Deduplication key
    let type: CommandType
    let executionTime: UInt64       // NTP timestamp
    let issuedBy: UserID
    let sequenceNumber: UInt64      // Monotonic, for ordering
    let epoch: UInt64               // Mode/authority epoch — reject stale commands
}
```

| Pattern | Purpose | Used In |
|---------|---------|---------|
| NTP-anchored positions | Positions never go stale | Play, seek, join-mid-song |
| Epoch numbers | Reject commands from expired DJ regimes | Mode transitions, reconnect |
| Monotonic sequence numbers | Detect gaps, order messages, deduplicate | All server→client messages |
| Nonces for idempotency | Safe retransmission of mutations | Queue votes, track adds |
| Two-phase prepare/commit | Absorb variable latency | Coordinated play start |
| Dead zones + cooldowns | Prevent feedback loops | Drift correction |

### Spotify SDK Wrapper (State Machine)

The Spotify SDK has unpredictable callback timing. Wrap it in a state machine:

```
IDLE → PREPARING → WAITING_FOR_CALLBACK → PLAYING → IDLE
```

Rules:
- No SDK call while PREPARING or WAITING_FOR_CALLBACK
- 3-second timeout on WAITING_FOR_CALLBACK
- All transitions serialized through a single dispatch queue
- Never report "playing" to server until callback confirms
- Maximum 1 queued pending command

### State Management Architecture

```
WebSocket (raw bytes)
    ↓
SessionTransport (decodes to SyncMessage, emits AsyncStream)
    ↓
SyncEngine (actor, processes messages, schedules playback)
    ↓  (@MainActor dispatch)
SessionStore (@Observable, single source of truth)
    ↓  (SwiftUI observation tracking)
Views (NowPlayingView, QueueView, etc.)
```

`SessionStore` is `@Observable @MainActor` — the single source of truth for all session state. Feature ViewModels are thin projections that read from it. Only `SyncEngine` and explicit user actions write to it.

### Project Structure

```
PirateRadio/
├── App/
│   ├── PirateRadioApp.swift          # Entry point
│   └── AppDelegate.swift             # Spotify SDK setup, silent audio session
├── Features/
│   ├── Auth/
│   │   ├── SpotifyAuthView.swift     # Login screen
│   │   └── SpotifyAuthViewModel.swift
│   ├── Session/
│   │   ├── CreateSessionView.swift   # Generate session code
│   │   ├── JoinSessionView.swift     # Enter code / "tune in" dial
│   │   └── SessionViewModel.swift
│   └── NowPlaying/
│       ├── NowPlayingView.swift      # Main playback screen
│       ├── NowPlayingViewModel.swift
│       ├── DJControlsView.swift      # DJ-specific controls
│       ├── QueueView.swift           # Track queue
│       └── ListenerView.swift        # Listener-mode controls
├── Core/
│   ├── Protocols/
│   │   ├── MusicSource.swift         # Abstract music playback
│   │   ├── SessionTransport.swift    # Abstract real-time transport
│   │   └── ClockProvider.swift       # Abstract NTP clock
│   ├── Sync/
│   │   └── SyncEngine.swift          # Actor: clock sync + playback coordination + drift
│   ├── Spotify/
│   │   ├── SpotifyClient.swift       # Web API client (search, metadata)
│   │   ├── SpotifyPlayer.swift       # iOS SDK wrapper (state machine, conforms to MusicSource)
│   │   └── SpotifyAuth.swift         # OAuth/PKCE + Keychain token storage + refresh
│   ├── Networking/
│   │   └── WebSocketTransport.swift  # WSS client (conforms to SessionTransport)
│   └── Models/
│       ├── Session.swift
│       ├── Track.swift
│       ├── SyncCommand.swift         # Timestamped, sequenced, epoched commands
│       └── PirateRadioError.swift    # Structured error hierarchy
├── UI/
│   ├── Theme/
│   │   ├── PirateTheme.swift         # Colors, fonts, semantic palette
│   │   └── GloveButton.swift         # Large touch-target button (60pt+)
│   └── Components/
│       ├── NeonGlow.swift            # Triple-layered shadow glow modifier
│       └── FrequencyDial.swift       # Rotary dial with haptic detents
└── Resources/
    ├── Assets.xcassets
    ├── Fonts/                        # Bundled: Share Tech Mono, Dela Gothic One
    └── Localizable.xcstrings

pirate-radio-backend/                  # Node.js project
├── index.js                          # Single file: express + ws + session state
├── package.json
└── fly.toml
```

### Research Insights: Simplified File Structure

The original plan had 25+ source files. Reduced to ~15 for MVP:
- Merged `ClockSync.swift` and `DriftCorrector.swift` into `SyncEngine.swift` (Kronos call is one line; drift logic is a value type inside the actor)
- Merged `WebSocketClient.swift` and `SessionAPI.swift` into `WebSocketTransport.swift`
- Added `Core/Protocols/` for the three critical abstractions
- Added `SyncCommand.swift` and `PirateRadioError.swift` as explicit model types
- Removed `Settings/` for MVP
- Backend reduced from 4 files to 1 (`index.js`)

## Implementation Phases

### Phase 1: Foundation + Platform Validation

**Goal:** Spotify auth works, playback control works, background execution validated. These are the three platform risks that could block everything.

- [x] Create Xcode project with SwiftUI, iOS 17+ target — `PirateRadioApp.swift`
- [x] Set up SPM dependencies: SpotifyiOS SDK, Kronos
- [x] Define `MusicSource`, `SessionTransport`, `ClockProvider` protocols — `Core/Protocols/`
- [x] Implement Spotify OAuth/PKCE flow with Keychain token storage — `SpotifyAuth.swift`
  - Use `SecRandomCopyBytes` for PKCE `code_verifier` (43-128 chars, cryptographically random)
  - Store access + refresh tokens in iOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`)
  - Implement proactive token refresh at 80% of expiry (not on 401 error)
  - Universal Link for redirect URI (not custom URL scheme — prevents interception)
- [x] Verify Premium status at login via Web API `GET /v1/me` → `product == "premium"` — `SpotifyAuth.swift`
- [x] Build login screen with clear Premium requirement messaging — `SpotifyAuthView.swift`
- [x] Wrap SpotifyiOS App Remote as state machine — `SpotifyPlayer.swift`
  - States: IDLE → PREPARING → WAITING_FOR_CALLBACK → PLAYING
  - 3-second timeout on WAITING_FOR_CALLBACK
  - Serialized through single dispatch queue
  - Measure play() → callback latency for sync calibration
- [x] Wrap Spotify Web API for track search — `SpotifyClient.swift`
- [x] **CRITICAL: Prototype background execution** — `AppDelegate.swift`
  - Configure `AVAudioSession` with `.playback` category
  - Test: does the app stay alive when screen locks while Spotify plays?
  - If not: implement silent audio session (play inaudible audio to maintain background privilege)
  - This must work or the sync engine dies when the screen locks
- [x] Handle error states: Spotify not installed, not logged in, not Premium — `PirateRadioError.swift`
- [ ] Verify: user can log in, search, play, and app stays alive when backgrounded

**Success criteria:** Single device works end-to-end. Background execution confirmed. Token refresh works. These are the make-or-break validations.

### Phase 2: Backend + Sync Engine

**Goal:** Two devices play the same track at approximately the same time.

- [x] Set up Node.js backend (`index.js`): express + ws + in-memory session state
- [x] Implement JWT authentication: client proves Spotify identity → backend issues short-lived JWT → JWT required for WebSocket upgrade
- [x] Session CRUD: create (returns 4-digit code), join (validate code + JWT), leave
  - Session IDs: UUID v4 (unguessable)
  - Join codes: 4-digit numeric, rotatable, expire after 1 hour
  - Max 10 members per session
- [x] WebSocket connection management: authenticated upgrade, 15-20s ping interval, 5s timeout for disconnect detection
- [x] Implement Kronos clock sync on device — `SyncEngine.swift`
- [x] Implement two-phase coordinated play (prepare/commit with 1500ms lead time)
- [x] Implement NTP-anchored position model for all sync messages
- [x] Implement message ordering: monotonic sequence numbers, epoch validation
- [x] Implement per-device Spotify latency calibration (measure first 3 play commands)
- [x] Implement three-tier drift correction (ignore / rate adjust / hard seek)
  - Adaptive frequency: 5s for first minute, 15s once stable
  - 500ms cooldown after any correction
- [x] Implement coordinated pause/resume/skip with timestamped commands
- [x] Handle join-mid-song: backend sends NTP-anchored current position, device computes and seeks
- [x] Implement reconnection state machine: CONNECTED → RECONNECTING → DISCONNECTED → RESYNCING
  - Exponential backoff: 0.5s, 1s, 2s, 4s, 8s, cap 15s
  - On reconnect: send `{lastSeenSeq, lastSeenEpoch}`, server replies with delta or full sync
  - During disconnect: continue playing current track without sync (graceful degradation)
- [x] Build session create UI (displays 4-digit code) — `CreateSessionView.swift`
- [x] Build session join UI (enter code) — `JoinSessionView.swift`
- [ ] Deploy backend to Fly.io
- [x] Rate limit: 5 sessions/user/hour, 10 join attempts/IP/min
- [ ] Verify: two devices play same track within ~300ms over cellular

**Success criteria:** Multi-device sync works. Reconnection recovers gracefully. This validates the entire product hypothesis.

### Phase 3: DJ + Queue + UI + Ship

**Goal:** Solo DJ mode works, app looks and feels like Pirate Radio, ready for TestFlight.

- [ ] **Solo DJ mode:** DJ has playback control (play, pause, skip, queue tracks). Listeners see what's playing, can request songs via queue. — `DJControlsView.swift`, `ListenerView.swift`, `QueueView.swift`
  - Backend-authoritative queue: clients send mutation requests, server broadcasts canonical state
  - Queue add operations use nonces for idempotent retransmission
  - Handle DJ disconnect: auto-promote next member
- [ ] **Design system** — `PirateTheme.swift`
  - Semantic color palette: `signal` (cyan #00FFE0), `broadcast` (magenta #FF00FF), `flare` (amber #FFB800), `void` (#0D0D0D)
  - Cyan = primary/active/connected, Magenta = DJ/authority, Amber = alerts/warmth
  - Never two neon colors at equal weight in same view
  - Bundle custom fonts: Share Tech Mono (numbers/body), Dela Gothic One (display/headers)
- [ ] **Neon glow modifier** — `NeonGlow.swift`
  - Triple-layered shadows: tight core (radius 2, 0.9 opacity) + medium (radius 8, 0.4) + wide ambient (radius 20, 0.15)
  - Optional subtle flicker (random ±5% opacity every 2-5s for 100ms)
- [ ] **Glove-friendly buttons** — `GloveButton.swift`
  - 60pt+ touch targets, neon border style, press-to-fill animation
  - `.sensoryFeedback(.impact(.medium), trigger:)` on all taps
- [ ] **Frequency dial** — `FrequencyDial.swift` (volume control, hero component)
  - DragGesture → angle calculation, tick marks, neon indicator line
  - Haptic detents at 0/25/50/75/100%
  - Physical inertia on release (deceleration animation)
- [ ] **Now Playing screen** — `NowPlayingView.swift`
  - Asymmetric layout: album art upper-left at 60% width, track title overlapping in neon
  - Crew list as horizontal strip with role-colored avatar rings (cyan = listener, magenta = DJ)
  - Staggered entrance animation: art → title → controls → crew
- [ ] **Session join "tuning" interaction** — `JoinSessionView.swift`
  - This is the hero moment: rotate frequency dial through static to "find" the station
  - CRT static overlay fades as user dials toward session frequency
  - Snap haptic on lock, static dissolves, album art blooms through
  - Session code maps to displayed frequency (e.g., code 1073 = "107.3 FM")
- [ ] Lock screen / Dynamic Island via `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`
- [ ] Haptic feedback on all controls
- [ ] Onboarding: first-launch flow explaining Spotify Premium requirement
- [ ] Session idle timeout: 30 minutes of no playback
- [ ] Battery: reduce drift checks to 60s when backgrounded, clock sync to 5min
- [ ] TestFlight build, test on actual ski mountain with 3+ devices

**Success criteria:** App is fun to use, distinctive-looking, and reliable on the mountain.

## Acceptance Criteria

### Functional Requirements

- [ ] Users authenticate with their own Spotify Premium account (Premium verified at login)
- [ ] Users create a session (4-digit code) and share code with friends
- [ ] Users join a session by entering the code
- [ ] All session members hear the same track within ~300ms of each other
- [ ] Solo DJ mode: one user controls playback, others listen and can request songs
- [ ] Play, pause, skip, and volume controls work and sync across devices
- [ ] Session recovers when members temporarily lose connectivity
- [ ] New members can join mid-song and sync to current position

### Non-Functional Requirements

- [ ] Sync precision: <400ms between any two devices in a session
- [ ] Session supports 2-10 concurrent listeners
- [ ] App launch to playback: <30 seconds (returning users with saved auth)
- [ ] All touch targets: minimum 60pt (glove-friendly)
- [ ] Battery: <15% drain per hour (passive listener, screen off); <25% (active DJ)
- [ ] Works on cellular (no WiFi dependency)

### Quality Gates

- [ ] Unit tests for SyncEngine (with mock ClockProvider, MusicSource, SessionTransport)
- [ ] Unit tests for Spotify SDK state machine wrapper
- [ ] Unit tests for DJ state transitions (pure function)
- [ ] Integration test: two simulated devices sync playback
- [ ] Manual test on actual ski mountain with 3+ devices

## Security Architecture

### Authentication Flow

```
1. Client authenticates with Spotify via PKCE (tokens stored in iOS Keychain)
2. Client sends Spotify user ID to Pirate Radio backend
3. Backend verifies identity, issues short-lived JWT (15 min, auto-refresh)
4. All REST and WebSocket requests carry Pirate Radio JWT
5. Spotify tokens NEVER leave the device
```

### Session Access Control

- Session IDs: UUID v4 (128-bit random, unguessable)
- Join codes: 4-digit numeric, rotatable by session creator, expire after 1 hour
- Session creator can kick members and regenerate join code
- All members notified when someone joins

### Message Security

- WSS only (TLS enforced, no ATS exceptions)
- Every WebSocket message validated against strict Codable schema server-side
- Role-based authorization: only DJ can send play/pause/skip; listeners can only queue/vote
- Rate limiting: max 10 messages/second per WebSocket connection
- All user inputs validated and length-limited

### Security Checklist

- [ ] Tokens in Keychain (`kSecAttrAccessibleAfterFirstUnlock`), not UserDefaults
- [ ] PKCE `code_verifier` via `SecRandomCopyBytes` (min 43 chars)
- [ ] Universal Link for OAuth redirect (not custom URL scheme)
- [ ] Spotify tokens never sent to backend
- [ ] Backend issues its own JWTs
- [ ] WSS enforced, no plaintext WebSocket
- [ ] Message schema validation + role-based authorization on server
- [ ] Rate limiting on session creation, join attempts, WebSocket messages
- [ ] Validate track IDs match Spotify's base-62 format (`^[a-zA-Z0-9]{22}$`)
- [ ] Privacy policy before App Store submission
- [ ] Observer mode for non-Premium users (see queue, no audio)

## Dependencies & Prerequisites

- **Spotify Developer Account** — register app, get client ID, configure redirect URI. **Apply for Extended Quota Mode on day one** (approval timeline is unpredictable and blocks testing beyond 5 users).
- **Spotify Premium accounts** — minimum 2-3 for testing
- **Backend hosting** — Fly.io (Node.js, single instance sufficient for v1)
- **Apple Developer Account** — for TestFlight distribution
- **Physical iPhones** — sync testing requires real devices (simulator won't run Spotify)
- **Domain for Universal Links** — AASA file hosting for OAuth redirect + session join links (post-MVP)
- **Custom fonts** — Bundle Share Tech Mono, Dela Gothic One in Resources/

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Spotify `play()` latency varies 150-800ms | High | High | Two-phase prepare/commit + per-device latency calibration + 1500ms lead time |
| iOS kills backgrounded app → sync dies | High | Critical | **Validate in Phase 1.** Silent audio session to maintain background privilege |
| Sync precision >500ms feels bad | Medium | High | Three-tier drift correction (rate adjust, not seek). Playback rate 1.02x/0.98x is inaudible |
| Spotify changes API/ToS | Low | Critical | Abstract behind `MusicSource` protocol; v2 adds non-Spotify sources |
| Dev Mode limited to 5 test users | High | Medium | Apply for Extended Quota Mode immediately; MVP designed for small crews anyway |
| Mountain cell service unreliable | Medium | High | Reconnection state machine, graceful degradation (continue playing without sync), honest "Signal Lost" UI |
| Race conditions in multi-device sync | Medium | High | Epoch numbering, sequence numbers, nonces, two-phase commits, message ordering buffer |
| Session hijacking via join code | Low | Medium | Short-lived codes, rotatable, creator can kick, JWT-authenticated WebSocket |

## Open Questions (Resolved)

| Original Question | Resolution |
|---|---|
| Vapor vs Node.js? | **Node.js.** ~200 lines of code; Vapor adds unnecessary toolchain complexity for a relay server. |
| Hosting? | **Fly.io.** Good WebSocket support, handles 2000+ concurrent connections per instance. |
| QR code format? | **4-digit code for MVP.** QR/deep links are post-MVP. Code 1073 displays as "107.3 FM" in the tuning UI. |
| When to apply for Extended Quota? | **Day one.** It's on the critical path for testing beyond 5 users. Approval timeline is unpredictable. |
| Custom ping-pong needed? | **No.** Kronos alone achieves 10-50ms, sufficient for the 300ms sync target. |

## Open Questions (Remaining)

1. **Silent audio session legality:** Is playing inaudible audio to maintain background execution acceptable for App Store review? Research suggests yes (common pattern), but should be tested.
2. **Spotify SDK background reliability:** How reliably does the Spotify app respond to App Remote commands when backgrounded? Needs empirical testing in Phase 1.
3. **Playback rate adjustment API:** Does SpotifyiOS SDK support `setPlaybackRate`? If not, the rate-adjustment drift correction tier falls back to seek-only with longer cooldowns.

## Future Considerations (Post-V1)

**V1.5 — Additional DJ Modes:**
- Collaborative Queue (anyone adds, voting determines order)
- Hot-Seat Rotation (auto-rotate DJ after N songs)
- Formal DJ state machine: pure `transition(state:event:members:)` function

**V2 — Own the Audio Pipeline:**
- Add direct upload / SoundCloud sources for tighter sync (<40ms)
- Opus codec for low-latency audio relay between devices
- Multipeer Connectivity for P2P fallback (no server needed)

**V2+ — Mountain Features:**
- Chairlift DJ mode (auto-detect via proximity + low speed)
- Adaptive BPM (music energy matches riding speed via accelerometer/GPS)
- Walkie-talkie voice clips over music
- Crew discovery / mountain social (tune into other crews, song battles)
- QR code / Universal Link session sharing
- Android / cross-platform

## References

### Research Sources
- [Spotify iOS SDK](https://developer.spotify.com/documentation/ios) — v5.0.1, App Remote control
- [Spotify Developer Policy](https://developer.spotify.com/policy) — prohibits one-to-many streaming
- [Spotify Web API](https://developer.spotify.com/documentation/web-api) — search, metadata, playback
- [Kronos NTP Library](https://github.com/MobileNativeFoundation/Kronos) — sub-second iOS clock sync
- [Inferno Metal Shaders](https://github.com/twostraws/Inferno) — CRT/noise effects for SwiftUI
- [Vapor WebSocket Docs](https://docs.vapor.codes/advanced/websockets/) — reference if switching from Node
- [Fly.io WebSocket Limits](https://community.fly.io/t/is-there-a-concurrent-websocket-connections-limit/3229)
- [AVAudioSession Background Modes](https://developer.apple.com/documentation/avfaudio/avaudiosession)

### Brainstorm
- [Pirate Radio Brainstorm](/docs/brainstorms/2026-02-13-pirate-radio-brainstorm.md)
