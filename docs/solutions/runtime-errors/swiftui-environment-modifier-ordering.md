---
title: "SwiftUI @Environment crash from modifier ordering"
date: 2026-02-14
category: runtime-errors
tags: [swiftui, environment, observable, modifier-chain, overlay]
module: PirateRadio.App
symptoms:
  - "Fatal error: No Observable object of type [X] found"
  - "SwiftUICore/Environment+Objects.swift:34: Fatal error"
  - "A View.environmentObject(_:) for [X] may be missing as an ancestor"
  - "App crashes on launch, blank screen"
  - "Tests crash before any test code runs"
severity: blocking
---

# SwiftUI @Environment Crash from Modifier Ordering

## Problem

App crashes immediately on launch with:

```
SwiftUICore/Environment+Objects.swift:34: Fatal error:
No Observable object of type ToastManager found.
A View.environmentObject(_:) for ToastManager may be missing
as an ancestor of this view.
```

Also surfaces when running hosted unit tests (test target depends on app target, so Xcode launches the full app as a host process).

## Root Cause

**SwiftUI modifier chain ordering determines environment propagation direction.** Modifiers applied later are **outermost** — they wrap everything before them. Environment values propagate **inward** from outer to inner.

```swift
// BROKEN — overlay can't see environment
RootView()
    .environment(toastManager)     // applied first = inner
    .overlay { ToastOverlay() }    // applied second = outer — no access!
```

The `.overlay` is at a higher level than `.environment()`, so `ToastOverlay` can't find `toastManager`. This crashes any view using `@Environment(ToastManager.self)`.

## Solution

Move `.environment()` calls to the **end** (outermost position) of the modifier chain:

```swift
// FIXED — environment wraps everything including overlays
RootView()
    .preferredColorScheme(.dark)
    .safeAreaInset(edge: .bottom) { ToastOverlay() }
    .onChange(of: ...) { ... }
    .optionalEnvironment(sessionStore)
    .environment(authManager)       // outermost — wraps all above
    .environment(toastManager)      // outermost — wraps all above
    .environment(mockTimerManager)  // outermost — wraps all above
```

## The Rule

> `.environment()` should always be the **last modifiers** in the chain so they wrap overlays, safe area insets, sheets, and all other view modifiers.

This applies to:
- `.overlay { }` — creates a sibling view at the same level
- `.safeAreaInset { }` — creates a view in the safe area
- `.sheet { }`, `.fullScreenCover { }` — presented views inherit environment from their attachment point

## Investigation Steps Tried

1. **`isTesting` guard in App body** — skipped full UI during XCTest. Fixed tests but app still crashed at runtime since the modifier ordering was wrong for both contexts.
2. **Non-hosted tests** (`TEST_HOST: ""`) — linker fails because `@testable import` needs the app binary.
3. **`EnvironmentKey` with default value** — `@Observable` + `@Environment(Type.self)` doesn't support defaults. Would require custom environment keys for every observable.

## Prevention

- Always place `.environment()` as the last modifiers in the WindowGroup body.
- When adding `.overlay`, `.safeAreaInset`, or `.sheet` to the root view, verify environment-dependent views inside them still work.
- Run the app (not just build) after modifying `PirateRadioApp.swift` — this crash only surfaces at runtime.

## Related

- `PirateRadio/App/PirateRadioApp.swift:28-50` — the fixed modifier chain
- `PirateRadio/UI/Components/ToastManager.swift:83` — `ToastOverlay` that triggered the crash
