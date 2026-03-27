---
title: "feat: Pirate Radio UI Demo — All Features, No Backend"
type: feat
date: 2026-02-14
---

# Pirate Radio UI Demo — All Features, No Backend

## Overview

Build out every creative feature in the Pirate Radio app as **UI-only with mock data**, so the full experience can be demoed by tapping through the app. No backend wiring, no Spotify SDK calls — just beautiful, animated, interactive screens with placeholder music, images, and rich transitions. The goal is to make someone pick up the phone and feel the product.

## Technical Approach

All features use the existing demo mode (`PirateRadioApp.demoMode = true`). New mock managers drive state changes on timers and user interaction. No network calls. Album art uses Spotify CDN URLs (public, no auth needed). Haptics on everything.

### New Files to Create

```
PirateRadio/
├── Core/
│   └── Mock/
│       ├── MockData.swift              # All mock tracks, members, sessions, stats
│       └── MockTimerManager.swift      # Drives fake events (requests, votes, joins)
├── UI/
│   ├── Onboarding/
│   │   └── OnboardingView.swift        # 3-page first-launch flow
│   ├── Components/
│   │   ├── ToastManager.swift          # In-app notification toast system
│   │   ├── TrackProgressBar.swift      # Animated progress with scrubbing
│   │   ├── VinylArtView.swift          # Album art with breathing/spin animation
│   │   ├── WalkieTalkieButton.swift    # Floating PTT button + recording UI
│   │   └── BPMGauge.swift              # Speedometer-style energy indicator
│   ├── Session/
│   │   ├── DJModePicker.swift          # Solo / Collab / Hot-Seat selector
│   │   ├── SessionSettingsView.swift   # DJ management panel
│   │   ├── MemberProfileCard.swift     # Tap-to-view crew member details
│   │   └── DiscoveryView.swift         # Mountain social / browse crews
│   ├── NowPlaying/
│   │   ├── RequestsView.swift          # DJ incoming request inbox
│   │   ├── HotSeatBanner.swift         # Countdown + "YOUR TURN" transition
│   │   ├── SignalLostOverlay.swift      # Disconnection animation
│   │   └── SessionRecapView.swift      # End-of-session stats card
│   └── Chairlift/
│       └── ChairliftModeView.swift     # Simplified chairlift UI overlay
```

### Models to Extend

```swift
// Add to Session.swift
enum DJMode: String, Codable, CaseIterable {
    case solo = "Solo DJ"
    case collaborative = "Collab Queue"
    case hotSeat = "Hot Seat"
}

// Add to Session
var djMode: DJMode
var hotSeatSongsPerDJ: Int          // default 3
var hotSeatSongsRemaining: Int

// Add to Session.Member
var tracksAdded: Int
var votesCast: Int
var djTimeMinutes: Int
var avatarColor: Color              // random neon color for demo

// Add to Track
var votes: Int                      // net score for collab queue
var requestedBy: String?            // who requested this track
var isUpvotedByMe: Bool
var isDownvotedByMe: Bool
```

---

## Implementation Phases

### Phase 1: Foundation — Mock Data + Toast System + Progress Bar

**Goal:** Rich mock data driving the app, toast notifications, and track progress. These are dependencies for everything else.

#### MockData.swift
- **30 curated tracks** with real Spotify album art URLs, names, artists, durations
  - Mix of genres that fit the vibe: Daft Punk, LCD Soundsystem, Tame Impala, Flume, ODESZA, The Weeknd, Arctic Monkeys, Gorillaz, Justice, Kavinsky, M83, MGMT, Parcels, Rüfüs Du Sol, etc.
- **8 mock crew members** with fun ski names: "DJ Powder", "Shredder", "Avalanche", "Mogul Queen", "Après Amy", "Gondola Greg", "Fresh Tracks", "Black Diamond"
- **5 mock sessions** for discovery: different crews, different now-playing tracks, varied member counts (2-8), fake distances ("0.3 mi", "1.2 mi")
- Mock session stats: total time, tracks played, per-member DJ time, top track

