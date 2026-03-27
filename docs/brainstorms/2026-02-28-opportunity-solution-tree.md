# Opportunity Solution Tree + POC Plan

**Date:** 2026-02-28
**Framework:** Teresa Torres, Continuous Discovery Habits

## Desired Outcome

**Outcome:** My friend group actually uses Pirate Radio together instead of listening to Spotify solo.
**Target Metric:** Friends in my planet actively tuning into each other's stations weekly.
**Why it matters:** If your own friend group won't use it, nobody else will. Dogfooding validates the core value prop before scaling.

---

## Opportunity Map

### Opportunity 1: Too much friction to start listening
**Problem:** Opening the app and getting to music takes too many steps. Friends will just open Spotify instead because it's one tap to play. If Pirate Radio isn't faster for the social use case, it loses.
**Evidence:** Already identified in brainstorm — quick-start flow and dial-first UX are direct responses to this.

**Solutions:**
1. Dial-first home screen with one-tap tune-in to active friends
2. Auto-load last queue/playlist when starting your own station
3. Push notification when a friend goes live ("Aaron is broadcasting on 98.7")

---

### Opportunity 2: Nothing to do when friends aren't live
**Problem:** If you open the app and nobody's broadcasting, there's nothing to do. You close it and forget about it. The app is only valuable during the narrow window when friends happen to overlap.
**Evidence:** Current session model is ephemeral — when the session ends, nothing persists.

**Solutions:**
1. Autonomous stations that keep playing your queue even when you leave the app
2. Station history / "what you missed" — see what friends played while you were gone
3. Async queue contributions — add songs to a friend's station even when they're not live

---

### Opportunity 3: "Why not just share a playlist?" (SELECTED)
**Problem:** Friends already share music via Spotify playlists, AirDrop, or group chats. Pirate Radio needs to offer something those can't — the real-time, ambient, always-available social listening experience.
**Evidence:** Core value hypothesis — synchronous social listening is meaningfully different from async playlist sharing.

**Solutions:**
1. **The Live Dial Experience** — Radio dial with real-time station indicators. The ritual of "tuning in" that playlists can't replicate. Physicality and liveness create a shared moment.
2. **Station Identity & Curation** — Your frequency is yours (98.7 Aaron). Friends know your taste by your station, not a playlist title. DJ identity makes it personal.
3. **Ambient Social Presence (SELECTED)** — Your station plays autonomously even when you're not in the app. Friends can tune in to your vibe anytime. Like leaving your bedroom door open with music playing. Creates ambient awareness of your friend group's musical lives without requiring coordination.

---

## Selected POC

**Opportunity:** "Why not just share a playlist?" — Pirate Radio must feel fundamentally different
**Solution:** Ambient Social Presence — autonomous stations that friends can tune into anytime

**Hypothesis:**
- "If we make stations play autonomously (queue advances even when the broadcaster backgrounds the app), then friends will tune in to each other's stations at least 3x per week because the always-available nature creates a habit loop that async playlist sharing can't."

**Experiment:**
- **Type:** MVP build
- **What to build:** Station keeps playing your queue even when you background the app. Server-side queue advancement. Friends can see who's "live" (has an active queue) and tune in with synced playback. Skip Spotify handoff for now — just keep the queue advancing.
- **Participants:** Your friend group (5-10 people on one planet)
- **Duration:** 2-3 weeks of real usage
- **Success criteria:** Do friends actually tune in when they see someone's station is live? Do people leave their stations running? Does it feel different from sharing a playlist?

**Feasibility Score:** 3/5
**Impact Score:** 5/5
**Market Fit Score:** 5/5
**Total:** 13/15

**Why this POC:**
- Directly tests the core differentiator — ambient, always-on social music presence
- Builds on existing infrastructure (queue management, WebSocket sync, Spotify playback)
- The key new piece is server-side queue advancement when the broadcaster isn't actively in the app
- If this doesn't feel magical to your friend group, no amount of UI polish matters

---

## What This Means for the 6 Plan Areas

The OST reshuffles priority from the brainstorm:

| Plan Area | Priority | Rationale |
|-----------|----------|-----------|
| **Station & Per-User Queue** | **1 — Build first** | Core of the POC. Server-side autonomous queue advancement is the key new capability. |
| **Quick-Start Flow** | **2 — Build second** | Seeing who's live and one-tap tune-in is essential for the POC to work. Friends need to know you're broadcasting. |
| **Planet & Account System** | **3 — Simplified for POC** | You need basic invites and a shared group, but the full planet model can wait. Use existing session join codes or a simple deep link for now. |
| **Dial UI** | **4 — Nice to have** | The dial is part of the long-term vision, but for the POC a simple list of active stations works. Don't block the experiment on building a custom dial. |
| **Spotify Handoff** | **5 — After POC validates** | Only matters if the ambient presence hypothesis is validated. Build once you know the core is sticky. |
| **Shazam Spike** | **6 — Separate track** | Independent exploration. Do whenever curiosity strikes. |

---

## Next Steps

1. **Plan "Station & Per-User Queue"** — Focus on server-side queue advancement (station keeps playing when broadcaster leaves). This is the minimal new infrastructure for the POC.
2. **Plan "Quick-Start: Who's Live"** — Simple screen showing active stations with one-tap tune-in. Doesn't need to be a dial yet.
3. **Ship to friend group via TestFlight** — You're already set up for this.
4. **Observe for 2-3 weeks** — Do friends tune in? Do they leave stations running? Does it feel different?
5. **Decide:** If it works → build the full dial UI, planet system, Spotify handoff. If it doesn't → revisit the opportunity (maybe friction or solo experience matters more).

---

**The bet:** Ambient social presence is what makes Pirate Radio fundamentally different from sharing a Spotify playlist. Test that bet first, with the minimum build possible.
