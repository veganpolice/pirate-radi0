---
title: "feat: Replace Messages with iMessage Share Button"
type: feat
date: 2026-03-04
---

# Replace Messages with iMessage Share Button

## Overview

Remove the "Messages" button (and the entire RequestsView / song requests feature) from the NowPlaying bottom bar. Replace it with a "Share" button using a radio tower icon that opens iMessage with a pre-populated invite containing a `pirate-radio://join/<code>` deep link.

## Acceptance Criteria

- [x] "Messages" button removed from NowPlaying bottom bar
- [x] RequestsView.swift deleted; all references and dead code removed (including `acceptRequest` in SessionStore if dead)
- [x] `pendingRequestCount` state, badge overlay, and `showRequests` sheet removed from NowPlayingView
- [x] New "Share" button in the same position (leftmost in bottom bar) with `antenna.radiowaves.left.and.right` icon and "Share" label
- [x] Tapping Share opens `MFMessageComposeViewController` with body: `"Tune in to my Pirate Radio station! Use code <joinCode> to join. pirate-radio://join/<joinCode>"`
- [x] Share button disabled (reduced opacity) when `canSendText() == false`, with toast on tap; in demo mode, button enabled with toast-only fallback
- [x] Deep link handled via `.onOpenURL` in PirateRadioApp (not NotificationCenter)
- [x] Pending join code stored if deep link arrives before auth completes
- [x] `MessageComposeView` uses trampoline UIViewController pattern (UIKit presents and dismisses UIKit)
- [x] Visible to both DJ and listeners

## Context

### Why iMessage specifically?
The app already has generic `ShareLink` in CreateSessionView and SessionSettingsView. This feature puts sharing front-and-center on the NowPlaying screen and targets iMessage directly for a more personal, instant invite experience.

### Existing share implementations (unchanged)
- `CreateSessionView.swift:136-147` — ShareLink with join code text
- `SessionSettingsView.swift:202-207` — ShareLink with join code text
- `SessionRecapView.swift:74-83` — ShareLink with session stats

### Key learnings from docs/solutions/
- **Environment modifier ordering** (`docs/solutions/runtime-errors/swiftui-environment-modifier-ordering.md`): `.environment()` must be outermost modifier. When adding the new `.sheet` for the message composer, ensure environment modifiers remain last.

## MVP

### 1. Delete RequestsView and clean up references

**Delete:** `PirateRadio/UI/NowPlaying/RequestsView.swift`

**Clean up in `NowPlayingView.swift`:**

```swift
// REMOVE these lines:
// Line 11: @State private var showRequests = false
// Line 27: @State private var pendingRequestCount = 0
// Line 50: .sheet(isPresented: $showRequests) { RequestsView() }
// Lines 154-175: entire Messages button block in bottomBar
// Lines 164-171: badge overlay
```

Also remove any dead code in `SessionStore` (e.g. `acceptRequest`, `requestAccepted`/`requestDeclined` toast types in `ToastManager`).

### 2. Create MessageComposeView wrapper (trampoline pattern)

**New file:** `PirateRadio/UI/Shared/MessageComposeView.swift`

`MFMessageComposeViewController` must be presented via UIKit's `present(_:animated:)` — it cannot be directly embedded as a `UIViewControllerRepresentable` child inside a SwiftUI `.sheet` (causes blank screen or crash). Use a transparent trampoline `UIViewController`:

```swift
import MessageUI
import SwiftUI

struct MessageComposeView: UIViewControllerRepresentable {
    let messageBody: String
    let onFinished: () -> Void

    func makeUIViewController(context: Context) -> MessageComposeHostController {
        MessageComposeHostController(messageBody: messageBody, onFinished: onFinished)
    }

    func updateUIViewController(_ uiViewController: MessageComposeHostController, context: Context) {}
}

class MessageComposeHostController: UIViewController, MFMessageComposeViewControllerDelegate {
    let messageBody: String
    let onFinished: () -> Void
    private var hasPresented = false

    init(messageBody: String, onFinished: @escaping () -> Void) {
        self.messageBody = messageBody
        self.onFinished = onFinished
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresented, MFMessageComposeViewController.canSendText() else { return }
        hasPresented = true
        let composer = MFMessageComposeViewController()
        composer.body = messageBody
        composer.messageComposeDelegate = self
        present(composer, animated: true)
    }

    func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        controller.dismiss(animated: true) {
            self.onFinished()
        }
    }
}
```

### 3. Add Share button to NowPlaying bottom bar

**Modify:** `PirateRadio/UI/NowPlaying/NowPlayingView.swift`

Add `import MessageUI` at the top.

