# Quick-Start Flow: Dial Home with Auto-Tune

**Date:** 2026-02-28
**Status:** Brainstorm complete

## What We're Building

Replace the current 3-button lobby with a radio dial as the primary home screen. When you open the app, you're immediately tuned into a friend's station — music starts playing. The dial shows fixed-frequency notches for every user in your group, glowing when they're live, dim when offline. Drag the dial to switch stations. "Start Broadcasting" lets you go live on your own frequency.

### Core Behavior

- **Auto-tune on launch:** App opens → finds the last station you were listening to → if it's still live, starts playing immediately. If not, picks the next live station. If nobody's live, shows the silent dial.
- **Dial navigation:** Drag the dial to move between stations. Each friend has a fixed notch (e.g., "Aaron 98.7"). Snapping to a live notch tunes in and transitions to NowPlayingView.
- **Fixed frequencies per user:** Your frequency is yours. Friends learn your spot on the dial. Frequencies are assigned on first broadcast (a dial-pick ceremony).
- **NowPlayingView takes over:** Once tuned in, the existing NowPlayingView is the player. Navigate back to the dial to switch stations.
- **Start Broadcasting:** Button on the dial view. First time triggers frequency selection. After that, starts your station on your fixed frequency.
- **Silent dial (empty state):** When nobody's live, show the dial with dim notches for known users. "Start Broadcasting" CTA prominent. Shows the social layer even when quiet.

### Group Discovery (POC Simplification)

For the dogfooding POC, all authenticated users are in one global group. No invite codes, no planet system. Everyone sees everyone. Real group management comes after validating the core hypothesis.

## Why This Approach

The dial IS the product identity. If the POC doesn't feel like radio — if it's just a list of active sessions — the dogfooding test is weaker. The ritual of "tuning in" is what makes Pirate Radio feel fundamentally different from sharing a Spotify playlist. Testing the hypothesis requires testing the *feel*, not just the mechanics.

Auto-tune on launch removes all friction. You don't decide to listen — you're already listening when the app opens. The question shifts from "should I tune in?" to "who am I tuned to?" That's the radio experience.

## Key Decisions

1. **Auto-tune on launch** — Music starts immediately. Last-tuned station if still live, otherwise next live station. No decision required from the user.
2. **Dial is the home screen** — Replaces SessionLobbyView. Social presence is always visible.
3. **Fixed frequencies per user** — Identity on the dial. Assigned on first broadcast via a dial-pick ceremony.
4. **NowPlayingView for playback** — Existing view, no changes needed. Dial → NowPlaying transition on tune-in.
5. **Global group for POC** — All users see each other. No invites or groups needed.
6. **Frequency picker on first broadcast** — Not during onboarding. Ties the choice to the moment it matters.
7. **Silent dial for empty state** — Dim notches show friends who have frequencies. "Start Broadcasting" CTA below.

## What's Needed (Server)

- **`GET /stations` endpoint** — List all active sessions (or all known users with their frequencies and live status). Currently no such endpoint exists.
- **Frequency persistence** — Server needs to store each user's assigned frequency. Currently only in-memory session state exists.
- **User registry** — Server needs to know about users beyond the current session. Today, users only exist in the context of an active session.

## What's Needed (Client)

- **New `DialHomeView`** — Replaces `SessionLobbyView` as the post-auth landing screen.
- **Evolve `FrequencyDial`** — Add user identity at notches (name labels), live/offline states (glow vs dim), and snap-to-tune behavior that triggers session join.
- **Auto-tune logic** — On app launch: fetch active stations → find last-tuned → join and play. Needs to be fast (< 2 seconds to music).
- **Frequency picker flow** — Modal on first "Start Broadcasting" tap. Spin the dial, claim a frequency.
- **Navigation refactor** — `SessionRootView` decision tree changes: authenticated → `DialHomeView` (with auto-tune) instead of `SessionLobbyView`.

## What Exists Already

- `FrequencyDial` component — rotary dial with detents, FM-like slots, snap behavior
- `DiscoveryView` — has the visual language (album art, member avatars, "Tune In" button) but uses mock data
- `JoinSessionView` — already maps dial frequencies to 4-digit codes and calls `joinSession`
- `sessionStore.joinSession(code:)` — full join flow: auth → POST /sessions/join → WebSocket → stateSync
- `NowPlayingView` — complete player view, no changes needed
- `PirateTheme` — design system with neon glow, void background, all the right aesthetics
- `GloveButtonStyle` — big touch targets with haptic feedback

## Open Questions

- What frequency range should the dial span? Current implementation uses FM-like 88.0–108.0. Is that enough slots for a 10-30 person group?
- Should offline friends (have a frequency but no active station) show on the dial at all, or only friends who are currently live?
- How does "Start Broadcasting" interact with an existing station? If you were already broadcasting and tuned into a friend, your station is still live. Does "Start Broadcasting" just navigate you back to your own NowPlayingView?
- Should there be any indication on the dial of what each friend is playing? (e.g., tiny album art at the notch, or just their name)
- Persistence: frequencies need to survive server restarts. Is this the moment to add a lightweight database (SQLite on Fly.io), or can we use a JSON file for the POC?

## Relationship to Existing Brainstorm

This implements items from the [Planets & Stations vision brainstorm](2026-02-28-planets-stations-vision-brainstorm.md):

| Vision concept | POC implementation |
|---|---|
| Planet | Global group (all users) |
| Station | Existing session model with autonomous playback |
| Frequency | Fixed per user, assigned on first broadcast |
| Dial | `DialHomeView` with evolved `FrequencyDial` |
| "My Planet" mode | The only mode (global group) |
| "Discover" mode | Skipped for POC |
| Deep link invites | Skipped — global group |
| One-tap tune-in | Auto-tune on launch + dial snap |

## Suggested Plan Breakdown

This could be one plan or split into two:

1. **Server: User Registry & Station List** — Frequency persistence, `GET /stations` endpoint, user-frequency mapping
2. **Client: Dial Home & Auto-Tune** — `DialHomeView`, evolved `FrequencyDial`, auto-tune logic, frequency picker, navigation refactor
