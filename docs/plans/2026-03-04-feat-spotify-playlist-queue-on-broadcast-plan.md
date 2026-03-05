---
title: "feat: Spotify Playlist Queue on Broadcast"
type: feat
date: 2026-03-04
status: reviewed
---

# Spotify Playlist Queue on Broadcast

## Overview

When a user taps "Start Broadcasting," CreateSessionView shows a tabbed UI — **Playlists** and **Top Tracks** — with pill-style tab buttons. Playlists are fetched on CreateSessionView appear. Tapping a playlist immediately fetches its tracks, plays the first one, and batch-enqueues the rest. No preview step — tap and go.

## Problem Statement / Motivation

Today, starting a broadcast drops you into CreateSessionView with top tracks and a search button. Building a good queue requires tapping tracks one at a time. If you already have a curated Spotify playlist, there's no way to use it. The result: broadcasting feels like work instead of "press play."

The hypothesis: if starting a broadcast is as easy as picking a playlist, DJs will broadcast more often and for longer.

## Proposed Solution

### Architecture

```
START BROADCASTING → CreateSessionView:
  .task → spotifyClient.getUserPlaylists() (fetched here, not DialHomeView)
  Tabbed UI: [Playlists] [Top Tracks]

  Playlists tab (default):
    → Show playlists (cover art, name, track count)
    → Tap playlist:
      1. Fetch tracks: GET /v1/playlists/{id}/tracks (limit 100)
      2. Filter: remove non-playable, invalid durationMs, episodes, local files
      3. Play first track: sessionStore.play(track: tracks[0])
      4. Verify play succeeded (currentTrack != nil)
      5. Batch-enqueue rest: syncEngine.sendBatchAddToQueue(tracks[1...])
      6. Navigate to NowPlayingView

  Top Tracks tab:
    → Existing getTopTracks() behavior (unchanged)

SERVER:
  New message: batchAddToQueue { tracks: [Track], nonce: String }
    → Validate: array, durationMs per track, queue cap
    → Append all atomically
    → Broadcast single queueUpdate
```

### Key Design Decisions

**Tabbed UI with inline pill styling.** Playlists and Top Tracks as peers. Pill buttons at the top toggle between them. Playlists tab is default. Styling inlined in CreateSessionView — no separate `PillButtonStyle` component (DHH + Simplicity review).

**Immediate play on playlist tap.** No preview screen. Tapping a playlist = committing to it. Matches the radio ethos — just press play. Toast confirms: "Added 47 tracks from 'Road Trip Vibes'."

**Batch enqueue (atomic server message).** New `batchAddToQueue` WebSocket message. Server appends all tracks in one operation, broadcasts one `queueUpdate`. Avoids 100 individual messages, eliminates interleaving race conditions.

**Append to end of queue.** Playlist tracks go after any existing queue items. Simple, no new server position logic.

**Fetch playlists on CreateSessionView appear (not DialHomeView).** Only DJs who tap "Start Broadcasting" pay the cost. Listeners tuning in via the dial never hit the playlist API. Playlists are `@State` local to the view — no need to cache on SessionStore since there's no navigation to survive (DHH review).

**No separate SpotifyPlaylist file.** `SpotifyPlaylist` struct defined in `SpotifyClient.swift` alongside other models, following existing pattern (DHH + Simplicity review).

**OAuth scope addition.** Add `playlist-read-private` and `playlist-read-collaborative` to scopes. For existing users: playlist fetch silently fails (catches error), falls back to Top Tracks tab. Users re-auth naturally when tokens expire. No special 403 detection or re-auth banner for POC (all reviewers agreed: defer).

**Verify play succeeded before batch enqueue.** After `await play(track:)`, check `session?.currentTrack != nil` before sending batch enqueue. Prevents orphan queue with no playing track (Kieran review: critical race condition fix).

