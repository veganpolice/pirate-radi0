---
title: Cancel-and-Replace Generation Counter Pattern
date: 2026-02-28
category: architecture-patterns
tags:
  - swift-concurrency
  - cancel-and-replace
  - race-condition
  - generation-counter
  - websocket
module: PirateRadio/Core/Sync
severity: high
symptoms:
  - Orphaned WebSocket connections on rapid dial switching
  - Incorrect session state (wrong station playing)
  - Server-side phantom members in sessions
---

## Problem

`tuneToStation()` used a cancel-and-replace pattern (`tuneTask?.cancel()` then create new Task). But Swift cooperative cancellation doesn't cancel underlying URLSession requests or WebSocket connections. If the user rapidly dials through stations A→B→C:

- Task-A's `leaveSession()` completes, Task-A is cancelled
- Task-B starts `joinSessionById(B)`, midway Task-B is cancelled
- Task-C starts `joinSessionById(C)`
- Task-B's join completes (URLSession ignores cancellation), opening a WebSocket
- Now two WebSocket connections exist, `session` was overwritten by whichever finished last

## Solution

Added a UUID generation counter. Each tune request gets a unique ID. After `joinSessionById` completes, check if a newer request superseded us — if so, leave the stale session.

```swift
private var tuneGeneration: UUID = UUID()

func tuneToStation(_ station: Station) {
    guard session?.id != station.sessionId else { return }
    tuneTask?.cancel()
    let generation = UUID()
    tuneGeneration = generation
    tuneTask = Task {
        if session != nil {
            await leaveSession()
        }
        guard !Task.isCancelled, tuneGeneration == generation else { return }
        await joinSessionById(station.sessionId)
        guard tuneGeneration == generation else {
            // A newer tune request superseded us — leave what we just joined
            await leaveSession()
            return
        }
        if error == nil {
            UserDefaults.standard.set(station.userId, forKey: "lastTunedUserId")
        }
    }
}
```

## Key Insights

- `Task.isCancelled` alone is insufficient when underlying operations (URLSession, WebSocket) don't cooperate with Swift cancellation
- A generation counter provides a second layer of defense — even if the cancelled task's network call completes, the stale result is detected and cleaned up

## Prevention

- Always use a generation counter alongside cancel-and-replace when operations have side effects (network connections, state mutations)
- Add an early-out guard when the target is already the current state (`session?.id != station.sessionId`)
- Check generation after **every** await point, not just after the first one
