# Fix Dead Buttons & Navigation — Brainstorm

**Date:** 2026-02-14
**Goal:** Make every button, link, and interactive element do something real (or be removed). No dead-ends, no demo-only methods called in production, no hard-coded placeholder values.

## What We're Building

A polish pass across all views to ensure basic navigation and button wiring works. Not adding new server features — just making the existing UI honest.

## Key Decisions

1. **No new server handlers this round** — pass DJ, kick member, DJ mode change stay client-only but should show a toast/alert saying "coming soon" instead of silently mutating local state
2. **Remove duplicate buttons** — Menu and Settings in bottom bar do the same thing
3. **Hard-coded values become dynamic or hidden** — pendingRequestCount=5, mock requests in RequestsView
4. **Discovery "Tune In" gets disabled or removed** — no backend support exists
5. **Volume dial in Chairlift mode** — cosmetic, keep but don't pretend it works

## Audit Findings

| Element | File | Issue | Fix Approach |
|---------|------|-------|-------------|
| Request badge "5" | NowPlayingView:27 | Hard-coded | Derive from session queue or hide |
| "Pass DJ" button | MemberProfileCard:102 | Demo-only `setDJ()` | Show "coming soon" toast |
| "Remove Member" button | SessionSettingsView:60 | Demo-only `removeMember()` | Show "coming soon" toast |
| DJ Mode picker | SessionSettingsView:244 | Demo-only `changeDJMode()` | Show "coming soon" toast |
| "Tune In" button | DiscoveryView:212 | Closes sheet, no join | Disable with "coming soon" label |
| Volume dial | ChairliftModeView:93 | Cosmetic only | Leave as-is (ambient UI) |
| Menu + Settings duplicate | NowPlayingView:145,196 | Both open settings | Remove duplicate, keep one |
| RequestsView init | RequestsView:9 | Always loads MockData | Show empty state in real mode |
| Shake debug actions | NowPlayingView:403 | Demo-only methods | Gate behind demoMode check |

## Open Questions

- Should "coming soon" features be hidden entirely or shown disabled?
- Decision: **Show disabled with toast** — users can see the feature exists

## Next

Proceed to `/workflows:plan` → `/workflows:work`
