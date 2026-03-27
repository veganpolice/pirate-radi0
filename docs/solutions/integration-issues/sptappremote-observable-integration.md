---
title: "SPTAppRemote Integration with SwiftUI @Observable Pattern"
category: integration-issues
tags: [spotify, sptappremote, observable, swift, ios-sdk, objc-interop, lazy-var, nsobject]
module: SpotifyAuth, SpotifyPlayer
symptoms:
  - "'lazy' cannot be used on a computed property"
  - "cannot declare conformance to 'NSObjectProtocol' in Swift"
  - "SPTAppRemote delegate methods not called on MainActor"
  - "0 tests executed with Swift Testing framework"
date: 2026-02-14
---

# SPTAppRemote Integration with SwiftUI @Observable Pattern

## Problem

Wiring Spotify's `SPTAppRemote` (Obj-C SDK) into a SwiftUI `@Observable` class produces multiple compile errors because `@Observable` transforms stored properties into computed ones, breaking `lazy var`, and SPTAppRemote delegates require `NSObjectProtocol` conformance.

## Root Cause

Three interop conflicts:

1. **@Observable + lazy var**: The `@Observable` macro rewrites stored properties as computed properties backed by the observation system. `lazy var` requires a stored property, so the compiler rejects it.

2. **@Observable + NSObject**: `SPTAppRemoteDelegate` inherits from `NSObjectProtocol`. A pure Swift class can't conform without inheriting `NSObject`.

3. **@MainActor + Obj-C delegates**: SPTAppRemote calls its delegate methods from arbitrary threads. Delegate methods on a `@MainActor` class must be marked `nonisolated` and bounce back to MainActor via `Task { @MainActor in }`.

## Solution

### 1. Use `@ObservationIgnored` for lazy SPTAppRemote

```swift
@Observable
@MainActor
final class SpotifyAuthManager: NSObject {
    @ObservationIgnored
    private(set) lazy var appRemote: SPTAppRemote = {
        let config = SPTConfiguration(
            clientID: Self.clientID,
            redirectURL: URL(string: Self.redirectURI)!
        )
        let remote = SPTAppRemote(configuration: config, logLevel: .debug)
        remote.delegate = self
        return remote
    }()
}
```

`@ObservationIgnored` tells `@Observable` to skip the property entirely, preserving `lazy var` semantics.

### 2. Inherit from NSObject

```swift
@Observable
@MainActor
final class SpotifyAuthManager: NSObject {
    override init() {
        super.init()
        // ...
    }
}
```

### 3. Use nonisolated delegates with Task bounce

```swift
extension SpotifyAuthManager: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.isConnectedToSpotifyApp = true
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: (any Error)?) {
        Task { @MainActor in
            self.isConnectedToSpotifyApp = false
        }
    }
}
```

### 4. Pass SPTAppRemote to actor with nonisolated(unsafe)

`SPTAppRemote` is an Obj-C class (not `Sendable`). To store it in a Swift actor:

```swift
actor SpotifyPlayer: MusicSource {
    nonisolated(unsafe) private let appRemote: SPTAppRemote

    init(appRemote: SPTAppRemote) {
        self.appRemote = appRemote
    }
}
```

### 5. Reuse PKCE token — no SPTSessionManager needed

SPTAppRemote can reuse an existing PKCE access token directly:

```swift
func connectAppRemote() {
    appRemote.connectionParameters.accessToken = existingPKCEToken
    appRemote.connect()
}
```

No separate `SPTSessionManager` auth flow is required.

## Prevention

- Always use `@ObservationIgnored` on `lazy var` properties inside `@Observable` classes.
- When an `@Observable` class needs Obj-C protocol conformance, inherit from `NSObject`.
- Mark all Obj-C delegate methods as `nonisolated` on `@MainActor` classes and bounce state updates via `Task { @MainActor in }`.
- Use `nonisolated(unsafe)` when passing non-Sendable Obj-C objects into Swift actors.

## Related

- [SwiftUI Environment Modifier Ordering](../build-errors/swiftui-environment-modifier-ordering.md)
- [NTP-Anchored Visual Sync](../integration-issues/ntp-anchored-visual-sync.md)
- [Spotify + Fly.io Dev Environment Setup](../integration-issues/spotify-flyio-dev-environment-setup.md)
