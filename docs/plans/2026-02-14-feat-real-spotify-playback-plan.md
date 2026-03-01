---
title: "feat: Enable real Spotify playback for on-device testing"
type: feat
date: 2026-02-14
---

# Enable Real Spotify Playback for On-Device Testing

## Overview

Take the app out of demo mode and wire up real Spotify playback via SPTAppRemote so the app can be deployed to a physical iPhone via USB and play actual music. No Apple Developer Program ($99) needed — a free Apple ID works for USB deployment (apps expire after 7 days, just rebuild).

## Problem Statement

The app runs entirely in demo mode (`PirateRadioApp.demoMode = true`). The Spotify PKCE auth flow is fully implemented, but `SpotifyPlayer.swift` has 4 TODO stubs where actual SDK calls should go. The Spotify iOS SDK (`SpotifyiOS` 5.0.1) is already a package dependency but never imported.

## What Already Works

- PKCE OAuth via ASWebAuthenticationSession (`SpotifyAuth.swift`)
- Keychain token storage + refresh
- Web API client for search/metadata (`SpotifyClient.swift`)
- Player state machine with latency tracking (`SpotifyPlayer.swift`)
- Audio session configured for background playback (`AppDelegate.swift`)
- URL scheme `pirate-radio://` registered in Info.plist
- Backend live at `pirate-radio-sync.fly.dev`

## What Needs to Change

### Phase 1: Wire Up SPTAppRemote (Core Work)

#### 1.1 Disable demo mode
**File:** `PirateRadio/App/PirateRadioApp.swift:12`
```swift
static let demoMode = false
```

#### 1.2 Add `app-remote-control` scope
**File:** `PirateRadio/Core/Spotify/SpotifyAuth.swift:18-24`
```swift
static let scopes = [
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
    "user-read-private",
    "streaming",
    "app-remote-control",  // NEW — required for SPTAppRemote
].joined(separator: " ")
```

#### 1.3 Create and manage SPTAppRemote instance
**File:** `PirateRadio/Core/Spotify/SpotifyAuth.swift`

Add to SpotifyAuthManager:
- `import SpotifyiOS`
- Lazy `SPTAppRemote` property configured with clientID + redirectURL
- `connectAppRemote()` — sets access token on connection params, calls `connect()`
- `disconnectAppRemote()` — calls `disconnect()` if connected
- `isConnectedToSpotifyApp: Bool` published state
- Conform to `SPTAppRemoteDelegate` (connection success/failure/disconnect callbacks)

Key detail: SPTAppRemote can reuse the PKCE access token — just set `appRemote.connectionParameters.accessToken = existingToken`.

#### 1.4 Implement SpotifyPlayer SDK calls
**File:** `PirateRadio/Core/Spotify/SpotifyPlayer.swift`

Replace 4 TODOs with actual calls:

| Line | Current | Replace With |
|------|---------|-------------|
| 58 | `// TODO: pause` | `appRemote.playerAPI?.pause(nil)` |
| 69 | `// TODO: seek` | `appRemote.playerAPI?.seekToPosition(Int(position.seconds * 1000), callback: nil)` |
| 73 | `// TODO: currentPosition` | `appRemote.playerAPI?.getPlayerState { ... }` |
| 124-126 | `// TODO: play + seek` | `appRemote.playerAPI?.play("spotify:track:\(trackID)", callback: ...)` then seek |

Also:
- `import SpotifyiOS`
- Accept `SPTAppRemote` reference (inject from SpotifyAuthManager)
- Conform to `SPTAppRemotePlayerStateDelegate`
- Wire `playerStateDidChange(_:)` to call existing `didStartPlayback(trackID:)`

#### 1.5 Add URL callback handler
**File:** `PirateRadio/App/AppDelegate.swift`

Add `application(_:open:options:)` to handle `pirate-radio://auth/callback` deep links — forward to SpotifyAuthManager and SPTAppRemote's `authorizationParameters(from:)`.

#### 1.6 Add lifecycle management
**File:** `PirateRadio/App/PirateRadioApp.swift`

- On `scenePhase == .active`: call `authManager.connectAppRemote()` if authenticated
- On `scenePhase == .background`: call `authManager.disconnectAppRemote()`

