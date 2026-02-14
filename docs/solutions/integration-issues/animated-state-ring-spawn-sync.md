# Animated State Variable Ring Spawn Desynchronization

## Problem

In a SwiftUI view, a pirate ship sails across the screen using animated state transitions:

```swift
@State private var ringOriginX: CGFloat = -0.05

// In a .task:
while !Task.isCancelled {
    ringOriginX = -0.05
    withAnimation(.linear(duration: 18)) {
        ringOriginX = 1.05
    }
    try? await Task.sleep(for: .seconds(18))
}
```

A separate task spawns rings at the ship's current position by reading `ringOriginX`:

```swift
let spawnPoint = CGPoint(x: ringOriginX * screenW, y: screenH * 0.52)
```

**Result:** All rings appear at the far right edge (x=1.05) instead of following the ship's visual position across the screen.

## Root Cause

The issue stems from a fundamental difference between **visual animation** and **state mutation** in SwiftUI:

- `withAnimation { ringOriginX = 1.05 }` immediately sets `ringOriginX` to `1.05` in memory
- SwiftUI only **interpolates the visual rendering** of this value over 18 seconds
- Any code that reads `ringOriginX` directly gets the actual state value (`1.05`), not the current visual position
- The ring spawning task reads the state value instantly, capturing the end-of-animation value every time

The state variable and its visual representation become **decoupled**—what you see on screen is not what the code can read.

## Solution

Replace the animated state variable with **time-based computation**. Instead of relying on SwiftUI's animation interpolation, calculate the current position based on elapsed time:

```swift
@State private var shipCycleStart: Date = .now

private func currentShipX() -> CGFloat {
    let elapsed = Date.now.timeIntervalSince(shipCycleStart)
    let fraction = (elapsed.truncatingRemainder(dividingBy: 18.0)) / 18.0
    return -0.05 + fraction * 1.1
}
```

**Update the animation loop:**

```swift
while !Task.isCancelled {
    shipCycleStart = .now
    try? await Task.sleep(for: .seconds(18))
}
```

**Use the computed position when spawning rings:**

```swift
let spawnPoint = CGPoint(x: currentShipX() * screenW, y: screenH * 0.52)
```

**Apply the animation to the view:**

```swift
.offset(x: currentShipX() * screenW)
.animation(.linear(duration: 18), value: shipCycleStart)
```

### Why This Works

- **Decoupling visual from logical:** The computed function provides the true real-time position
- **Consistent read source:** All tasks query the same time-based calculation, ensuring synchronization
- **Animation-agnostic:** The visual animation is independent of the logical position tracking
- **No state race conditions:** Multiple tasks can safely read the same calculated value without conflicts

This pattern—computing animated values from a time anchor rather than animating state—is essential for coordinating multiple visual elements that depend on each other's positions.