#### MockTimerManager.swift
- Observable class that fires fake events on timers when demo mode is active
- Events: member joins (random 15-30s), song request comes in (random 20-40s), vote cast on queue track (random 5-10s), hot-seat countdown ticks
- Each event triggers a toast notification
- Start/stop with session lifecycle

#### ToastManager.swift
- `@Observable` singleton, injected via environment
- Toast types: `.memberJoined`, `.memberLeft`, `.songRequest`, `.djChanged`, `.modeChanged`, `.requestAccepted`, `.requestDeclined`, `.voteCast`, `.signalLost`, `.reconnected`
- Each toast: icon + message + color (signal/broadcast/flare) + 4s auto-dismiss
- Stack max 3, oldest auto-pops
- Slide in from top with spring animation
- Swipe to dismiss

#### TrackProgressBar.swift
- Horizontal bar showing elapsed / total
- Animated fill using `TimelineView` (updates every 0.5s)
- Time labels: "1:24 / 3:28" format in PirateTheme.body
- Bar color: `PirateTheme.signal` with neon glow
- DJ mode: draggable thumb for scrubbing (60pt hit target)
- Listener mode: read-only, no thumb
- Paused: bar stops, glow dims

#### VinylArtView.swift
- Wraps `AsyncImage` for album art
- **Breathing animation**: subtle scale pulse 1.0 → 1.02 over 2s, continuous when playing
- **Neon glow**: intensifies on beat (fake: oscillate glow intensity 0.2-0.5 every 0.8s)
- **Paused state**: scale snaps to 1.0, glow dims to 0.1
- Corner radius 8, clip shape
- Drop shadow matching dominant color (use signal color)

### Phase 2: DJ Modes + Queue Voting + Requests

**Goal:** All three DJ modes work with visible behavior differences.

#### DJModePicker.swift
- Shown in `CreateSessionView` before session is created
- 3 large cards, one per mode, with icon + name + one-line description:
  - Solo DJ: `antenna.radiowaves.left.and.right` — "You control the music"
  - Collab Queue: `hand.thumbsup` — "Everyone votes on what plays next"
  - Hot Seat: `arrow.triangle.2.circlepath` — "DJ rotates every few songs"
- Selected card glows with `PirateTheme.broadcast`
- Haptic on selection
- Flows into session creation

#### QueueView.swift (enhance existing)
- **Collab mode additions:**
  - Each track row shows vote count badge (net score)
  - Thumbs up / thumbs down buttons per track (toggle, haptic)
  - Queue auto-sorts by vote count (with reorder animation)
  - "Added by [Name]" label under track
- **Hot-seat mode:** same as solo but shows "DJ: [Name]" header
- **Solo mode:** unchanged (DJ full control)

#### RequestsView.swift
- Sheet presented from badge button on Now Playing (DJ only, solo mode)
- Badge shows pending request count (red dot)
- List of requested tracks with requester avatar + name
- Each row: track info + Accept (checkmark, green) / Decline (x, red) buttons
- Accept: adds to queue + toast to requester "DJ accepted your request!"
- Decline: removes + toast "DJ passed on your request"
- Empty state: "No requests yet" with radio icon

#### HotSeatBanner.swift
- Persistent banner below track header in hot-seat mode
- Shows: "DJ: [Name] • [N] songs left" with countdown
- When countdown hits 0:
  - Full-screen takeover: dark overlay + "YOUR TURN TO DJ" in large neon display font
  - Crown icon animates from old DJ avatar to new DJ avatar (arc path, 800ms)
  - Heavy haptic burst
  - 2.5s display, then fade to Now Playing with new DJ controls
- If not your turn: "Now DJing: [Name]" banner update with transition

### Phase 3: Session Settings + Member Profiles + Onboarding

**Goal:** Settings panel, member interaction, and first-launch experience.

#### SessionSettingsView.swift
- Modal sheet from gear icon (top-right of Now Playing)
- **DJ sees:**
  - DJ Mode section: current mode badge, "Change Mode" button → DJModePicker
  - Hot-seat config: "Rotate every [N] songs" stepper (1-10)
  - Members section: list with kick button (red, confirmation alert)
  - Session code: display + "Regenerate Code" button (confirmation alert)
  - "End Session" button (red, bottom, confirmation → triggers recap)
