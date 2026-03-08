---
status: pending
priority: p2
issue_id: "003"
tags: [code-review, simplicity, dead-code, swift]
dependencies: []
---

# Delete dead placeholder files and orphaned views

## Problem Statement

Four view files are either gutted to EmptyView placeholders or completely unreachable from the navigation graph. Keeping them adds confusion and ~238 LOC of dead code.

## Findings

- `HotSeatBanner.swift` — gutted to EmptyView, zero references outside its own file
- `DJModePicker.swift` — gutted to EmptyView, zero references outside its own file
- `SessionLobbyView.swift` — ~90 lines, never instantiated from any navigation path
- `JoinSessionView.swift` — rewritten to ~80 lines but never instantiated (was only shown from SessionLobbyView sheet, which is itself dead)

## Proposed Solutions

### Option 1: Delete all four files and remove from pbxproj

**Approach:** Delete the files and remove their file references and build phase entries from the Xcode project file.

**Pros:**
- Clean removal of ~238 LOC dead code
- No confusion for future developers

**Cons:**
- Xcode project file edits are error-prone

**Effort:** 30 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `PirateRadio/UI/NowPlaying/HotSeatBanner.swift` — delete
- `PirateRadio/UI/Session/DJModePicker.swift` — delete
- `PirateRadio/UI/Session/SessionLobbyView.swift` — delete
- `PirateRadio/UI/Session/JoinSessionView.swift` — delete
- `PirateRadio.xcodeproj/project.pbxproj` — remove references

## Acceptance Criteria

- [ ] All four files deleted
- [ ] Xcode project file updated (no dangling references)
- [ ] Build succeeds
- [ ] No references to deleted types remain

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Code Simplicity Reviewer + Architecture Strategist agents

**Actions:**
- Grep confirmed zero external references to HotSeatBanner and DJModePicker
- Navigation graph analysis confirmed SessionLobbyView and JoinSessionView are unreachable
