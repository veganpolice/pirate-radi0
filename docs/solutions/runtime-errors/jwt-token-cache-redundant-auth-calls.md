---
title: JWT Token Cache - Eliminate Redundant Auth Calls
date: 2026-02-28
category: runtime-errors
tags: [jwt, caching, networking, performance, auth]
module: PirateRadio/Core/Sync
severity: medium
symptoms:
  - 2-3 extra network round trips per app launch (50-200ms each)
  - Burst of /auth calls on rapid dial turns
  - Unnecessary server load on auth endpoint
---

## Problem

`getBackendToken()` called `POST /auth` on every backend request without caching. The auto-tune flow invokes it twice: once in `fetchStations()` and again in `joinSessionById()`. Each `tuneToStation()` call triggers `leaveSession()` + `joinSessionById()`, repeating the call. Rapid dial switching generates bursts of `/auth` requests despite tokens being valid for 24 hours.

## Solution

Added `cachedToken` and `tokenExpiry` fields to cache tokens and refresh 1 hour before expiry:

```swift
private var cachedToken: String?
private var tokenExpiry: Date?

private func getBackendToken() async throws -> String {
    // Return cached token if still valid (refresh 1 hour before expiry)
    if let token = cachedToken, let expiry = tokenExpiry,
       expiry > Date().addingTimeInterval(3600) {
        return token
    }

    // ... existing fetch logic ...

    cachedToken = response.token
    tokenExpiry = Date().addingTimeInterval(24 * 3600)
    return response.token
}
```

## Prevention

- Always cache tokens with known validity periods
- Use a refresh window (e.g., 1 hour before expiry) to avoid edge-case failures
- Consider that multi-step flows amplify uncached token costs