```swift
// Add state
@State private var showShareCompose = false

// Evaluate once (static, never changes at runtime)
private let canShare = PirateRadioApp.demoMode || MFMessageComposeViewController.canSendText()

// In bottomBar, replace Messages button block (position 1):
Button {
    if MFMessageComposeViewController.canSendText() {
        showShareCompose = true
    } else {
        toastManager.show("iMessage not available on this device")
    }
} label: {
    VStack(spacing: 4) {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: 20, weight: .medium))
        Text("Share")
            .font(.caption2)
    }
}
.frame(maxWidth: .infinity, minHeight: 50)
.opacity(canShare ? 1.0 : 0.4)

// Add sheet (before .environment modifiers per learnings):
.sheet(isPresented: $showShareCompose) {
    if let joinCode = sessionStore.session?.joinCode {
        MessageComposeView(
            messageBody: "Tune in to my Pirate Radio station! Use code \(joinCode) to join. pirate-radio://join/\(joinCode)"
        ) {
            showShareCompose = false
        }
    }
}
```

### 4. Handle `pirate-radio://join/<code>` deep link via `.onOpenURL`

**Modify:** `PirateRadio/App/PirateRadioApp.swift` — add `.onOpenURL` to the WindowGroup/root view:

```swift
.onOpenURL { url in
    if url.host == "join", let code = url.lastPathComponent.nilIfEmpty {
        if let sessionStore {
            Task { await sessionStore.joinSession(code: code) }
        } else {
            pendingJoinCode = code  // process after auth completes
        }
    }
}
```

Add `@State private var pendingJoinCode: String?` to PirateRadioApp. After `sessionStore` is created (when auth completes), check and consume `pendingJoinCode`.

**Modify:** `PirateRadio/App/AppDelegate.swift` — return `false` for non-auth URLs so SwiftUI's `.onOpenURL` can handle them:

```swift
func application(_ app: UIApplication, open url: URL, options: [...]) -> Bool {
    if url.host == "auth" {
        authManager?.handleAppRemoteURL(url)
        return true
    }
    return false
}
```

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `PirateRadio/UI/NowPlaying/RequestsView.swift` | Delete | Remove entire file |
| `PirateRadio/UI/NowPlaying/NowPlayingView.swift` | Modify | Remove Messages button/state, add Share button/sheet, `import MessageUI` |
| `PirateRadio/UI/Shared/MessageComposeView.swift` | Create | Trampoline UIViewController wrapper for MFMessageComposeViewController |
| `PirateRadio/App/PirateRadioApp.swift` | Modify | Add `.onOpenURL` handler and `pendingJoinCode` state |
| `PirateRadio/App/AppDelegate.swift` | Modify | Return `false` for non-auth URLs |
| `project.yml` | Verify | Ensure new file is picked up by XcodeGen glob |

## Edge Cases

- **Simulator/iPad Wi-Fi:** Button visible but dimmed (unless demo mode); tap shows toast
- **Demo mode:** `canShare` override keeps button visually enabled; tap shows toast instead of composer
- **Message cancelled:** Delegate fires `.cancelled`, UIKit dismisses composer, `onFinished` resets `showShareCompose`
- **Deep link before auth:** Join code stored in `pendingJoinCode`, consumed when SessionStore is created
- **`session.joinCode` nil-safety:** Guard unwrap `sessionStore.session?.joinCode` before presenting composer
- **Recipient without app:** Message includes human-readable join code alongside the deep link URL

## References

- `NowPlayingView.swift:152-213` — current bottom bar with Messages button
- `RequestsView.swift` — file to be deleted
- `AppDelegate.swift:16-23` — current URL handling (Spotify auth only)
- `PirateRadioApp.swift:106-149` — root view hierarchy where `.onOpenURL` will be added
- `CreateSessionView.swift:136-147` — existing ShareLink pattern
- `docs/solutions/runtime-errors/swiftui-environment-modifier-ordering.md` — sheet + environment ordering

## Review Notes

Plan revised after parallel review by DHH, Kieran, and Simplicity reviewers. Key changes from v1:
- **Trampoline pattern** for MFMessageComposeViewController (Kieran: direct embedding in .sheet crashes)
- **`.onOpenURL` instead of NotificationCenter** (all reviewers: simpler, correct for SwiftUI lifecycle)
- **UIKit dismisses UIKit** — no stale DismissAction capture (DHH + Kieran)
- **Pending join code** for deep links arriving before auth (Kieran: race condition)
- **Demo mode override** so button isn't permanently dimmed in Simulator (DHH)
- **Human-readable join code** in message alongside deep link (DHH: recipients without app)
