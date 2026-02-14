# Pirate Radio

**Synchronized group listening for the mountain.**

One person DJs from Spotify. Everyone else hears the same track at the same time through their own earbuds. Retro pirate radio meets neon ski lodge.

```
┌─────────────────────────────────────────────┐
│             Pirate Radio Backend             │
│           Node.js on Fly.io (WSS)            │
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
      Each device streams from its own
      Spotify Premium account. The server
      coordinates what plays and when.
```

Every listener streams independently from Spotify's CDN using their own Premium account. A lightweight WebSocket server broadcasts timestamped sync commands. NTP-based clock sync via [Kronos](https://github.com/MobileNativeFoundation/Kronos) achieves ~300ms sync precision across devices -- unnoticeable when you're spread across a mountain.

> **Every listener needs Spotify Premium.** This is the only architecture that complies with Spotify's Developer Policy (no one-to-many streaming). The tradeoff is real, but it's the only legal path.

---

## Tech Stack

| Layer | Tech |
|-------|------|
| iOS app | Swift 5.9, SwiftUI, iOS 17+ |
| Music playback | [SpotifyiOS SDK](https://github.com/spotify/ios-sdk) (App Remote) |
| Track search / metadata | Spotify Web API |
| Clock sync | [Kronos](https://github.com/MobileNativeFoundation/Kronos) NTP (10-50ms precision) |
| Backend | Node.js, Express, `ws` |
| Hosting | [Fly.io](https://fly.io) (single instance, in-memory state) |
| Auth | Spotify OAuth/PKCE on device, JWT for backend |
| Package manager | Swift Package Manager |

## Project Structure

```
PirateRadio/
├── App/                        # Entry point, AppDelegate
├── Core/
│   ├── Models/                 # Session, Track, SyncCommand, errors
│   ├── Networking/             # WebSocketTransport, KronosClock
│   ├── Protocols/              # MusicSource, SessionTransport, ClockProvider
│   ├── Spotify/                # Auth (OAuth/PKCE), Player (state machine), Web API client
│   └── Sync/                   # SyncEngine, SessionStore, NowPlayingBridge
├── UI/
│   ├── Auth/                   # Spotify login
│   ├── Session/                # Create / join / lobby
│   ├── NowPlaying/             # Playback screen, queue
│   ├── Theme/                  # PirateTheme, GloveButton
│   └── Components/             # FrequencyDial
└── Resources/                  # Assets, fonts, Info.plist

server/                         # Node.js backend
├── index.js                    # Single file: Express + WebSocket + session state
├── package.json
├── fly.toml
└── Dockerfile
```

## Setup

### Prerequisites

- Xcode 16+ with iOS 17 SDK
- A physical iPhone (Spotify SDK doesn't work in the simulator)
- [Node.js](https://nodejs.org) 20+ (for local backend dev)
- [Fly.io CLI](https://fly.io/docs/flyctl/install/) (for deployment)
- 2+ Spotify Premium accounts (for sync testing)

### 1. Spotify Developer Dashboard

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and create an app.
2. Note your **Client ID**.
3. Add a **Redirect URI** (e.g., `pirate-radio://callback`).
4. Add your test users under **Users and Access** (Dev Mode is limited to 25 users).
5. Apply for **Extended Quota Mode** early -- approval timelines are unpredictable.

Add your Client ID and Redirect URI to the Xcode project (see `SpotifyAuth.swift`).

### 2. iOS App

```bash
# Open the Xcode project
open PirateRadio.xcodeproj

# Or regenerate from project.yml (requires xcodegen)
xcodegen generate
```

- Set your development team in Signing & Capabilities.
- SPM will resolve `SpotifyiOS` and `Kronos` automatically.
- Build and run on a physical device.

### 3. Backend

**Local development:**

```bash
cd server
npm install
npm run dev          # starts with --watch on port 3000
```

**Deploy to Fly.io:**

```bash
cd server
fly launch           # first time -- creates the app
fly deploy           # subsequent deploys
fly secrets set JWT_SECRET=$(openssl rand -hex 32)
```

The server runs at `pirate-radio-sync.fly.dev`. Point the iOS app's WebSocket URL there.

## How It Works

1. **DJ creates a session** -- gets a 4-digit code (displayed as a radio frequency, e.g., code `1073` = "107.3 FM").
2. **Crew joins** by entering the code.
3. **DJ picks a track** -- the server broadcasts a two-phase sync command:
   - **Prepare:** all devices preload the track via Spotify SDK.
   - **Commit:** all devices start playback at an NTP-aligned timestamp (1500ms lead time absorbs Spotify's variable latency).
4. **Drift correction** runs continuously: ignore <50ms, rate-adjust 50-500ms, hard seek >500ms.
5. **Join mid-song:** latecomers get the current NTP-anchored position and seek to the right spot.

## License

Private. All rights reserved.
