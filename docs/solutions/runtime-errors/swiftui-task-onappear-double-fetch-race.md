---
title: SwiftUI .task + .onAppear Double-Fetch Race Condition
date: 2026-02-28
category: runtime-errors
tags:
  - swiftui
  - lifecycle
  - race-condition
  - networking
module: PirateRadio/UI
severity: medium
symptoms:
  - Duplicate HTTP GET /stations requests on app launch
  - Wasted bandwidth and server load
  - Race condition between async lifecycle methods
---

## Problem

In `DialHomeView`, both `.task {}` and `.onAppear {}` were attached to the same view. `.task` called `autoTune()` which internally calls `fetchStations()`. `.onAppear` had a guard `if !sessionStore.isAutoTuning` to prevent double-fetch, but this was a timing race — `.onAppear` fires before `.task`'s closure executes its first line (`isAutoTuning = true`), so the guard passes and `fetchStations()` runs twice on every app launch.

## Root Cause

`.task` and `.onAppear` both fire on first appearance. `.task` is async (creates a new Task), so `isAutoTuning` isn't set to `true` by the time `.onAppear` checks it. This creates a race condition where both fetch operations execute.

## Solution

Replaced `.onAppear` with `.onChange(of: sessionStore.session)` which only triggers the re-fetch when returning from a session logout (oldValue != nil, newValue == nil). `.task` handles initial auto-tune exclusively.

```swift
// BEFORE (buggy — double-fetch race)
.task {
    await sessionStore.autoTune()
}
.onAppear {
    if !sessionStore.isAutoTuning {
        Task { await sessionStore.fetchStations() }
    }
}

// AFTER (fixed — single entry point)
.task {
    await sessionStore.autoTune()
}
.onChange(of: sessionStore.session) { oldValue, newValue in
    if oldValue != nil && newValue == nil {
        Task { await sessionStore.fetchStations() }
    }
}
```

## Prevention

- Never use `.task` + `.onAppear` for the same concern — their ordering is not guaranteed
- Use `.task(id:)` or `.onChange(of:)` for re-trigger logic
- Prefer `.task` for initial async work, `.onChange` for reactive updates
