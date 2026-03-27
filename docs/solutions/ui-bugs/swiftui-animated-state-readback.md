---
title: "SwiftUI withAnimation sets @State to target immediately — visual interpolation only"
date: 2026-02-14
category: ui-bugs
tags: [swiftui, animation, state-management, withAnimation, timing]
module: PirateRadio.UI.Components
symptoms:
  - "Spawned elements appear at animation target position instead of current visual position"
  - "Reading @State during withAnimation returns final value, not interpolated value"
  - "All spawned rings cluster at far right of screen (x = 1.05)"
severity: moderate
---

# SwiftUI `withAnimation` Sets @State to Target Immediately

## Problem

A pirate ship sails across the screen over 18 seconds using `withAnimation`. A separate task spawns expanding rings at the ship's "current" position by reading the animated `@State` variable. All rings appeared at the far right edge instead of tracking the ship.

```swift
@State private var ringOriginX: CGFloat = -0.05

// Task 1: Animate ship across
while !Task.isCancelled {
    ringOriginX = -0.05
    withAnimation(.linear(duration: 18)) {
        ringOriginX = 1.05  // ← Sets to 1.05 IMMEDIATELY in memory
    }
    try? await Task.sleep(for: .seconds(18))
}

// Task 2: Spawn rings at ship position
let spawnPoint = CGPoint(x: ringOriginX * screenW, y: screenH * 0.52)
// ringOriginX is always 1.05 here ^
```

## Root Cause

`withAnimation { property = newValue }` sets the `@State` variable to `newValue` **immediately** in memory. SwiftUI only **interpolates the visual rendering** over the animation duration. Any Swift code that reads the variable gets the final target value, not the current visual position.

The state variable and its on-screen appearance are decoupled — what you see is not what code reads.

## Solution

Replace the animated state variable with **time-based computation**. Store a cycle start time and calculate position mathematically:

```swift
@State private var shipCycleStart: Date = .now

/// Compute position from elapsed time — always returns the "true" current position.
private func currentShipX() -> CGFloat {
    let elapsed = Date.now.timeIntervalSince(shipCycleStart)
    let fraction = (elapsed.truncatingRemainder(dividingBy: 18.0)) / 18.0
    return -0.05 + fraction * 1.1  // -0.05 → 1.05
}

// Reset the clock every cycle
.task {
    while !Task.isCancelled {
        shipCycleStart = .now
        try? await Task.sleep(for: .seconds(18))
    }
}

// Spawn rings using the computed position
let spawnPoint = CGPoint(x: currentShipX() * screenW, y: screenH * 0.52)
```

The visual animation still uses `withAnimation` on the view; the time-based function is only for code that needs to know "where is the ship right now?"

## The Rule

> Never read an `@State` variable to determine the "current" position of something being animated with `withAnimation`. The state holds the target value, not the interpolated value. Use time-based math instead.

## Prevention

- When multiple SwiftUI tasks need to coordinate positions, use a shared time anchor (`Date`) rather than animated `@State`
- Keep visual animation (`withAnimation`) separate from logical position tracking
- If you find yourself reading an animated property in a different `Task`, that's a code smell — switch to time-based computation

## Related

- `docs/solutions/architecture-patterns/ntp-anchored-visual-sync.md` — same principle applied to cross-device sync
- `docs/solutions/runtime-errors/swiftui-environment-modifier-ordering.md` — another SwiftUI modifier ordering gotcha
- `PirateRadio/UI/Components/BeatPulseBackground.swift` — the fixed implementation
