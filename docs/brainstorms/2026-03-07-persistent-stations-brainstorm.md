# Persistent Radio Stations

**Date:** 2026-03-07
**Status:** Ready for planning

## What We're Building

Each user owns a permanent radio station identified by a self-chosen FM frequency (e.g., 97.3). Stations persist across server restarts and app sessions. A station's queue loops continuously — when the last track finishes, it starts over from the beginning. Anyone on the platform can see all stations on the dial and tune in at any time, even if the station owner isn't actively listening.

### Core Behaviors

- **One station per user, forever.** Created on first Spotify login. User picks their frequency (first-come-first-served). The frequency is their permanent identity.
- **Queue is persistent.** Stored in SQLite. Tracks added by the owner are saved and survive server restarts.
- **Always broadcasting (virtually).** The station's queue loops. When someone tunes in, the server computes what track/position should be playing based on a stored snapshot, then starts real-time sync.
- **All stations are public.** The FM dial shows every registered station. No friend/follow system needed.
- **Owner controls only while tuned in.** If the owner is listening to someone else's station, their own station plays autonomously (queue advances, loops). They must tune back in to skip/reorder.

## Why This Approach (Lazy Snapshot)

Three approaches were considered:

1. **Virtual Clock** — Compute current position from a mathematical timeline. Elegant but complex.
2. **Always-Running Timers** — Every station has a live timer. Simple but wasteful and doesn't scale.
3. **Lazy Snapshot (chosen)** — Store a snapshot of playback position when all listeners leave. Compute current position on next tune-in. Run real timers only while someone is listening.

Lazy Snapshot was chosen because:
- It reuses the existing timer/advancement pattern (already works for active sessions)
- No timers run for idle stations (efficient)
- Simpler than virtual clock math — just "how much wall-clock time has passed since snapshot?"
- Position calculation still needed but is a one-time operation on tune-in, not continuous

### How Lazy Snapshot Works

1. **Station goes idle** (last listener leaves): Save snapshot `{ trackIndex, elapsedMs, snapshotTimestamp }` to SQLite.
2. **Someone tunes in**: Calculate `wallClockElapsed = now - snapshotTimestamp`. Walk forward through the queue by `wallClockElapsed` milliseconds (accounting for remaining duration of the snapshot track, then subsequent tracks, looping as needed). Result: current `trackIndex` and `positionMs`.
3. **Start real-time sync**: Boot up the normal session/timer machinery from the computed position. Broadcast `stateSync` to the new listener.
4. **Station goes idle again**: Save a new snapshot, tear down the timer.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Station identity | User-chosen FM frequency | Personal, memorable, fun |
| Station persistence | SQLite on Fly.io volume | Simple, no external services, fits single-instance architecture |
| Queue behavior on empty | Loop from the beginning | Station always has music if tracks were ever added |
| Station discovery | All stations public on the dial | No social graph needed, community feel |
| Owner control | Only while tuned into own station | Keeps it simple, station is autonomous otherwise |
| Playback model | Lazy Snapshot | Efficient, pragmatic, builds on existing timer pattern |

## Open Questions

1. **Frequency conflicts:** What happens if two users want 97.3? First-come-first-served is clear, but what's the UX for "taken"? Show available nearby frequencies?
2. **Queue size limits:** Current limit is 100 tracks. Is that enough for a looping station? Should it be higher?
3. **Station deletion/reset:** Can a user abandon their frequency and pick a new one? Or is it permanent?
4. **Listener count visibility:** Should the dial show how many people are tuned into each station?
5. **Offline indicator:** Should there be a visual distinction between "owner is listening" vs "station playing autonomously"?
6. **Migration:** How do existing in-memory sessions transition? Wipe and start fresh, or try to migrate?
7. **Fly.io volume:** Need a persistent volume for SQLite. Single-instance constraint is already true — just need to ensure the volume is configured.