**Client-side track filtering.** Before enqueuing, filter out: tracks with `is_playable == false`, tracks with missing/zero `durationMs` (prevents the NaN setTimeout queue drain bug), local files, podcast episodes.

**First 100 tracks only.** Spotify paginates at 100. We fetch one page. Server queue cap is also 100. No pagination for POC.

## Technical Approach

### Single Phase — All Changes

Ship as one PR. ~155 LOC across existing files. Zero new files.

#### 1. OAuth Scopes

**SpotifyAuth.swift** (~line 19-27):
```swift
// Add to scopes array:
"playlist-read-private",
"playlist-read-collaborative"
```

#### 2. SpotifyClient — Playlist Methods + Models

**SpotifyClient.swift** — new private models following existing pattern:
```swift
// Private response models (same pattern as SearchResponse, TopTracksResponse)
private struct PlaylistsResponse: Codable {
    let items: [PlaylistItem]
}

private struct PlaylistItem: Codable {
    let id: String
    let name: String
    let images: [SpotifyImage]
    let tracks: PlaylistTracksRef

    struct PlaylistTracksRef: Codable {
        let total: Int
    }
}

private struct PlaylistTracksResponse: Codable {
    let items: [PlaylistTrackItem]
}

private struct PlaylistTrackItem: Codable {
    let track: SpotifyTrack?
    let isLocal: Bool
    enum CodingKeys: String, CodingKey {
        case track
        case isLocal = "is_local"
    }
}
```

**Public model (in SpotifyClient.swift, non-private):**
```swift
struct SpotifyPlaylist: Identifiable {
    let id: String
    let name: String
    let imageURL: String?
    let trackCount: Int
}
```

**Methods:**
```swift
func getUserPlaylists(limit: Int = 20) async throws -> [SpotifyPlaylist] {
    let token = try await authManager.getAccessToken()
    // GET https://api.spotify.com/v1/me/playlists?limit=\(limit)
    // Map PlaylistItem → SpotifyPlaylist
}

func getPlaylistTracks(playlistId: String, limit: Int = 100) async throws -> [Track] {
    let token = try await authManager.getAccessToken()
    // GET https://api.spotify.com/v1/playlists/\(playlistId)/tracks?limit=\(limit)
    // Filter: non-nil track, not local, durationMs > 0, type == "track"
    // Map SpotifyTrack → Track (reuse existing mapping)
}
```

#### 3. Server — batchAddToQueue Handler

**server/index.js** (~line 526) — simple handler, no nonce Set (use queue-based nonce check like existing `addToQueue`):
```javascript
case "batchAddToQueue": {
    const { tracks, nonce } = data;
    if (!Array.isArray(tracks) || tracks.length === 0) break;

    // Idempotency: same pattern as addToQueue (check nonce in queue)
    if (session.queue.some((t) => t.nonce === nonce)) {
        ws.send(JSON.stringify({ type: "queueUpdate", data: { queue: session.queue } }));
        break;
    }

    // Enforce queue cap
    const available = MAX_QUEUE_SIZE - session.queue.length;
    for (const track of tracks.slice(0, available)) {
        const durationMs = Number(track.durationMs);
        if (!Number.isFinite(durationMs) || durationMs <= 0) continue;
        session.queue.push({
            ...track,
            durationMs,
            addedBy: senderId,
            nonce,
        });
    }

    broadcastToSession(session, {
        type: "queueUpdate",
        data: { queue: session.queue },
    });
    break;
}
```

#### 4. Client — SyncMessage + SyncEngine

**SessionTransport.swift** — add case to `SyncMessageType` enum:
```swift
case batchAddToQueue(tracks: [Track], nonce: String)
```

**WebSocketTransport.swift** — add to `encodeForServer()`:
```swift
case .batchAddToQueue(let tracks, let nonce):
    // Encode tracks array + nonce, following addToQueue pattern
```

