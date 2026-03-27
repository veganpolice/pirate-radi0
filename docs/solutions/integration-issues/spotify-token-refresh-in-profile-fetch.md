---
title: "Spotify profile fetch silently fails with expired token"
date: 2026-02-14
category: integration-issues
tags: [spotify, oauth, pkce, token-refresh, silent-failure]
module: PirateRadio.Core.Spotify
symptoms:
  - "userID is nil despite isAuthenticated being true"
  - "Start Broadcasting button does nothing"
  - "displayName not shown on lobby screen"
  - "No visible error — function fails silently"
  - "Works after fresh sign-in but not on relaunch"
severity: blocking
related:
  - docs/solutions/integration-issues/sptappremote-observable-integration.md
  - docs/solutions/integration-issues/spotify-flyio-dev-environment-setup.md
---

# Spotify Profile Fetch Silently Fails With Expired Token

## Problem

After app relaunch, `authManager.userID` is nil even though `isAuthenticated` is true and tokens exist in keychain. The "Start Broadcasting" button does nothing because `SessionStore.getBackendToken()` requires `userID`.

## Root Cause

`refreshUserProfile()` used the raw `accessToken` property directly:

```swift
// BAD: uses potentially expired token
private func refreshUserProfile() async {
    guard let token = accessToken else { return }
    // Spotify returns 401, guard silently returns
}
```

The access token from keychain was expired. The Spotify `/v1/me` endpoint returned 401, and the `guard let` silently ate the error. `userID` was never set.

## Solution

Use `getAccessToken()` which auto-refreshes expired tokens:

```swift
private func refreshUserProfile() async {
    do {
        let token = try await getAccessToken() // Auto-refreshes if expired
        // ... use token for API call
    } catch {
        logger.error("Profile fetch error: \(error)")
    }
}
```

Also add logging — the original code had `try?` and `guard let` that swallowed every error silently.

## Key Insight

**Never use raw token properties for API calls.** Always route through `getAccessToken()` which handles refresh. Any method that touches `accessToken` directly is a bug waiting for token expiry.

Pattern to follow:
- `accessToken` — private storage only, never use for API calls
- `getAccessToken()` — public accessor that refreshes if needed

## Prevention

- Grep for direct `accessToken` usage outside of `getAccessToken()` and keychain methods
- Add logging to all API calls — silent `try?` failures are debugging nightmares
- Test with expired tokens: set `tokenExpiry` to past date in keychain
