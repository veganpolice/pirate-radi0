---
title: "feat: Quick-Start Dial Home with Auto-Tune"
type: feat
date: 2026-02-28
status: reviewed
---

# Quick-Start Dial Home with Auto-Tune

## Overview

Replace the 3-button lobby with a radio dial as the home screen. When you open the app, you're immediately tuned into a friend's station — music starts playing. The dial shows notches for live stations. Drag to switch. "Start Broadcasting" goes live on an auto-assigned frequency. This is POC priority #2 from the [OST](../brainstorms/2026-02-28-opportunity-solution-tree.md).

## Problem Statement / Motivation

Today, opening Pirate Radio drops you in a lobby with three buttons. Getting to music requires tapping "Tune In," entering a 4-digit code, and waiting. That's 3+ steps and 5+ seconds — worse than just opening Spotify. If the social listening experience isn't *faster* than solo Spotify for the common case (friends are live), the app loses.

The hypothesis: if opening the app immediately puts music in your ears from a friend's station, the habit loop closes. No decisions, no codes — just turn it on and you're listening.

**Source:** [Brainstorm](../brainstorms/2026-02-28-quick-start-dial-home-brainstorm.md), [OST](../brainstorms/2026-02-28-opportunity-solution-tree.md) — Priority #2.

## Proposed Solution

### Architecture: Dial Home + Auto-Tune + Auto-Assigned Frequencies

The server gets a lightweight user registry (in-memory, populated on `/auth`) that auto-assigns frequencies. A new `GET /stations` endpoint returns live stations. The client replaces `SessionLobbyView` with `DialHomeView`, which fetches stations on appear, auto-tunes to the last-listened user's station, and renders the existing `FrequencyDial` (evolved in place) with live station notches.

```
APP LAUNCH (authenticated):
  DialHomeView.onAppear
    → GET /stations (returns live stations only)
    → Find last-tuned user (UserDefaults: lastTunedUserId)
    → If still live: joinSession(sessionId:) → NowPlayingView
    → If gone but others live: join first live station → NowPlayingView
    → If nobody live: show empty dial + "Start Broadcasting" CTA

DIAL NAVIGATION:
  User drags dial → snaps to live notch
    → cancel in-flight tune task
    → leaveSession() (if currently in one)
    → joinSession(sessionId:) → NowPlayingView

START BROADCASTING:
  leaveSession() (if listening) → createSession() → CreateSessionView
  (frequency auto-assigned by server on first createSession)

BACK TO DIAL:
  Dial button in NowPlayingView toolbar
    → leaveSession() → DialHomeView renders (session == nil)
    → re-fetch stations on appear
```

### Key Design Decisions (incorporating review feedback)

**Auto-assigned frequencies (DHH + Simplicity).** Server assigns a stable frequency per user on first `/auth` call. No frequency picker, no `POST /users/frequency`, no client-side frequency caching. If the server restarts, frequencies get reassigned — acceptable for POC. Eliminates an entire view, endpoint, and conflict resolution flow.

**Live stations only on the dial (Simplicity).** Don't show offline friends. The dial has notches only for currently broadcasting users. If nobody is live, empty dial with "Start Broadcasting" CTA. This eliminates offline notch rendering, dual haptic states, and the need for a full user registry in the API response.

**`lastTunedUserId` not `lastTunedJoinCode` (Kieran).** Join codes are ephemeral (1-hour expiry, change on session recreation). Persist the user ID instead — it survives session recreation and server restarts.

**Join by session ID, not join code (Kieran).** `GET /stations` returns `sessionId` directly. Add a `POST /sessions/join-by-id` endpoint (or modify existing join to accept either). This avoids the join-code-expiry problem for long-running stations.

**Task cancellation on rapid dial switching (Kieran).** `SessionStore` gets a `tuneTask: Task?` property. Each dial snap cancels the previous task before starting a new one. Prevents interleaved leaveSession/joinSession calls.

**Reset `isCreator` in `leaveSession` (Kieran).** Currently `isCreator` persists across session boundaries. Reset it to `false` in `leaveSession()` to prevent stale DJ permissions.

**Re-fetch stations on return to dial (DHH).** When navigating back from NowPlayingView, `DialHomeView.onAppear` re-fetches stations. Friends who went live while you were listening will appear.

**Evolve `FrequencyDial` in place (DHH + Simplicity).** Don't create a new `StationDial` component. Add a `stations` parameter to the existing `FrequencyDial`. Keep one dial component.

