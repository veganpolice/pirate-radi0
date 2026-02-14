---
title: "feat: Beat Visualizer — Visual Proof of Sync"
type: feat
date: 2026-02-14
---

# Beat Visualizer — Visual Proof of Sync

## Overview

Add a beat-synced visualizer to the NowPlayingView that replaces the album art area. The visualizer pulses at the track's exact BPM, synchronized across all devices via the existing NTP-anchored playback position. When crew members hold their phones side by side, they see the same beat pulse at the same moment — visual proof that sync is working.

This is the "wow moment" that sells Pirate Radio. Audio sync is invisible; this makes it visible.

## How Sync Works (No New Protocol Needed)

The key insight: **the animation is a pure function of BPM + NTP-anchored playback position**. Every device already agrees on the current playback position (that's the entire sync engine's job). If every device computes the beat phase from the same position and the same BPM, the animation is identical. No new sync messages required.

```
beatPhase = (currentPositionSeconds * (bpm / 60.0)) mod 1.0
```

- `currentPositionSeconds` comes from `NTPAnchoredPosition.positionAt(ntpTime:)` — already synced
- `bpm` comes from Spotify's audio features API — same value on every device
- `beatPhase` cycles 0.0 → 1.0 for each beat
- The visual maps `beatPhase` to scale, glow, opacity

## Proposed Solution

### Data Flow

```
Spotify Web API (audio-features/{trackId})
    ↓ (fetched once per track change)
SpotifyClient.fetchBPM(trackID:) → Double?
    ↓
SessionStore.currentBPM: Double?
    ↓ (@Observable)
BeatVisualizer (SwiftUI view, replaces album art)
    ↓ reads
SessionStore.session.isPlaying + NTPAnchoredPosition
    ↓ computes
beatPhase per frame via TimelineView(.animation)
    ↓ renders
Pulsing neon ring / waveform at exact beat timing
```

### New Files

1. **`PirateRadio/UI/Components/BeatVisualizer.swift`** — The visualizer view
2. **No other new files** — BPM fetch added to existing `SpotifyClient.swift`, state to existing `SessionStore`

### Files Modified

1. **`PirateRadio/Core/Spotify/SpotifyClient.swift`** — Add `fetchAudioFeatures(trackID:)` method
2. **`PirateRadio/Core/Sync/SessionStore.swift`** — Add `currentBPM` property, fetch on track change
3. **`PirateRadio/UI/NowPlaying/NowPlayingView.swift`** — Replace album art with `BeatVisualizer`
4. **`PirateRadio/Core/Models/Track.swift`** — Add optional `bpm: Double?` field

## Technical Approach

### 1. Fetch BPM from Spotify

Add to `SpotifyClient.swift`:

```swift
// GET /v1/audio-features/{id}
// Response includes: tempo (BPM as Float), time_signature, etc.
func fetchAudioFeatures(trackID: String) async throws -> AudioFeatures

struct AudioFeatures: Codable {
    let tempo: Double      // BPM, e.g. 120.0
    let timeSignature: Int // beats per bar, e.g. 4
}
```

This is a single REST call, cached per track. No rate limit concern (one call per track change, not per beat).

### 2. Store BPM in SessionStore

```swift
// SessionStore additions:
private(set) var currentBPM: Double?

// On track change (in handleUpdate):
case .trackChanged(let track):
    session?.currentTrack = track
    if let track {
        Task { await fetchBPMForTrack(track.id) }
    } else {
        currentBPM = nil
    }
```

### 3. BeatVisualizer View

Uses `TimelineView(.animation)` (same pattern as `CRTStaticOverlay`) to render every frame. Computes beat phase from the NTP-anchored position.

```swift
struct BeatVisualizer: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let phase = currentBeatPhase(at: timeline.date)
                drawBeat(context: context, size: size, phase: phase)
            }
        }
    }

    private func currentBeatPhase(at date: Date) -> Double {
        guard let bpm = store.currentBPM,
              store.session?.isPlaying == true,
              bpm > 0 else { return 0 }

        // Get current playback position from the NTP-anchored system
        let positionSeconds = store.currentPlaybackPosition(at: date)
        let beatsElapsed = positionSeconds * (bpm / 60.0)
        return beatsElapsed.truncatingRemainder(dividingBy: 1.0)
    }
}
```

### 4. Visual Design

The visualizer should feel like a **neon heartbeat** — the app's signature visual.

**Concept: Concentric pulse rings**
- Center: album art (small, ~80pt) as a constant anchor
- Rings expand outward on each beat, fading as they travel
- Ring color: `PirateTheme.signal` (cyan) for listeners, `PirateTheme.broadcast` (magenta) for DJ
- Beat "hit" moment (phase ~0.0): bright flash, rings spawn, slight scale bump
- Between beats (phase 0.3-0.9): rings drift outward, fade, ambient glow dims

**Phase-to-visual mapping:**
```
phase 0.0-0.1:  ATTACK  — sharp brightness spike, new ring spawns, scale 1.0→1.05
phase 0.1-0.3:  DECAY   — brightness eases down, ring expands
phase 0.3-0.9:  SUSTAIN — gentle ambient glow, rings continue expanding and fading
phase 0.9-1.0:  ANTICIPATION — subtle brightness increase (subconscious cue for next beat)
```

**Sync indicator:** Small text below the visualizer showing sync status: "IN SYNC" (cyan) / "SYNCING..." (amber). Uses existing `sessionStore.syncStatus`.

### 5. NowPlayingView Integration

