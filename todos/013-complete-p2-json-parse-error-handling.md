---
status: pending
priority: p2
issue_id: "013"
tags: [code-review, correctness, server, resilience]
dependencies: []
---

# Wrap JSON.parse(row.tracks_json) in error handling

## Problem Statement

`JSON.parse(stationRow.tracks_json)` appears 3 times in server/index.js (lines ~189, ~723, ~986) with no try/catch. If JSON is ever corrupted in SQLite, the server will crash. Since data persists across deploys, this is a real risk.

## Proposed Solutions

### Option 1: Extract a parseTracks helper with error handling

**Approach:** Centralize into `function parseTracks(row) { try { return JSON.parse(row.tracks_json) } catch { return [] } }`. Log the error and return empty array as fallback.

**Effort:** 10 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `server/index.js` — 3 call sites of `JSON.parse(row.tracks_json)`

## Acceptance Criteria

- [ ] All tracks_json parsing uses the helper
- [ ] Corrupted JSON returns empty array (not crash)
- [ ] Error is logged for debugging
- [ ] Server tests pass