**One session at a time.** `SessionStore.session` stays a single optional. "Start Broadcasting" while listening → `leaveSession()` first. No session multiplexing for POC.

**`JoinSessionView` and `DiscoveryView` become dead code (DHH).** The dial IS the join flow. Mark old views as deprecated; delete in a cleanup pass.

## Technical Approach

### Phase 1: Server — User Registry & Stations Endpoint

The foundation. ~40 LOC.

**Server changes** (`server/index.js`):

```javascript
// New: user registry — auto-populated on /auth, lost on restart
const userRegistry = new Map(); // userId → { displayName, frequency }
let nextFrequency = 88.1; // auto-increment, 0.2 MHz steps

function assignFrequency() {
  const freq = nextFrequency;
  nextFrequency = Math.round((nextFrequency + 0.2) * 10) / 10;
  if (nextFrequency > 107.9) nextFrequency = 88.1; // wrap (won't happen with 10-30 users)
  return freq;
}

// In POST /auth handler, after JWT creation:
if (!userRegistry.has(userId)) {
  userRegistry.set(userId, {
    displayName: req.body.displayName,
    frequency: assignFrequency(),
  });
} else {
  userRegistry.get(userId).displayName = req.body.displayName;
}
```

```javascript
// GET /stations — list live stations only
app.get("/stations", authenticateHTTP, (req, res) => {
  const stations = [];
  for (const session of sessions.values()) {
    if (!session.isPlaying && session.queue.length === 0) continue; // skip idle

    const user = userRegistry.get(session.creatorId);
    if (!user) continue;

    stations.push({
      userId: session.creatorId,
      displayName: user.displayName,
      frequency: user.frequency,
      sessionId: session.id,
      currentTrack: session.currentTrack,
    });
  }
  res.json({ stations });
});
```

```javascript
// POST /sessions/join-by-id — join by session ID (no code expiry issue)
app.post("/sessions/join-by-id", authenticateHTTP, (req, res) => {
  const { sessionId } = req.body;
  if (!sessionId || typeof sessionId !== "string") {
    return res.status(400).json({ error: "sessionId required" });
  }
  const session = sessions.get(sessionId);
  if (!session) {
    return res.status(404).json({ error: "Session not found" });
  }
  const djMember = session.members.get(session.djUserId);
  res.json({
    id: session.id,
    joinCode: session.joinCode,
    djUserId: session.djUserId,
    djDisplayName: djMember?.displayName || session.djUserId,
    memberCount: session.members.size,
  });
});
```

**Tasks:**
- [x] Add `userRegistry` Map and `assignFrequency()` to server state (`server/index.js:~30`)
- [x] Update `POST /auth` to auto-register user with assigned frequency (`server/index.js:~80`)
- [x] Implement `GET /stations` — live sessions only, with frequency from registry (`server/index.js:~170`)
- [x] Implement `POST /sessions/join-by-id` — join without code expiry concern (`server/index.js:~175`)
- [x] Test: `GET /stations` returns empty → one live station → station goes idle → disappears
- [x] Test: `POST /sessions/join-by-id` success, 404 for missing session, 400 for missing ID

**Success criteria:** `GET /stations` returns live stations with frequencies. `POST /sessions/join-by-id` lets clients join without code expiry issues.

---

### Phase 2: Client — DialHomeView, Auto-Tune & Navigation

Everything client-side in one phase. Build the data layer and UI together — they only make sense together. ~150 LOC.

**New model** (`PirateRadio/Core/Models/Station.swift`):

```swift
/// A live station on the dial.
struct Station: Codable, Identifiable {
    let userId: String
    let displayName: String
    let frequency: Double
    let sessionId: String
    let currentTrack: Track?

    var id: String { userId }
}
```

**SessionStore additions** (`PirateRadio/Core/Sync/SessionStore.swift`):

