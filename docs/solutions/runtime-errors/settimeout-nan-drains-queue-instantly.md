---
title: "setTimeout(fn, NaN) Fires Immediately — Drains Queue Instantly"
category: runtime-errors
tags: [setTimeout, NaN, queue, validation, javascript, server]
module: server
symptoms:
  - "Entire queue drains instantly on playback start"
  - "All tracks skipped in a synchronous burst"
  - "Station goes idle immediately after queue is populated"
date: 2026-02-28
---

# setTimeout(fn, NaN) Fires Immediately — Drains Queue Instantly

## Problem

If `durationMs` on a track object is missing, undefined, or non-numeric, calling `setTimeout(fn, NaN)` fires the callback immediately (not after a delay). In the queue advancement loop where `advanceQueue()` calls `scheduleAdvancement()` which calls `setTimeout()`, this creates an instant recursive drain — the entire queue is consumed in a synchronous burst, all tracks are skipped, and the station goes idle.

## Symptoms

- Queue empties the moment playback begins, with no audible playback of any track.
- Server logs show rapid-fire `advanceQueue` calls with no delay between them.
- Station transitions straight from "playing" to "idle" within milliseconds.

## Root Cause

JavaScript's `setTimeout` treats any non-numeric delay as `0`. When the delay argument is `NaN`, `undefined`, or otherwise not a valid number, the timer fires on the next tick.

Since `advanceQueue` -> `scheduleAdvancement` -> `setTimeout` -> `advanceQueue` forms a loop, a single `NaN` duration causes the entire queue to drain instantly:

```
advanceQueue() sets currentTrack (durationMs: undefined)
  → scheduleAdvancement() calls setTimeout(fn, NaN)
    → callback fires immediately (delay = 0)
      → advanceQueue() sets next track
        → scheduleAdvancement() ... (repeats until queue is empty)
```

This happens whenever `durationMs` is missing from the track object — for example, if the Spotify API response omits it or the client sends a malformed request.

## Solution

Multi-layered guard in `scheduleAdvancement`:

```javascript
const MAX_TRACK_DURATION_MS = 30 * 60 * 1000; // 30 minutes

function scheduleAdvancement(session) {
  clearAdvancement(session);
  if (!session.currentTrack || !session.isPlaying) return;

  const durationMs = Number(session.currentTrack.durationMs);
  if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > MAX_TRACK_DURATION_MS) return;

  // ... calculate remaining time and schedule
}
```

Each guard serves a specific purpose:

1. **`Number()` instead of `parseInt()`** — cleaner coercion, no partial string parsing (`parseInt("300abc")` returns `300`, `Number("300abc")` returns `NaN`).
2. **`Number.isFinite()`** — catches `NaN`, `Infinity`, `-Infinity` in one check.
3. **`durationMs <= 0`** — catches zero and negative values that would fire immediately or behave unpredictably.
4. **`durationMs > MAX_TRACK_DURATION_MS`** — caps at 30 minutes, prevents timer-based resource abuse (a malicious `durationMs: Number.MAX_SAFE_INTEGER` would hold a timer for ~24.8 days).

## Key Insight

ANY server-side `setTimeout` that uses client-supplied data for the delay MUST validate the input. `setTimeout(fn, NaN)` is equivalent to `setTimeout(fn, 0)` — it fires immediately, not "never". This is one of JavaScript's most dangerous silent coercions because the failure mode (instant execution) is the exact opposite of what you'd expect (no execution).

## Prevention

- Validate all numeric inputs at the boundary where external data enters the system, not at the point of use.
- Wrap any `setTimeout` that depends on dynamic data in a guard that rejects non-finite, non-positive values.
- Add integration tests that pass `undefined`, `null`, `"not a number"`, `0`, `-1`, and `Infinity` as `durationMs` and assert the queue does not drain.

## How It Was Caught

Code review by the Kieran reviewer agent identified this during plan review, before any code was written. Static analysis and testing would not have caught it without specifically targeting `NaN` coercion paths.

## Related

- `server/index.js` — `scheduleAdvancement` function
- [MDN: setTimeout — delay parameter](https://developer.mozilla.org/en-US/docs/Web/API/setTimeout#delay)