Replace the `trackHeader` album art block with `BeatVisualizer`:

```swift
// Before: 200x200 album art
// After: BeatVisualizer filling the same space, with small album art centered inside

BeatVisualizer()
    .frame(height: 240)
    .padding(.top, 16)
```

Track title and artist move below the visualizer (simpler layout, visualizer is the hero).

### 6. Exposing Playback Position to the View

`SessionStore` needs a method to compute current position from the NTP anchor:

```swift
// SessionStore addition:
func currentPlaybackPosition(at date: Date) -> Double {
    guard let anchor = currentAnchor else { return 0 }
    // Convert Date to NTP milliseconds using Kronos offset
    let ntpNow = UInt64(date.timeIntervalSince1970 * 1000) + clockOffset
    return anchor.positionAt(ntpTime: ntpNow)
}
```

This requires the `SyncEngine` to expose the current anchor and clock offset to `SessionStore`. Add a new `SessionUpdate` case:

```swift
case anchorUpdated(NTPAnchoredPosition, clockOffsetMs: Int64)
```

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Track has no audio features (API returns 404) | Fall back to no animation — show static album art with subtle breathing glow |
| BPM is 0 or missing | Same as above — graceful fallback |
| Playback paused | Freeze the visualizer at current phase — rings stop expanding, glow holds |
| Playback resumes | Animation resumes from the correct phase (computed from NTP position) |
| Track changes | Fade out current visualizer, fetch new BPM, fade in with new tempo |
| App backgrounded | `TimelineView` automatically stops rendering (no battery cost) |
| Sync drift >500ms | Visualizer follows the NTP anchor, not local playback — so it stays in sync even during drift correction |
| Very slow BPM (<60) | One pulse per second or slower — still works, just calmer |
| Very fast BPM (>180) | 3+ pulses per second — cap visual intensity so it doesn't strobe |
| Spotify API rate limit | Cache BPM per track ID in memory; only fetch once per unique track |
| No network for API call | If BPM fetch fails, show album art fallback. Retry on next track. |

## Acceptance Criteria

- [ ] Visualizer pulses at the correct BPM for the current track
- [ ] Two devices in the same session show visually identical beat pulses when held side by side
- [ ] Visualizer freezes when playback pauses, resumes correctly
- [ ] Smooth transition when track changes (no jarring jump)
- [ ] Falls back to album art display when BPM unavailable
- [ ] No additional battery drain beyond existing `TimelineView` usage (60fps only when visible)
- [ ] Sync status indicator visible below visualizer
- [ ] Fits the neon pirate radio aesthetic (cyan/magenta palette, glow effects)
- [ ] Glove-friendly — no interactive elements in the visualizer itself
- [ ] Works in demo mode with a hardcoded BPM

## Implementation Checklist

### Step 1: BPM Data Pipeline
- [x] Add `AudioFeatures` response model — `SpotifyClient.swift`
- [x] Add `fetchAudioFeatures(trackID:)` to `SpotifyClient` — `SpotifyClient.swift`
- [x] Add `bpm: Double?` to `Track` model — `Track.swift`
- [x] Add `currentBPM: Double?` to `SessionStore` — `SessionStore.swift`
- [x] Fetch BPM on track change in `SessionStore.handleUpdate` — `SessionStore.swift`
- [x] Cache BPM in `Track.bpm` to avoid re-fetching

### Step 2: Expose Playback Position
- [x] Add `anchorUpdated` case to `SyncEngine.SessionUpdate` — `SyncEngine.swift`
- [x] Emit `anchorUpdated` from `SyncEngine` when anchor changes — `SyncEngine.swift`
- [x] Store `currentAnchor` and `clockOffsetMs` in `SessionStore` — `SessionStore.swift`
- [x] Add `currentPlaybackPosition(at:)` method to `SessionStore` — `SessionStore.swift`

### Step 3: Build Visualizer
- [x] Create `BeatVisualizer.swift` with `TimelineView` + `Canvas` — `UI/Components/BeatVisualizer.swift`
- [x] Implement `currentBeatPhase(at:)` computation
- [x] Implement concentric ring rendering with phase-based animation
- [x] Add neon glow effects matching `PirateTheme`
- [x] Add album art thumbnail in center
- [x] Add sync status indicator below

### Step 4: Integrate into NowPlayingView
- [x] Replace album art section with `BeatVisualizer` — `NowPlayingView.swift`
- [x] Move track title/artist below visualizer — `NowPlayingView.swift`
- [x] Update demo mode with hardcoded BPM (e.g., 120) — `SessionStore.swift`

### Step 5: Polish
- [x] Smooth fade transition on track change
- [x] Freeze animation on pause
- [x] Fallback to album art when no BPM
- [x] Cap visual intensity for BPM >180 (anti-strobe)
- [ ] Test with two physical devices side by side

## References

- Existing `TimelineView` + `Canvas` pattern: `PirateRadio/UI/Components/CRTStaticOverlay.swift`
- NTP-anchored position model: `PirateRadio/Core/Sync/SyncEngine.swift:39`
- Spotify Audio Features API: `GET /v1/audio-features/{id}` → returns `tempo` (BPM)
- Session store: `PirateRadio/Core/Sync/SessionStore.swift`
- Current album art area: `PirateRadio/UI/NowPlaying/NowPlayingView.swift:47-94`
- Theme colors: `PirateRadio/UI/Theme/PirateTheme.swift`
- [Spotify Audio Features docs](https://developer.spotify.com/documentation/web-api/reference/get-audio-features)