```swift
// New state
var stations: [Station] = []
var isAutoTuning = false
private var tuneTask: Task<Void, Never>?

// Fetch live stations from server
func fetchStations() async {
    guard let token = try? await getBackendToken() else { return }
    // GET /stations with bearer token
    // Decode into [Station], update self.stations
}

// Auto-tune: find best station and join
func autoTune() async {
    isAutoTuning = true
    defer { isAutoTuning = false }

    await fetchStations()

    guard let target = pickAutoTuneTarget() else { return }
    await joinSessionById(target.sessionId)
    if error == nil {
        UserDefaults.standard.set(target.userId, forKey: "lastTunedUserId")
    }
}

private func pickAutoTuneTarget() -> Station? {
    guard !stations.isEmpty else { return nil }
    let lastUserId = UserDefaults.standard.string(forKey: "lastTunedUserId")
    return stations.first(where: { $0.userId == lastUserId })
           ?? stations.first
}

// Tune to a specific station (cancel-and-replace for rapid switching)
func tuneToStation(_ station: Station) {
    tuneTask?.cancel()
    tuneTask = Task {
        if session != nil {
            await leaveSession()
        }
        guard !Task.isCancelled else { return }
        await joinSessionById(station.sessionId)
        if error == nil {
            UserDefaults.standard.set(station.userId, forKey: "lastTunedUserId")
        }
    }
}

// Join by session ID (new endpoint)
func joinSessionById(_ sessionId: String) async {
    // POST /sessions/join-by-id with { sessionId }
    // Same flow as joinSession(code:) but hits different endpoint
    // Reuse connectToSession() after receiving response
}
```

**Fix `leaveSession()` — reset `isCreator` (Kieran):**

```swift
func leaveSession() async {
    await syncEngine?.stop()
    syncEngine = nil
    session = nil
    isCreator = false          // ← ADD THIS
    connectionState = .disconnected
}
```

**Evolve `FrequencyDial` in place** (`PirateRadio/UI/Components/FrequencyDial.swift`):

Add an optional `stations` parameter. When provided, derive detents from station frequencies and show the snapped station's name in the center instead of the numeric value.

```swift
struct FrequencyDial: View {
    @Binding var value: Double
    let color: Color
    var detents: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
    var onDetentSnap: ((Double) -> Void)?

    // NEW: optional station data for dial-home mode
    var stations: [Station] = []
    var onTuneToStation: ((Station) -> Void)?

    // When stations is non-empty:
    //   - detents derived from stations.map { frequencyToDialValue($0.frequency) }
    //   - tick marks at station positions glow PirateTheme.signal
    //   - center label shows snapped station's displayName + frequency
    //   - onDetentSnap triggers onTuneToStation with the matched station
}
```

Key changes to `FrequencyDial`:
- Add `stations: [Station]` and `onTuneToStation: ((Station) -> Void)?` parameters
- When `stations` is non-empty, derive detents from station frequencies mapped to 0.0–1.0
- Render station ticks with `PirateTheme.signal` glow (live stations only, so all notches glow)
- Center label: snapped station's name + frequency, or "Scanning..." between notches
- `onDetentSnap` fires `onTuneToStation` with the matched station
- When `stations` is empty, existing behavior unchanged (backwards compatible)

**New `DialHomeView`** (`PirateRadio/UI/Home/DialHomeView.swift`):

```swift
/// The radio dial home screen. Auto-tunes on appear.
struct DialHomeView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager

    @State private var dialValue: Double = 0.5

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 24) {
                // Tuning header: "Tuning in to Aaron..." or "Nobody's on"
                tuningHeader

                // The dial with live station notches
                FrequencyDial(
                    value: $dialValue,
                    color: PirateTheme.signal,
                    stations: sessionStore.stations,
                    onTuneToStation: { station in
                        sessionStore.tuneToStation(station)
                    }
                )

                // "Start Broadcasting" button
                Button("Start Broadcasting") {
                    Task { await startBroadcasting() }
                }
                .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))
            }
            .padding()
        }
        .task {
            await sessionStore.autoTune()
        }
        .onAppear {
            // Re-fetch on return from NowPlayingView
            if !sessionStore.isAutoTuning {
                Task { await sessionStore.fetchStations() }
            }
        }
    }

    private func startBroadcasting() async {
        if sessionStore.session != nil {
            await sessionStore.leaveSession()
        }
        await sessionStore.createSession()
    }
}
```

**Navigation change** (`PirateRadioApp.swift:~144`):

```swift
// Replace SessionLobbyView() with DialHomeView()
if sessionStore.session == nil {
    DialHomeView()
}
```

**Back-to-dial from NowPlayingView** (`NowPlayingView.swift`):

```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        Button {
            Task { await sessionStore.leaveSession() }
        } label: {
            Image(systemName: "dial.low")
                .foregroundColor(PirateTheme.signal)
        }
    }
}
```

When `leaveSession()` sets `session = nil`, `SessionRootView` automatically renders `DialHomeView`.