- **Listener sees:**
  - Read-only mode badge
  - Member list (no kick)
  - Session code (for sharing)
  - "Leave Session" button

#### MemberProfileCard.swift
- Presented as bottom sheet when tapping crew avatar in crew strip
- Layout:
  - Large avatar circle with role-colored ring (magenta DJ, cyan listener)
  - Display name in display font
  - Role badge: "DJ" or "Listener"
  - Stats grid: Tracks Added | Votes Cast | DJ Time
  - **DJ actions** (only visible if you're DJ):
    - "Pass DJ" button (hot-seat/solo mode) → confirmation → crown animation
  - Dismiss by drag or tap outside

#### OnboardingView.swift
- 3-page horizontal pager with page indicators
- Forward swipe only, "Skip" button top-right
- **Page 1: "PIRATE RADIO"**
  - Large animated frequency dial spinning through stations
  - CRT static fading in/out
  - "Your crew. Your music. Perfectly synced." subtitle
- **Page 2: "HOW IT WORKS"**
  - Animated diagram: DJ phone (magenta glow) → signal waves → listener phones (cyan glow)
  - "One DJ controls the music. Everyone hears it at the same time."
  - Three mini icons: 🎧 Sync • 📻 Tune In • 🎿 Ride
- **Page 3: "SPOTIFY PREMIUM"**
  - Spotify logo + "Everyone needs Spotify Premium"
  - "Each person streams from their own account — we keep you in sync"
  - "Get Started" button (GloveButtonStyle, broadcast color)
- All text in PirateTheme fonts, void background, neon accents
- Shown once (UserDefaults flag), skippable

### Phase 4: Signal Lost + Walkie-Talkie + Chairlift Mode + BPM

**Goal:** The wow-factor features that make people say "wait, show me that again."

#### SignalLostOverlay.swift
- Full-screen overlay triggered by mock timer or debug button
- **Animation sequence:**
  1. CRT static fades in (0→0.8 intensity over 0.5s)
  2. Now Playing dims underneath (0.3 opacity)
  3. "SIGNAL LOST" text pulses in flare color
  4. "Searching for signal..." with animated dots
  5. After 3s: static fades out (0.8→0 over 1s)
  6. "SIGNAL LOCKED" flash in signal color
  7. Now Playing fades back to full
- Heavy haptic on lost, medium on reconnected
- Toast: "Back on air!" on reconnect

#### WalkieTalkieButton.swift
- Floating circular button (60pt), bottom-right of Now Playing
- Icon: `mic.fill` in flare color
- **Press-and-hold to "record":**
  - Button scales up 1.2x with broadcast glow
  - Circular progress ring counts down 10s max
  - Waveform visualization (fake: animated random bars)
  - "Recording..." label
- **Release:**
  - Button snaps back
  - Toast: "Voice clip sent to crew!"
  - Fake incoming clips from mock members appear as bubbles above the button
  - Bubble: avatar + waveform + "3s" duration label + auto-dismiss after 5s
- No actual audio recording — purely visual demo

#### ChairliftModeView.swift
- Toggle in SessionSettingsView: "Chairlift Mode"
- When active, overlays/modifies Now Playing:
  - Crew strip hidden (everyone's together on the chair)
  - Album art enlarged to 80% width
  - Controls simplified: just play/pause + skip (larger, 80pt targets)
  - "CHAIRLIFT MODE" badge at top with chairlift icon (🚡 or custom)
  - "Auto-DJ" toggle: when on, shows "Up Next" suggestions banner with genre labels
  - Background color subtly shifts to darker (more cozy/chairlift vibe)
- Toggle off: smooth transition back to full Now Playing

#### BPMGauge.swift
- Mini speedometer (80x80pt) shown in Now Playing top-right corner
- Semi-circular gauge with tick marks
- Three zones colored: Chill (signal), Cruise (flare), Sprint (broadcast)
- Needle animated to current "BPM" (mock: oscillates between zones over 10s)
- Current BPM number below: "128 BPM"
- Subtle glow matching current zone color
- Only visible when a track is playing

### Phase 5: Discovery + Session Recap + Polish

**Goal:** The social features and the satisfying ending. Plus animation polish across everything.

#### DiscoveryView.swift
- Accessed from new "Discover" button on SessionLobbyView
- Modal sheet with FM radio dial metaphor at top:
  - FrequencyDial repurposed, tuning through mock sessions
  - As dial turns, session list below filters/highlights nearest frequency
  - CRT static between stations
- **Session list:**
  - Each row: crew name, frequency ("107.3 FM"), member count, now playing (mini album art + track name), distance ("0.3 mi away")
  - Tap row → expanded card: full now playing, member list, "Tune In" button
  - "Tune In" = join as eavesdrop listener (navigates to Now Playing in read-only)
- 8 mock sessions with curated variety
- Empty state: "No crews nearby. Start your own!" (shouldn't appear in demo)

#### SessionRecapView.swift
- Full-screen modal presented when "End Session" tapped (after confirm)
- **Animated card build-up:**
  1. "SESSION COMPLETE" header in display font with neon glow (0.3s)
  2. Total time counter animates up: "2h 34m" (0.5s count-up)
  3. Tracks played counter: "47 tracks" (0.3s count-up, staggered)
  4. Top track: album art + name bloom in (0.5s scale from 0)
  5. Crew highlights flip in as cards:
     - "Most Requests: Shredder (12)"
     - "Top DJ: DJ Powder (1h 15m)"
     - "Vote Machine: Avalanche (38 votes)"
  6. DJ leaderboard bar chart (animated bars growing)
- "Share" button → renders card as image → system share sheet
- "Done" button → returns to Session Lobby
- Pirate Radio watermark/logo at bottom

#### Animation Polish (across all existing views)

- **Now Playing staggered entrance:**
  - Album art: slides in from left, 0ms delay
  - Track title: fades in from right, 200ms delay
  - Progress bar: grows width from 0, 400ms delay
  - Controls: scale up from 0.8, 600ms delay
  - Crew strip: slides up from bottom, 800ms delay
  - Use `.transition(.asymmetric(...))` + `withAnimation(.spring(duration: 0.5))`

- **Screen transitions:**
  - Lobby → Now Playing: matched geometry on app title
  - Session creation: zoom transition on session code
  - All sheets: spring-damped presentation

- **Crew strip animations:**
  - New member appears: scale from 0 + haptic
  - Member leaves: fade out + collapse

- **Queue reorder animation:**
  - In collab mode: tracks smoothly slide to new position when votes change
  - `.animation(.spring(), value: sortedQueue)`

### Phase 6: Integration + Demo Flow

**Goal:** Wire everything together, make the demo flow buttery smooth.

- Update `PirateRadioApp.swift` to show onboarding on first launch (UserDefaults check)
- Update `SessionStore.demo()` with new model fields (djMode, hotSeatSongsPerDJ, etc.)
- Update `CreateSessionView` to include DJModePicker before code display
- Update `NowPlayingView` to include: progress bar, BPM gauge, walkie-talkie button, hot-seat banner, signal lost overlay
- Update `SessionLobbyView` to include "Discover" button
- Wire MockTimerManager to fire events → toasts → state updates
- Add debug gesture (triple-tap status bar or shake) to trigger:
  - Signal lost/reconnect cycle
  - Hot-seat rotation
  - Incoming voice clip
- Ensure all screens build and display correctly in demo mode
- Test full flow: Onboarding → Lobby → Create (pick mode) → Now Playing → all features → End Session → Recap

---

## Acceptance Criteria

### Must Have
- [ ] All 3 DJ modes selectable at session creation with visible behavior differences
- [ ] Track progress bar with elapsed/remaining time, DJ scrubbing
- [ ] Collaborative queue voting with animated reorder
- [ ] Song request inbox for DJ with accept/reject
- [ ] Hot-seat rotation countdown + "YOUR TURN" full-screen transition
- [ ] Toast notification system with 6+ event types
- [ ] Session settings panel with member management
- [ ] Member profile cards with stats
- [ ] 3-page animated onboarding
- [ ] Album art breathing/glow animation
- [ ] Signal lost → reconnect animation sequence
- [ ] Walkie-talkie push-to-talk visual demo
- [ ] Mountain social discovery with FM dial metaphor
- [ ] Session recap with animated stats build-up
- [ ] Chairlift mode simplified UI
- [ ] BPM energy gauge
- [ ] 30+ placeholder tracks with real album art
- [ ] 8+ mock crew members across features
- [ ] Staggered entrance animation on Now Playing
- [ ] Haptic feedback on all interactive elements

### Nice to Have
- [ ] Session recap share-as-image
- [ ] Crown-passing animation between avatars on DJ change
- [ ] Reduce motion support for accessibility
- [ ] Debug shake gesture to trigger demo events
- [ ] Fake incoming walkie-talkie voice clip bubbles from mock members

## Mock Data Spec

### 30 Tracks (sample — full list in MockData.swift)

| # | Track | Artist | Album Art |
|---|-------|--------|-----------|
| 1 | Around the World | Daft Punk | Spotify CDN URL |
| 2 | Midnight City | M83 | Spotify CDN URL |
| 3 | Nightcall | Kavinsky | Spotify CDN URL |
| 4 | Tame Impala | The Less I Know The Better | Spotify CDN URL |
| 5 | Flume | Never Be Like You | Spotify CDN URL |
| 6 | Do I Wanna Know? | Arctic Monkeys | Spotify CDN URL |
| 7 | Feel Good Inc | Gorillaz | Spotify CDN URL |
| 8 | Electric Feel | MGMT | Spotify CDN URL |
| 9 | A Moment Apart | ODESZA | Spotify CDN URL |
| 10 | Innerbloom | Rüfüs Du Sol | Spotify CDN URL |
| ... | 20 more tracks | Various | Various |

### 8 Crew Members

| Name | Role | Tracks Added | Votes Cast | DJ Time |
|------|------|-------------|------------|---------|
| DJ Powder | DJ | 12 | 8 | 45m |
| Shredder | Listener | 8 | 24 | 15m |
| Avalanche | Listener | 3 | 38 | 0m |
| Mogul Queen | Listener | 6 | 15 | 20m |
| Après Amy | Listener | 2 | 31 | 10m |
| Gondola Greg | Listener | 1 | 4 | 0m |
| Fresh Tracks | Listener | 9 | 19 | 5m |
| Black Diamond | Listener | 5 | 22 | 0m |

### 8 Discovery Sessions

| Crew Name | Frequency | Members | Now Playing | Distance |
|-----------|-----------|---------|-------------|----------|
| Summit Senders | 91.7 FM | 4 | "Midnight City" - M83 | 0.2 mi |
| Powder Hounds | 94.3 FM | 7 | "Nightcall" - Kavinsky | 0.8 mi |
| Après Crew | 98.1 FM | 3 | "Electric Feel" - MGMT | 1.5 mi |
| Gondola Gang | 101.5 FM | 6 | "Innerbloom" - Rüfüs Du Sol | 0.4 mi |
| Black Run DJs | 104.9 FM | 2 | "Do I Wanna Know?" - Arctic Monkeys | 2.1 mi |
| Lodge Rats | 107.3 FM | 8 | "Feel Good Inc" - Gorillaz | 0.1 mi |
| Terrain Park Crew | 110.7 FM | 5 | "Around the World" - Daft Punk | 1.8 mi |
| First Chair Club | 88.5 FM | 3 | "A Moment Apart" - ODESZA | 3.2 mi |

## References

- Existing plan: [docs/plans/2026-02-13-feat-pirate-radio-v1-plan.md](/docs/plans/2026-02-13-feat-pirate-radio-v1-plan.md)
- Brainstorm: [docs/brainstorms/2026-02-13-pirate-radio-brainstorm.md](/docs/brainstorms/2026-02-13-pirate-radio-brainstorm.md)
- Design system: `PirateRadio/UI/Theme/PirateTheme.swift`, `GloveButton.swift`
- Components: `FrequencyDial.swift`, `CRTStaticOverlay.swift`
- Demo mode entry: `PirateRadio/App/PirateRadioApp.swift` (line 10)
- Mock data seed: `PirateRadio/Core/Sync/SessionStore.swift` (`demo()` factory)
