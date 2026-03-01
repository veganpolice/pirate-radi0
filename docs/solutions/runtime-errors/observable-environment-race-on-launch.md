---
title: "@Observable environment race condition on app launch"
date: 2026-02-14
category: runtime-errors
tags: [swiftui, observable, environment, race-condition, onchange, state-init]
module: PirateRadio.App
symptoms:
  - "Fatal error: No Observable object of type SessionStore found"
  - "App crashes immediately on launch (not first install)"
  - "Works after fresh sign-in but crashes on subsequent launches"
  - "Crash only when keychain has cached tokens"
severity: blocking
related:
  - docs/solutions/runtime-errors/swiftui-environment-modifier-ordering.md
---

# @Observable Environment Race Condition on App Launch

## Problem

App crashes on launch with "No Observable object of type SessionStore found" but only when the user has previously authenticated (tokens cached in keychain).

## Root Cause

The `SessionStore` was created via `.onChange(of: authManager.isAuthenticated)` in the view body. On first sign-in this works because `isAuthenticated` *changes* from false to true. But on relaunch with cached tokens:

1. `SpotifyAuthManager.init()` loads tokens from keychain
2. Sets `isAuthenticated = true` immediately (value never *changes*)
3. `.onChange` never fires — `sessionStore` stays `nil`
4. SwiftUI renders `SessionRootView` which reads `@Environment(SessionStore.self)` — crash

```swift
// BAD: onChange only fires on *changes*, not initial values
.onChange(of: authManager.isAuthenticated) { _, isAuth in
    if isAuth { sessionStore = SessionStore(authManager: authManager) }
}
```

## Solution

Create `SessionStore` eagerly in `init()` when tokens already exist:

```swift
init() {
    let auth = SpotifyAuthManager()
    _authManager = State(initialValue: auth)
    // Create SessionStore immediately if already authenticated
    _sessionStore = State(initialValue:
        auth.isAuthenticated ? SessionStore(authManager: auth) : nil
    )
}
```

Keep the `.onChange` for when auth state changes *during* the session (sign-in/sign-out).

## Key Insight

`.onChange` is for state *transitions*, not initial state. If a downstream object depends on an initial condition being true, create it eagerly in `init()` rather than relying on `.onChange` to catch it.

## Prevention

- When using `@Observable` objects injected via `.optionalEnvironment()`, verify the object exists for all launch paths — not just the fresh sign-in path.
- Test with cached credentials, not just first-time flows.