**Tasks:**
- [x] Create `Station` model — 5 fields, live stations only (`PirateRadio/Core/Models/Station.swift`)
- [x] Add `stations`, `isAutoTuning`, `tuneTask` to `SessionStore` (`SessionStore.swift`)
- [x] Implement `fetchStations()` — GET /stations with bearer token (`SessionStore.swift`)
- [x] Implement `autoTune()` — fetch → pick target by `lastTunedUserId` → join (`SessionStore.swift`)
- [x] Implement `tuneToStation()` — cancel-and-replace pattern for rapid switching (`SessionStore.swift`)
- [x] Implement `joinSessionById()` — POST /sessions/join-by-id, reuse `connectToSession()` (`SessionStore.swift`)
- [x] Fix `leaveSession()` — add `isCreator = false` reset (`SessionStore.swift`)
- [x] Persist `lastTunedUserId` on every successful join (`SessionStore.swift`)
- [x] Evolve `FrequencyDial` — add `stations` parameter, derive detents, show station names, `onTuneToStation` callback (`FrequencyDial.swift`)
- [x] Create `DialHomeView` — dial, tuning header, "Start Broadcasting" button, auto-tune on `.task`, re-fetch on `.onAppear` (`PirateRadio/UI/Home/DialHomeView.swift`)
- [x] Replace `SessionLobbyView()` with `DialHomeView()` in `SessionRootView` (`PirateRadioApp.swift:~144`)
- [x] Add dial toolbar button to `NowPlayingView` for back-to-dial (`NowPlayingView.swift`)
- [ ] Handle auto-tune join failure — toast "Station went offline", stay on dial
- [ ] Handle `GET /stations` failure — show empty dial + error toast
- [ ] Test: app launch → auto-tune → NowPlayingView with correct station
- [ ] Test: rapid dial switching → only final station joined, no interleaving
- [ ] Test: back-to-dial → leaveSession → DialHomeView renders → stations re-fetched

**Success criteria:** Opening the app auto-tunes to a live friend. Dial shows live stations as glowing notches. Dragging switches stations safely. "Start Broadcasting" goes live. Navigation between dial and NowPlayingView is seamless.

---

## Acceptance Criteria

### Functional Requirements

- [ ] App launch with live friends → music playing within ~3 seconds (best-effort)
- [ ] App launch with no live friends → empty dial with "Start Broadcasting" CTA
- [ ] Dial shows live stations as glowing notches with auto-assigned frequencies
- [ ] Dragging dial to a live notch tunes in → transitions to NowPlayingView
- [ ] "Start Broadcasting" → go live (frequency auto-assigned, no picker)
- [ ] Back-to-dial from NowPlayingView leaves session and returns to dial
- [ ] Last-tuned user is remembered across app restarts (UserDefaults)
- [ ] Returning to dial re-fetches stations (friends who went live appear)

### Non-Functional Requirements

- [ ] No crashes on `GET /stations` failure or slow network
- [ ] No concurrent session state — rapid switching cancels in-flight tasks
- [ ] No orphaned WebSocket connections on station switching
- [ ] `isCreator` correctly reset on leave/join cycle

### Quality Gates

- [ ] Server endpoint tests: GET /stations, POST /sessions/join-by-id, auto-assign frequency on auth
- [ ] Client: auto-tune happy path
- [ ] Client: rapid dial switching (cancel-and-replace)
- [ ] Navigation: dial → NowPlaying → dial round-trip

## Dependencies & Prerequisites

- **Phase 1 plan shipped:** Server-side autonomous queue advancement is working.
- **Spotify Premium required:** Non-premium users see an error toast (existing guard).
- **In-memory server state:** Frequencies and registry wipe on restart. Accepted for POC.
- **Global group:** All users see each other. No invites needed.

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SPTAppRemote wake adds 3-10s to auto-tune | High | Medium | Show dial immediately, music starts when ready. Don't block UI. |
| Server restart reassigns frequencies | Certain | Low | Accepted for POC. Users get new positions. Not a hypothesis-breaker. |
| Race: rapid dial switching corrupts state | High | High | Cancel-and-replace `tuneTask` pattern. Only final snap executes. |
| Race: station goes offline between fetch and join | Medium | Low | `joinSessionById` returns 404 → toast → stay on dial. |
| `@Environment` crash on new view hierarchy | Medium | Critical | Apply `.environment()` last in chain. (See: `docs/solutions/runtime-errors/swiftui-environment-modifier-ordering.md`) |
| `SessionStore` not initialized on relaunch | Medium | Critical | Create eagerly in `init()`. (See: `docs/solutions/runtime-errors/observable-environment-race-on-launch.md`) |
| `isCreator` stale after leave/join cycle | High | Medium | Reset in `leaveSession()`. (Kieran review finding.) |