SPTAppRemote drops connection after ~30s of no playback — reconnect on foreground.

### Phase 2: Non-Demo Session Flow

#### 2.1 Create a real session when auth completes
**File:** `PirateRadio/App/PirateRadioApp.swift`

When `demoMode = false` and auth succeeds:
- Create a `SessionStore` with the real SpotifyPlayer (not mock data)
- The existing `.onChange(of: authManager.isAuthenticated)` handler already does this (lines 34-41)
- Verify it creates a proper session with the user as DJ

#### 2.2 Wire "Create Session" to start playback
**File:** `PirateRadio/UI/Session/CreateSessionView.swift`

When DJ creates a session and picks a track:
- Call `sessionStore.play(track:)` which routes to `SpotifyPlayer.play()`
- This triggers SPTAppRemote to play on the Spotify app

#### 2.3 Add "Spotify not installed" fallback
If `UIApplication.shared.canOpenURL(URL(string: "spotify://")!)` returns false:
- Show an alert directing to App Store
- Deep link: `itms-apps://itunes.apple.com/app/id324684580`

### Phase 3: Build & Deploy to Device

#### 3.1 Set development team
**File:** `project.yml:31` (currently `DEVELOPMENT_TEAM: ""`)

Either:
- Set your Apple ID team in project.yml and run `xcodegen generate`
- Or set it manually in Xcode: Target → Signing & Capabilities → Team → your Apple ID

A **free Apple ID** works. No $99 developer program needed for USB deployment.

#### 3.2 Build and run on device
```bash
xcodegen generate
open PirateRadio.xcodeproj
# In Xcode: select your iPhone, Cmd+R
```

First time: trust developer cert on iPhone (Settings → General → VPN & Device Management).

## Prerequisites on Device

- [ ] Spotify app installed from App Store
- [ ] Logged into Spotify with Premium account
- [ ] iPhone connected via USB cable
- [ ] Developer certificate trusted (first run only)

## Acceptance Criteria

- [ ] App launches on physical iPhone (not simulator) — requires setting DEVELOPMENT_TEAM
- [x] Spotify OAuth login flow completes (PKCE, opens Safari) — already implemented
- [x] SPTAppRemote connects to Spotify app — wired in SpotifyAuth + lifecycle
- [x] Tapping play on a track plays real audio through Spotify — SDK calls wired
- [x] Pause, seek, and skip work — SDK calls wired
- [ ] Track metadata (name, artist, album art) displays correctly — needs on-device testing
- [x] App reconnects to Spotify when returning from background — scenePhase lifecycle

## Key Gotchas (from docs/solutions/)

1. **Spotify dev mode caps at 5 test users** — apply for Extended Quota Mode early
2. **`.environment()` must be last modifier** in root view chain (prevents runtime crash)
3. **SPTAppRemote drops after ~30s of silence** — reconnect on foreground
4. **Free Apple ID builds expire after 7 days** — just rebuild
5. **No client secret needed** for PKCE flow (iOS doesn't use one)

## Files to Modify

| File | Change |
|------|--------|
| `PirateRadio/App/PirateRadioApp.swift` | Set `demoMode = false`, add lifecycle connect/disconnect |
| `PirateRadio/Core/Spotify/SpotifyAuth.swift` | Add `app-remote-control` scope, SPTAppRemote instance, delegate |
| `PirateRadio/Core/Spotify/SpotifyPlayer.swift` | Import SpotifyiOS, replace 4 TODOs with SDK calls, add delegate |
| `PirateRadio/App/AppDelegate.swift` | Add URL callback handler |
| `project.yml` | Set DEVELOPMENT_TEAM (or do in Xcode) |

## References

- Existing PKCE auth: `PirateRadio/Core/Spotify/SpotifyAuth.swift`
- Player state machine: `PirateRadio/Core/Spotify/SpotifyPlayer.swift`
- MusicSource protocol: `PirateRadio/Core/Protocols/MusicSource.swift`
- Spotify iOS SDK docs: https://developer.spotify.com/documentation/ios
- SPTAppRemote reference: https://spotify.github.io/ios-sdk/html/Classes/SPTAppRemote.html
- Setup guide: `docs/solutions/integration-issues/spotify-flyio-dev-environment-setup.md`
