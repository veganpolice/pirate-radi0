---
title: "Syncing visual animations across devices using NTP-anchored positions"
date: 2026-02-14
category: architecture-patterns
module: sync-engine, ui
tags: [ntp, animation, sync, beat-visualizer, swiftui, timelineview, canvas]
symptoms:
  - Need to show identical animations on multiple devices simultaneously
  - Want visual proof that audio sync is working
  - Considered sending animation state over WebSocket
severity: n/a
resolution_time: 2h
---

# Syncing Visual Animations Across Devices via NTP-Anchored Positions

## Problem

We needed a beat visualizer that pulses at the track's BPM, synchronized across all devices in a session. The naive approach would be to broadcast animation state over WebSocket — but that adds latency, network overhead, and a new failure mode.

## Key Insight

**Animation is a pure function of already-synced state. No new protocol needed.**

Every device already agrees on the current playback position via the NTP-anchored sync engine. If every device computes the beat phase from the same position and the same BPM, the animation is identical by construction.

```
beatPhase = (currentPositionSeconds * (bpm / 60.0)) mod 1.0
```

- `currentPositionSeconds` — from `NTPAnchoredPosition.positionAt(ntpTime:)`, already synced
- `bpm` — from Spotify's audio features API, same value on every device
- `beatPhase` — cycles 0.0 → 1.0 for each beat, drives all visual properties

If audio is in sync, the visual is in sync. Zero additional messages.

## Solution

### 1. Expose NTP anchor to the view layer

The `SyncEngine` (actor) already tracks an `NTPAnchoredPosition`. We added a new `SessionUpdate` case to bridge it to the `@Observable` `SessionStore`:

```swift
// SyncEngine.SessionUpdate
case anchorUpdated(NTPAnchoredPosition, clockOffsetMs: Int64)

// SessionStore
private(set) var currentAnchor: NTPAnchoredPosition?
private(set) var clockOffsetMs: Int64 = 0

func currentPlaybackPosition(at date: Date) -> Double {
    guard let anchor = currentAnchor else { return 0 }
    let ntpNow = UInt64(date.timeIntervalSince1970 * 1000) + UInt64(max(0, clockOffsetMs))
    return anchor.positionAt(ntpTime: ntpNow)
}
```

### 2. Compute beat phase per frame

The `BeatVisualizer` uses `TimelineView(.animation)` to get a callback every frame, then computes phase from the shared position:

```swift
private func currentBeatPhase(at date: Date) -> Double {
    guard let bpm = store.currentBPM,
          store.session?.isPlaying == true,
          bpm > 0 else { return 0 }
    let positionSeconds = store.currentPlaybackPosition(at: date)
    let beatsElapsed = positionSeconds * (bpm / 60.0)
    return beatsElapsed.truncatingRemainder(dividingBy: 1.0)
}
```

### 3. Map phase to visuals

Phase 0.0→1.0 drives everything: ring expansion, opacity, glow intensity. No keyframe animation — pure math from shared state.

## Why This Pattern Generalizes

This works for **any** visual that should be synchronized across devices:

| Visual | Phase formula |
|--------|---------------|
| Beat pulse | `(position * bpm / 60) mod 1.0` |
| Progress bar | `position / trackDuration` |
| Color cycle | `(position * cycleHz) mod 1.0` |
| Waveform scroll | `position * pixelsPerSecond` |

The pattern: **derive visual state from NTP-anchored playback position, not from messages or local timers.**

## What We Tried (and Avoided)

| Approach | Why rejected |
|----------|-------------|
| Broadcast animation frame index over WebSocket | Adds latency, network load, new failure mode. Unnecessary when state is already shared. |
| Local `Timer` driving animation | Each device's timer drifts independently. Would be visually identical only by accident. |
| Spotify's audio analysis API (beat timestamps) | More accurate to actual beat grid, but 10x more complex to sync. BPM is sufficient for a pulse effect. |

## Anti-Strobe Safeguard

For BPM >180 (3+ pulses/second), we reduce ring count and opacity to prevent strobe-like flashing:

```swift
let intensityScale = bpm > 180 ? 120.0 / bpm : 1.0
let visibleRings = bpm > 180 ? 2 : maxRings
```

## Files

- `PirateRadio/UI/Components/BeatVisualizer.swift` — Visualizer view (TimelineView + Canvas)
- `PirateRadio/Core/Sync/SyncEngine.swift:52` — `anchorUpdated` session update case
- `PirateRadio/Core/Sync/SessionStore.swift` — `currentPlaybackPosition(at:)` bridge
- `PirateRadio/Core/Spotify/SpotifyClient.swift` — `fetchAudioFeatures(trackID:)` for BPM
- `PirateRadio/Core/Models/Track.swift` — `bpm: Double?` cached per track

## Prevention / Best Practices

- **Default to computation over communication.** Before adding a sync message, check if the state can be derived from what's already shared.
- **Use NTP time, not `Date()`.** `Date()` varies per device. NTP-anchored calculations give identical results everywhere.
- **Cache API-derived constants per track.** BPM doesn't change mid-song. Fetch once, cache in the model.
- **Cap visual intensity for fast tempos.** Anything above 180 BPM risks photosensitive discomfort.

## Related

- [Pirate Radio v1 Plan](/docs/plans/2026-02-13-feat-pirate-radio-v1-plan.md) — Sync engine architecture
- [Beat Visualizer Plan](/docs/plans/2026-02-14-feat-beat-visualizer-sync-proof-plan.md) — Feature plan
- `NTPAnchoredPosition` in `SyncCommand.swift:26` — The core anchor model
- PR: https://github.com/veganpolice/pirate-radi0/pull/2