## Implementation Order

```
Phase 1 (Server: Registry + Endpoints)     ← ~40 LOC server, 6 tasks
    ↓
Phase 2 (Client: Everything)               ← ~150 LOC Swift, 17 tasks
```

**Total: 2 phases, ~23 tasks, ~190 LOC.** Down from 4 phases, ~20 tasks, ~480 LOC in the original plan (63% LOC reduction per Simplicity review).

## What We're NOT Building (YAGNI)

- **Frequency picker** — auto-assign, no ceremony (DHH + Simplicity)
- **Offline notch rendering** — only show live stations (Simplicity)
- **User registry in API response** — derive from sessions Map (Simplicity)
- **Client-side frequency caching** — no restoration dance (DHH + Simplicity)
- **`StationDial` new component** — evolve `FrequencyDial` in place (DHH + Simplicity)
- **`POST /users/frequency` endpoint** — auto-assign eliminates it (all reviewers)
- **`FrequencyPickerView`** — eliminated with auto-assign (all reviewers)
- **Planet system** — global group for POC
- **Discover mode** — everyone is in one group
- **Multi-session support** — one session at a time
- **Auto-refresh/polling stations** — re-fetch on dial appear only
- **Tuning animation with CRT static** — future polish
- **Database** — in-memory is fine for POC

## Future Work (After POC Validates)

1. **Frequency picker ceremony** — let users claim vanity frequencies (the brainstorm wanted this; deferred per reviews)
2. **Offline friend notches** — show dim notches for known-but-inactive users
3. **Auto-refresh stations** — poll `GET /stations` every 30s
4. **Push notifications** — "Aaron is broadcasting on 98.7"
5. **Multi-session support** — your station stays live while you listen
6. **Tuning animation** — CRT static between stations
7. **Planet system** — persistent groups, deep link invites
8. **Persistence** — Redis/SQLite for user registry and frequencies

## Review Feedback Incorporated

- **DHH:** Auto-assign frequencies, evolve FrequencyDial in place, merge phases, re-fetch on return to dial, clarify dead code (JoinSessionView/DiscoveryView)
- **Kieran:** Cancel-and-replace for rapid switching, `lastTunedUserId` not joinCode, join-by-sessionId to avoid code expiry, reset `isCreator` in leaveSession, frequency conflict check in auto-assign
- **Simplicity:** Live stations only on dial, no user registry in API, no FrequencyPickerView, 2 phases not 4, ~190 LOC not ~480 LOC

## References & Research

### Internal References
- Brainstorm: `docs/brainstorms/2026-02-28-quick-start-dial-home-brainstorm.md`
- OST: `docs/brainstorms/2026-02-28-opportunity-solution-tree.md`
- Phase 1 plan (shipped): `docs/plans/2026-02-28-feat-station-per-user-queue-autonomous-playback-plan.md`
- FrequencyDial component: `PirateRadio/UI/Components/FrequencyDial.swift`
- SessionRootView nav: `PirateRadioApp.swift:130-149`
- SessionLobbyView (being replaced): `PirateRadio/UI/Session/SessionLobbyView.swift`
- SessionStore join flow: `PirateRadio/Core/Sync/SessionStore.swift:57-107`
- Server session management: `server/index.js:26-35, 517-543`
- Server auth endpoint: `server/index.js:77-90`

### Institutional Learnings
- Observable environment race on launch: `docs/solutions/runtime-errors/observable-environment-race-on-launch.md`
- Environment modifier ordering: `docs/solutions/runtime-errors/swiftui-environment-modifier-ordering.md`
- SPTAppRemote wake before play: `docs/solutions/integration-issues/sptappremote-wake-spotify-before-play.md`
- Double-play bug: `docs/solutions/integration-issues/statesync-double-play-dj-and-syncengine.md`
- WebSocket protocol mismatch: `docs/solutions/integration-issues/websocket-protocol-mismatch-silent-message-drop.md`
- setTimeout NaN guard: `docs/solutions/runtime-errors/settimeout-nan-drains-queue-instantly.md`
