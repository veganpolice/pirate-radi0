---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, correctness, swift, ui]
dependencies: []
---

# Fix FrequencyPickerView snap-to-nearest-odd rounding bias

## Problem Statement

`FrequencyPickerView.selectedFrequency` (line 16-18) always rounds UP to the next odd tenth when on an even value. This biases frequency selection — the user can never approach a frequency from above and land on it.

## Findings

- Current: `let snapped = tenths % 2 == 1 ? tenths : tenths + 1`
- 88.0 → 881, 88.2 → 883, 88.4 → 885 (always rounds up)
- Should snap to nearest odd tenth, not always up

## Proposed Solutions

### Option 1: Round to nearest odd

**Approach:** Replace with nearest-odd logic:
```swift
let snapped = tenths % 2 == 1 ? tenths : (tenths - 1 < Station.fmMinInt ? tenths + 1 : tenths - 1)
```
Or simpler: since the dial value maps continuously, just round to nearest:
```swift
let lower = tenths % 2 == 1 ? tenths : tenths - 1
let upper = lower + 2
let snapped = (tenths - lower <= upper - tenths) ? lower : upper
```

**Effort:** 10 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `PirateRadio/UI/Onboarding/FrequencyPickerView.swift:16-18`

## Acceptance Criteria

- [ ] Frequency snaps to nearest odd tenth (not always up)
- [ ] Edge cases at 88.1 and 107.9 handled correctly
- [ ] Build succeeds

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Code Simplicity Reviewer agent
