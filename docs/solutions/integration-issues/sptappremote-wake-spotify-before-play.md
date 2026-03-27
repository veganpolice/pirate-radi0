---
title: "SPTAppRemote requires Spotify app to be actively running"
date: 2026-02-14
category: integration-issues
tags: [spotify, sptappremote, playback, connection-refused, ios]
module: PirateRadio.Core.Spotify
symptoms:
  - "Connection refused on localhost:9095"
  - "SPTAppRemote connection failed: Stream error"
  - "App Remote not connected, skipping player state subscription"
  - "Playback callback timed out for track"
  - "No audio plays after selecting a track"
  - "Play command sent but nothing happens"
severity: blocking
related:
  - docs/solutions/integration-issues/sptappremote-observable-integration.md
---

# SPTAppRemote Requires Spotify App to Be Actively Running

## Problem

After selecting a track, no audio plays. Console shows "Connection refused" on port 9095 and "SPTAppRemote connection failed". The play command is sent but Spotify never receives it.

## Root Cause

SPTAppRemote communicates with the Spotify iOS app via a local TCP socket on port 9095. If Spotify isn't actively running (killed, suspended, or never opened), the socket doesn't exist and connection fails immediately.

`appRemote.connect()` silently fails — no audio, no visible error to the user.

## Solution

Before playing, check if AppRemote is connected. If not, wake Spotify using `authorizeAndPlayURI`:

```swift
func wakeSpotifyAndConnect() {
    guard let token = accessToken else { return }
    appRemote.connectionParameters.accessToken = token
    appRemote.authorizeAndPlayURI("") // Opens Spotify app, empty = don't auto-play
}
```

In the play flow, wait for connection:

```swift
func play(track: Track) async {
    if !authManager.isConnectedToSpotifyApp {
        authManager.wakeSpotifyAndConnect()
        // Wait up to 10s for connection
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if authManager.isConnectedToSpotifyApp { break }
        }
        guard authManager.isConnectedToSpotifyApp else {
            self.error = .playbackFailed(...)
            return
        }
    }
    // Now safe to send play command
    appRemote.playerAPI?.play("spotify:track:\(track.id)", ...)
}
```

## Key Insight

SPTAppRemote is **not** a background service — it's an IPC channel to a running app. Your app must ensure Spotify is alive before sending commands. `authorizeAndPlayURI("")` is the standard way to wake Spotify without auto-playing a track.

## User Experience

- User briefly switches to Spotify app, then returns to Pirate Radio
- Subsequent play commands work without switching (Spotify stays alive in background)
- If user force-kills Spotify, next play attempt re-wakes it

## Prevention

- Always check `appRemote.isConnected` before sending commands
- Don't assume connection persists — Spotify can be killed anytime
- Add a visible "Connecting to Spotify..." state in the UI rather than silent failure
