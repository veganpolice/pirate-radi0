---
title: "Server-Side Queue Advancement Timer Pattern"
category: architecture-patterns
tags: [server, timer, queue, autonomous-playback, websocket, settimeout]
module: server
date: 2026-02-28
---

# Server-Side Queue Advancement Timer Pattern

## Problem

When the broadcaster backgrounds the iOS app, the WebSocket disconnects and playback stops. The session dies because the server had no mechanism to advance the queue without client interaction. Every listener loses audio the moment the host switches to another app.

## Root Cause

Queue advancement was driven entirely by the client. The flow was: track ends on device -> client sends skip/next -> server updates state. With no client connected, the server sat idle holding a frozen session until the idle timeout reaped it.

## Solution

A per-session `setTimeout` timer chain on the server that fires when the current track's remaining duration elapses, advances the queue, broadcasts `stateSync` to all connected members, and schedules the next timer. Combined with a 5-minute grace period so sessions with queued tracks survive the broadcaster disconnecting.

### Core functions

**`scheduleAdvancement(session)`** -- calculates remaining playback time using the elapsed-time anchor and sets a `setTimeout`:

```js
function scheduleAdvancement(session) {
  clearAdvancement(session);  // always clear first — prevents timer leaks
  if (!session.currentTrack || !session.isPlaying) return;

  const durationMs = Number(session.currentTrack.durationMs);
  if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > MAX_TRACK_DURATION_MS) return;

  const elapsed = Date.now() - session.positionTimestamp;
  const currentPositionMs = session.positionMs + elapsed;
  const remainingMs = durationMs - currentPositionMs;

  if (remainingMs <= 0) {
    advanceQueue(session);
    return;
  }

  session.advancementTimer = setTimeout(() => {
    advanceQueue(session);
  }, remainingMs);
}
```

**`advanceQueue(session)`** -- shifts the queue, bumps epoch, resets sequence, updates `lastActivity`, broadcasts, and schedules the next timer:

```js
function advanceQueue(session) {
  const nextTrack = session.queue.shift();
  if (nextTrack) {
    session.currentTrack = nextTrack;
    session.positionMs = 0;
    session.positionTimestamp = Date.now();
    session.isPlaying = true;
    session.epoch++;
    session.sequence = 0;
    session.lastActivity = Date.now();  // prevents idle timeout from killing active stations

    broadcastToSession(session, {
      type: "stateSync",
      data: sessionSnapshot(session),
      epoch: session.epoch,
      seq: session.sequence,
      timestamp: Date.now(),
    });

    scheduleAdvancement(session);  // chain the next timer
  } else {
    session.isPlaying = false;
    session.lastActivity = Date.now();
    // broadcast idle state so clients update UI
    broadcastToSession(session, { ... });
  }
}
```

**`destroyOrGrace(session)`** -- on last member disconnect, checks whether the session should stay alive:

```js
function destroyOrGrace(session) {
  if (session.queue.length > 0 || session.isPlaying) {
    if (!session.destroyTimeout) {
      session.destroyTimeout = setTimeout(() => {
        destroySession(session.id);
      }, GRACE_PERIOD_MS);  // 5 minutes
    }
  } else {
    destroySession(session.id);
  }
}
```

### Handler hook points

The timer must be wired into every state-mutating handler. Missing any of these causes stale timers or stuck queues:

| Handler | Action | Why |
|---------|--------|-----|
| `playCommit` | `scheduleAdvancement()` | Playback starting, begin countdown |
| `skip` | `scheduleAdvancement()` | New track loaded, reset countdown |
| `resume` | `scheduleAdvancement()` | Unpaused, resume countdown |
| `pause` | `clearAdvancement()` | No advancement while paused |
| `seek` | `scheduleAdvancement()` | Position changed, recalculate remaining time |
| `destroySession` | `clearAdvancement()` | Cleanup, prevent firing into deleted session |
| Last member leaves | `destroyOrGrace()` | Start grace period instead of immediate destroy |

## Critical Guards

1. **Validate `durationMs` with `Number()` + `isFinite()` + clamp.** Using `parseInt()` silently truncates decimals. If `durationMs` is `undefined`, `NaN`, or absurdly large, `setTimeout(fn, NaN)` fires immediately and drains the entire queue in a tight loop. The guard:
   ```js
   const durationMs = Number(session.currentTrack.durationMs);
   if (!Number.isFinite(durationMs) || durationMs <= 0 || durationMs > MAX_TRACK_DURATION_MS) return;
   ```
   `MAX_TRACK_DURATION_MS` is set to 30 minutes.

2. **`seek` handler MUST call `scheduleAdvancement()`.** Without it, the timer uses the pre-seek remaining time. If a user seeks to 0:10 on a 3:00 track but the timer still thinks 0:30 remains, the track will cut off early or late.

3. **Cap queue size (`MAX_QUEUE_SIZE = 100`).** Without a cap, a malicious or buggy client could push unbounded tracks and exhaust server memory.

4. **Always `clearAdvancement()` before `scheduleAdvancement()`.** The first line of `scheduleAdvancement` calls `clearAdvancement`. This prevents timer leaks where two timers race on the same session.

5. **Grace period broadcasts to 0 members.** During the grace period the timer chain continues advancing and broadcasting `stateSync` to an empty member set. This is harmless (no-op broadcast) and acceptable for a POC. A production optimization would pause the timer chain and resume on reconnect.

## Prevention

- **Wire timers at the handler level, not deep in business logic.** Every handler that changes `isPlaying`, `positionMs`, or `currentTrack` must explicitly call `scheduleAdvancement()` or `clearAdvancement()`. A code review checklist item: "Does this handler affect playback position? If yes, does it touch the advancement timer?"
- **Validate all client-supplied durations server-side.** Never trust `durationMs` from the client. Use `Number()` + `isFinite()` + clamp, not `parseInt()`.
- **Cap all unbounded collections.** Any array that clients can push to (queue, members, requests) needs a size limit.
- **Anchor elapsed time to `Date.now()` at mutation time.** Store `positionTimestamp` alongside `positionMs` so the server can compute current position at any future point without client input.

## Related

- `server/index.js` -- `scheduleAdvancement`, `clearAdvancement`, `advanceQueue`, `destroyOrGrace` (lines 547-632)
- [Queue / Playback / Skip / Advance Plan](/docs/plans/2026-02-14-feat-queue-playback-skip-advance-plan.md)
- [NTP-Anchored Visual Sync](/docs/solutions/architecture-patterns/ntp-anchored-visual-sync.md) -- uses the same `positionMs` + `positionTimestamp` anchor on the client side
- [WebSocket Protocol Mismatch](/docs/solutions/integration-issues/websocket-protocol-mismatch-silent-message-drop.md) -- related disconnect/reconnect issues
