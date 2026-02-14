# Pirate Radio - Brainstorm

**Date:** 2026-02-13
**Status:** Ready for planning

---

## What We're Building

Pirate Radio is an iOS app for synchronized group music listening on the mountain. A crew of skiers/snowboarders all hear the same music at the same time through their own earbuds, with one or more people acting as DJ. Think Spotify Jam but with tighter sync, a way more fun interface, and snow-specific features.

**Core concept:** One device streams from Spotify and acts as the audio source. Pirate Radio relays that audio to all connected listeners in real-time, using clock synchronization and offset correction to keep everyone within ~20-40ms of each other — perceptually identical timing.

## Why This Approach (Pirate Stream)

We evaluated three architectures:

1. **Spotify Remote Orchestra** — Use Spotify's API to issue play/seek commands to each device. Rejected: API rate limits (30s rolling window) and round-trip latency (100-300ms) make tight sync impossible.

2. **Pirate Stream (chosen)** — DJ device streams audio; app relays it to listeners via real-time protocol. Each device uses NTP-like clock sync + leader-follower offset correction for precise playback.

3. **Hybrid Commander** — Each device streams from Spotify independently with drift correction. Rejected: micro-seek corrections cause audible glitches, and sync precision can't match owning the pipeline.

**Why Pirate Stream wins:**
- Tightest possible sync (~20-40ms, below human perception threshold)
- Only the DJ needs Spotify Premium (listeners receive the relay stream)
- Full control over the audio pipeline enables future music sources (SoundCloud, uploads, etc.)
- Can implement proper buffering for spotty mountain networks

**Tradeoffs to watch:**
- More complex audio engineering (Core Audio, real-time buffers)
- Potential Spotify ToS friction around audio relaying — needs legal review
- Requires a relay server or peer-to-peer mesh for the group

## Key Decisions

### DJ Modes (all three in v1)
- **Solo DJ:** One person controls everything. Others listen and can request songs.
- **Collaborative Queue:** Anyone adds tracks. Group votes or round-robin determines play order.
- **Hot-Seat Rotation:** DJ control rotates automatically after N songs.

### Audio Architecture
- Leader-follower model with continuous offset correction
- Aggressive buffering to handle mountain network conditions
- Cellular preferred over WiFi (more reliable on mountains per research)
- Target: <40ms sync across all devices in the crew

### UI / Aesthetic
- **Retro pirate radio meets neon ski lodge**
- Analog dials, frequency tuning visuals, static/noise textures
- Dark mode base with bright neon accents
- Mountain/snow imagery woven throughout
- Large touch targets (usable with gloves)

### Platform
- iOS native (Swift/SwiftUI)
- Best audio APIs (Core Audio) for precise timing
- Best Bluetooth/network stack for sync

### Music Source
- Spotify integration for v1
- SoundCloud, direct uploads, and other sources in future versions

## V1 Scope

**In:**
- Sync engine (the hard technical core)
- All 3 DJ modes
- Spotify integration (track selection, metadata, queue)
- Pirate/neon UI with glove-friendly controls
- Session creation/joining (QR code or link)
- Basic playback controls (play, pause, skip, volume)

**Out (future versions):**
- Chairlift DJ mode (auto-detect chairlift via proximity + speed)
- Run tracker integration (BPM adapts to speed/altitude)
- Walkie-talkie voice clips over music
- Crew discovery / social (see other crews, tune in, song battles)
- SoundCloud and direct upload support
- Android / cross-platform

## Open Questions

1. **Spotify ToS:** Is relaying audio from one Spotify account to multiple listeners legally viable? Need to research Spotify's developer terms around audio redistribution. May need each listener to auth with their own Spotify account even if audio comes from the DJ's stream.

2. **Network topology:** Peer-to-peer mesh (no server needed, but complex) vs. relay server (simpler, but adds latency and cost)? Ski mountains have variable connectivity — P2P might be more resilient when cell service is weak.

3. **Group size limit:** How many listeners can stay in sync before the architecture breaks down? Need to determine practical upper bound (5 people? 20? 50?).

4. **Offline/buffer strategy:** How much audio should be buffered ahead? Too little = dropouts on the lift. Too much = sync drift and memory pressure.

5. **Session discovery:** How do people join a crew? QR code scan? Nearby Bluetooth discovery? Share link? Some combination?

## Future Vision (Post-V1)

The snow-specific features are what make Pirate Radio a category of its own:

- **Chairlift DJ:** When the crew clusters together at low speed (chairlift detection), the UI transforms and chairlift riders get priority DJ control
- **Adaptive BPM:** Music energy matches riding intensity via accelerometer/GPS speed data
- **Walkie-talkie:** Quick voice clips ("last run!", "meet at the lodge") layered over the music without interrupting playback
- **Mountain Social:** See other Pirate Radio crews on the mountain, tune into their frequency, cross-crew song battles
- **Seasonal expansion:** Summer festivals, road trips, beach days — the sync tech generalizes beyond skiing
