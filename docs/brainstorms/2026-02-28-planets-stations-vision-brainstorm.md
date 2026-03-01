# Pirate Radio: Planets, Stations & Dial Vision

**Date:** 2026-02-28
**Status:** Brainstorm complete

## What We're Building

A social radio app where friend groups ("planets") share music through personal radio stations. Each person broadcasts on a persistent frequency within their planet. Listeners tune in via a physical-feeling dial UI. The app is social-first: opening it shows you who's live and gets you listening in one tap.

### Core Concepts

- **Planet** — A persistent social group (like a Discord server). You invite friends to your planet; the invite creates their account. Planets persist long-term; stations come and go within them.
- **Station** — A temporary broadcast within a planet. Each person can run one station at a time. A station is backed by a queue that Pirate Radio manages and syncs to Spotify.
- **Frequency** — Each user has a fixed frequency within each planet (e.g., "Aaron is always 98.7"). This is their identity on that planet's dial. Frequencies are planet-scoped — you might be 98.7 on one planet and 103.5 on another.
- **Dial** — The primary UI. A radio dial with notches for active stations. Two modes: "My Planet" (friends only) and "Discover" (all public stations). Same dial, toggled.

### Tuning In = Synced Playback

When you tune into a friend's station, their current track starts playing on YOUR Spotify, synced to their position in real-time. This is the existing session sync model, reframed as "tuning in."

### Spotify Handoff

You can seamlessly hand queue control to Spotify. Leave the Pirate Radio UI and use Spotify directly — your station stays live. Pirate Radio monitors Spotify's player state and relays it to your listeners. Your friends don't know you switched. Coming back to Pirate Radio reclaims control.

### Transitions

Use Spotify's built-in crossfade for smooth transitions rather than building custom audio mixing. The "transition" button triggers the next track and lets Spotify's crossfade handle the blend.

### Queue System

- Each station has a queue persisted to the database
- Pirate Radio is the authority on what plays next — it manages Spotify's queue
- History is persisted through the queue system (tracks move from queue → played)
- Spotify API used to detect current playback and verify queue state
- Easy to swap an entire queue by loading a Spotify playlist

### Quick-Start Flow

1. **Open app** → Dial is front and center
2. **Friends active?** → Notches on dial show live stations. One tap to tune in.
3. **Nobody active?** → "Start your station" with playlist picker. Load your last Spotify playlist or existing Pirate Radio queue.
4. Starting your own station is secondary to joining friends.

## Feature: Shazam Pirate Capture (Spike First)

The "real pirate feature" — record your night out, Shazam songs as you hear them, and build a station from the captured tracks. Always-on audio recognition that builds a pirate hitlist of the sets you're hearing.

**Decision:** Do a technical spike on ShazamKit feasibility before committing to a version. Questions to answer:
- Background audio recognition battery impact
- ShazamKit accuracy in loud venue environments
- How to handle partial matches / unrecognized tracks
- Can it run alongside Spotify playback?

## Key Decisions

1. **Planets are a persistent social layer; stations are temporary broadcasts** — Two distinct concepts, not a rename of sessions
2. **Tuning in = real-time synced playback** — Same as current session model
3. **Dial-first, social-first UX** — Opening the app shows the dial with active friends
4. **Two-mode dial** — "My Planet" for friends, "Discover" for public. Same UI, toggled
5. **Planet-scoped frequencies** — Your dial position is fixed per planet, part of your identity
6. **Spotify handoff keeps station live** — PR passively relays Spotify state to listeners
7. **Spotify's crossfade for transitions** — Don't build custom audio mixing
8. **Shazam capture: spike first** — Too uncertain to commit; test feasibility before planning
9. **One active planet at a time** — Simple for v1, multi-planet later
10. **Configurable listener collaboration** — Broadcaster sets station to listen-only, requests, or open queue
11. **Deep link invites** — Share a URL to invite to a planet
12. **Medium planet size (10-30)** — Extended friend groups, not communities
13. **Discover mode is V2** — Planet-only stations for launch
14. **User picks their frequency** — Part of identity within each planet
15. **Stations are autonomous** — Your broadcast continues even when you're listening elsewhere

## Resolved Questions

1. **Multi-planet membership?** — One active planet at a time for now. Multi-planet membership is a future consideration.
2. **Listener collaboration?** — Configurable per station. The broadcaster chooses: listen-only, requests-only, or open queue. Maps to existing DJ mode concept.
3. **Invite flow?** — Share link / deep link. Generate a unique URL, share via iMessage/WhatsApp/etc. Tapping opens the app (or App Store) and joins the planet.
4. **Planet size?** — Medium (10-30 people). Extended friend groups or small communities.
5. **Public discovery?** — V2. Skip Discover mode for now. Focus on planet-only stations first.
6. **Frequency assignment?** — User picks their frequency when joining a planet. Personal choice, part of identity.
7. **Your station while tuning in?** — Keeps playing autonomously. Your queue advances and broadcasts to listeners even while you're listening to someone else. It's a real radio station.

## Open Questions

- How long does a station stay "live" with no listeners and the broadcaster tuned elsewhere? Indefinitely until queue runs out?
- Can you have multiple planets but only one active at a time — what does "switching" look like in the UI?
- Deep link format and account creation flow — Spotify-only auth, or also email/Apple ID?

## Relationship to Existing Code

The current codebase has sessions, WebSocket sync, queue management, and Spotify playback all working. The planet/station model is a **new layer on top**:

- **Sessions → Stations** (conceptual rename + queue ownership per user)
- **New: Planet model** (persistent group, member management, frequency assignments)
- **New: Dial UI** (replaces or augments current DiscoveryView/CreateSessionView)
- **New: Spotify handoff** (passive player state monitoring mode)
- **Evolve: Queue system** (per-user queues instead of per-session, playlist import)

## Suggested Plan Breakdown

These could become separate `/workflows:plan` runs:

1. **Planet & Account System** — Data model, invites, persistence
2. **Station & Per-User Queue** — Evolve sessions into user-owned stations
3. **Dial UI** — The radio dial with planet/discover modes
4. **Spotify Handoff** — Passive monitoring mode, seamless switching
5. **Quick-Start Flow** — App open → dial → one-tap join
6. **Shazam Spike** — Technical feasibility of ShazamKit capture
