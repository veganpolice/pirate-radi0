# Fix Dead Buttons & Navigation

## Goal
Make every button and interactive element do something real or show "coming soon". No silent no-ops.

## Changes

### 1. Add `comingSoon` toast type
**ToastManager.swift** — add case, icon (wrench), color (flare)

### 2. MemberProfileCard "Pass DJ" → coming soon toast
**MemberProfileCard.swift:101** — replace `sessionStore.setDJ()` with toast in non-demo mode

### 3. SessionSettingsView "Remove Member" → coming soon toast
**SessionSettingsView.swift:60** — replace `sessionStore.removeMember()` with toast in non-demo mode

### 4. SessionSettingsView "Change DJ Mode" → coming soon toast
**SessionSettingsView.swift:244** — replace `sessionStore.changeDJMode()` with toast in non-demo mode

### 5. RequestsView — show empty state in real mode
**RequestsView.swift:12** — only load MockData when demoMode, otherwise start empty

### 6. NowPlayingView — remove hard-coded badge, deduplicate bottom bar
**NowPlayingView.swift:27** — derive pendingRequestCount from queue count or 0
**NowPlayingView.swift:145** — remove duplicate Menu button (keep Settings gear)

### 7. DiscoveryView "Tune In" → coming soon toast
**DiscoveryView.swift:212** — show toast instead of silently closing

### 8. SessionRecapView — gate mock stats behind demoMode
**SessionRecapView.swift:17** — in real mode show placeholder stats

### 9. NowPlayingView shake handler — gate behind demoMode
**NowPlayingView.swift:391** — only run shake debug actions in demo mode