**WebSocketTransport.swift** — add to `translate()` (no-op, server won't echo this back):
```swift
// Handle in default case — no action needed
```

**SyncEngine.swift** — add to `processMessage()` switch (no-op case):
```swift
case .batchAddToQueue:
    break // Server doesn't echo this back; queue comes via queueUpdate
```

**SyncEngine.swift** — new send method following existing `sendAddToQueue` pattern:
```swift
func sendBatchAddToQueue(tracks: [Track]) {
    let nonce = UUID().uuidString
    let message = SyncMessage(
        type: .batchAddToQueue(tracks: tracks, nonce: nonce),
        senderId: userId,
        timestamp: Date()
    )
    transport.send(message)
}
```

#### 5. UI — Tabbed CreateSessionView + Playlist List

**CreateSessionView.swift:**
```swift
enum BrowseTab: String, CaseIterable {
    case playlists = "Playlists"
    case topTracks = "Top Tracks"
}

@State private var selectedTab: BrowseTab = .playlists
@State private var isLoadingPlaylist = false
@State private var playlists: [SpotifyPlaylist] = []

// Tab selector (inline pill styling, no separate component)
HStack(spacing: 12) {
    ForEach(BrowseTab.allCases, id: \.self) { tab in
        Button(tab.rawValue) { selectedTab = tab }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(tab == selectedTab ? PirateTheme.signal : PirateTheme.void)
            .foregroundColor(tab == selectedTab ? PirateTheme.void : PirateTheme.signal)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(PirateTheme.signal, lineWidth: 1))
    }
}

// Content
switch selectedTab {
case .playlists:
    playlistList
case .topTracks:
    topTracksList  // existing top tracks code, extracted
}
```

**Playlist list (inline in CreateSessionView):**
```swift
@ViewBuilder
var playlistList: some View {
    if playlists.isEmpty {
        Text("No playlists found")
            .foregroundColor(PirateTheme.dimText)
    } else {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(playlists) { playlist in
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: playlist.imageURL ?? "")) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            PirateTheme.void
                        }
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(.headline)
                                .foregroundColor(PirateTheme.signal)
                            Text("\(playlist.trackCount) tracks")
                                .font(.caption)
                                .foregroundColor(PirateTheme.dimText)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isLoadingPlaylist else { return }
                        isLoadingPlaylist = true
                        Task {
                            await playPlaylist(playlist)
                            isLoadingPlaylist = false
                        }
                    }
                }
            }
        }
    }
}
```

**playPlaylist() — local to CreateSessionView (not on SessionStore):**
```swift
private func playPlaylist(_ playlist: SpotifyPlaylist) async {
    guard let client = spotifyClient else { return }
    do {
        let tracks = try await client.getPlaylistTracks(playlistId: playlist.id)
        guard !tracks.isEmpty else {
            toastManager.show("This playlist is empty")
            return
        }
        // Play first track
        await sessionStore.play(track: tracks[0])
        // Verify play succeeded before batch enqueue (Kieran: prevents orphan queue)
        guard sessionStore.session?.currentTrack != nil else { return }
        // Batch-enqueue the rest
        if tracks.count > 1 {
            sessionStore.syncEngine?.sendBatchAddToQueue(tracks: Array(tracks[1...]))
            toastManager.show("Added \(tracks.count - 1) tracks from '\(playlist.name)'")
        }
    } catch {
        toastManager.show("Couldn't load playlist")
    }
}
```

**Fetch playlists on CreateSessionView appear:**
```swift
.task {
    guard let client = spotifyClient else { return }
    do {
        playlists = try await client.getUserPlaylists()
    } catch {
        // Silent failure — Top Tracks tab still available
    }
}
```

#### Tasks (All in One Phase)

**SpotifyClient + Auth:**
- [x] Add `playlist-read-private` and `playlist-read-collaborative` to OAuth scopes (`SpotifyAuth.swift:~19`)
- [x] Add private response models: `PlaylistsResponse`, `PlaylistItem`, `PlaylistTracksResponse`, `PlaylistTrackItem` (`SpotifyClient.swift`)
- [x] Add `SpotifyPlaylist` struct (non-private) in `SpotifyClient.swift`
- [x] Implement `getUserPlaylists(limit:)` (`SpotifyClient.swift`)
- [x] Implement `getPlaylistTracks(playlistId:limit:)` — filter local files, episodes, invalid durationMs (`SpotifyClient.swift`)

**Server:**
- [x] Add `batchAddToQueue` case to WebSocket message handler — queue-based nonce check, durationMs validation, queue cap enforcement, single `queueUpdate` broadcast (`server/index.js:~526`)

**SyncMessage + SyncEngine (4 touch points):**
- [x] Add `batchAddToQueue(tracks: [Track], nonce: String)` to `SyncMessageType` enum (`SessionTransport.swift`)
- [x] Add encoding for `batchAddToQueue` in `encodeForServer()` (`WebSocketTransport.swift`)
- [x] Add no-op case in `translate()` for unhandled echo (`WebSocketTransport.swift`)
- [x] Add no-op case in `processMessage()` switch (`SyncEngine.swift`)
- [x] Implement `sendBatchAddToQueue(tracks:)` following existing `sendAddToQueue` pattern (`SyncEngine.swift`)

**UI:**
- [x] Add `BrowseTab` enum, `@State selectedTab`, `@State playlists`, `@State isLoadingPlaylist` to CreateSessionView
- [x] Add inline pill-style tab selector (no separate ButtonStyle)
- [x] Extract existing top tracks code into `topTracksList` computed property
- [x] Build `playlistList` view — inline playlist rows with cover art, name, track count
- [x] Implement `playPlaylist(_:)` — fetch tracks, play first, verify success, batch-enqueue rest, toast
- [x] Add `.task` to fetch playlists on CreateSessionView appear
- [x] Add loading state guard to prevent double-tap
- [x] Handle empty states (no playlists, empty playlist)

---

## Acceptance Criteria

### Functional Requirements

- [ ] CreateSessionView shows tabbed UI: Playlists (default) and Top Tracks
- [ ] Playlists fetched on CreateSessionView appear (up to 20)
- [ ] Tapping a playlist fetches tracks, plays first, batch-enqueues rest
- [ ] Toast confirms: "Added N tracks from 'Playlist Name'"
- [ ] Playlists show cover art, name, and track count
- [ ] Top Tracks tab preserves existing behavior
- [ ] Tracks with invalid durationMs, local files, and episodes are filtered out
- [ ] Queue cap (100) respected — excess tracks truncated by server

### Non-Functional Requirements

- [ ] Playlist fetch failure does not block broadcasting (falls back to Top Tracks tab)
- [ ] No double-enqueue from rapid tapping (loading state guard)
- [ ] Batch enqueue is atomic on server (one queueUpdate broadcast)
- [ ] Play first track verified before batch enqueue (no orphan queue)
- [ ] `batchAddToQueue` SyncMessageType case handled in all 4 code locations

## Dependencies & Prerequisites

- Dial Home + Auto-Tune plan shipped (done)
- Autonomous queue advancement working (done)
- Spotify Premium account required (existing guard)
- Users with old OAuth tokens: playlist fetch silently fails, top tracks still work

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Old tokens lack playlist scope → 403 | Certain (existing users) | Low | Silent failure, Top Tracks tab still works. Re-auth on next token expiry. |
| Playlist tracks missing durationMs → NaN queue drain | Medium | Critical | Client filters invalid tracks; server validates per-track in batchAddToQueue |
| Large playlist exceeds queue cap | Medium | Low | Server enforces cap; first N tracks added |
| play() fails → orphan queue | Medium | High | Verify `currentTrack != nil` after play() before batch enqueue |
| SyncMessage enum new case → compiler errors | Certain | Low | 4 touch points documented: enum, encodeForServer, translate, processMessage |

## What We're NOT Building

- **Playlist preview/track list** — tap = immediate play, no preview step
- **Liked Songs** — different API, potentially thousands of tracks
- **Playlist search/filtering** — just show the first 20
- **Playlist pagination** — one page (20 playlists) is enough for POC
- **Track pagination within playlist** — one page (100 tracks), matches queue cap
- **Insert-at-front queue position** — append to end, simpler
- **DialHomeView prefetch** — fetch on CreateSessionView only (DHH: don't tax listeners)
- **SessionStore playlist cache** — view-local state is sufficient (DHH: no navigation to survive)
- **403 scope detection / re-auth banner** — silent failure + natural re-auth (all reviewers: defer)
- **Separate PillButtonStyle component** — inline styling (Simplicity: one usage site)
- **Separate SpotifyPlaylist.swift file** — inline in SpotifyClient.swift (DHH: follow pattern)
- **processedNonces Set on server** — use existing queue-based nonce check (Kieran: consistency)

## Review Feedback Incorporated

- **DHH:** Don't put playlist logic on SessionStore (it has no SpotifyClient dependency). Fetch on CreateSessionView, not DialHomeView. Keep SpotifyPlaylist in SpotifyClient.swift. Inline PillButtonStyle. Delete PlaylistOwner model. Follow existing SyncEngine pattern — use [Track] not [String: Any]. One phase, one PR.
- **Kieran:** Verify play() succeeded before batch enqueue (prevents orphan queue). batchAddToQueue with [String: Any] breaks Codable — use [Track]. New SyncMessageType case needs 4 touch points (enum, encode, translate, processMessage). processedNonces never initialized — use queue-based nonce check instead. 403 reuses .spotifyNotPremium error — catch silently for POC.
- **Simplicity:** Merge all phases. Drop cache TTL (simple emptiness check). Drop 403 detection. Drop nonce Set. Drop PlaylistOwner. Inline PlaylistRow. ~155 LOC total, 0 new files.

## References & Research

### Internal References
- Dial Home plan (shipped): `docs/plans/2026-02-28-feat-quick-start-dial-home-auto-tune-plan.md`
- SpotifyClient (existing pattern): `PirateRadio/Core/Spotify/SpotifyClient.swift`
- SpotifyAuth scopes: `PirateRadio/Core/Spotify/SpotifyAuth.swift:19-27`
- SessionStore queue ops: `PirateRadio/Core/Sync/SessionStore.swift:311-317`
- SyncEngine addToQueue: `PirateRadio/Core/Sync/SyncEngine.swift:182-192`
- SyncMessageType enum: `PirateRadio/Core/Protocols/SessionTransport.swift:22-35`
- WebSocketTransport encode: `PirateRadio/Core/Networking/WebSocketTransport.swift:309-364`
- WebSocketTransport translate: `PirateRadio/Core/Networking/WebSocketTransport.swift:155-227`
- Server queue handler: `server/index.js:526-544`
- CreateSessionView: `PirateRadio/UI/Session/CreateSessionView.swift`
- DialHomeView: `PirateRadio/UI/Home/DialHomeView.swift`

### Institutional Learnings
- Token refresh in API calls: `docs/solutions/integration-issues/spotify-token-refresh-in-profile-fetch.md` — always use `getAccessToken()`, never raw token
- NaN setTimeout queue drain: `docs/solutions/runtime-errors/settimeout-nan-drains-queue-instantly.md` — validate durationMs before enqueue
- Observable environment race on launch: `docs/solutions/runtime-errors/observable-environment-race-on-launch.md` — SessionStore eager init
- SPTAppRemote wake before play: `docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md` — wake Spotify before playback
- Server queue advancement timer: `docs/solutions/architecture-patterns/server-side-queue-advancement-timer.md` — always validate durationMs with isFinite
