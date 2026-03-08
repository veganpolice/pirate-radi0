---
status: pending
priority: p2
issue_id: "012"
tags: [code-review, simplicity, dead-code, server]
dependencies: []
---

# Remove legacy server endpoints and dead code

## Problem Statement

`POST /sessions` and `POST /sessions/join` were kept for "backward compat during Phase 2 transition." The iOS client no longer calls either (Phase 2 is complete). They add ~55 lines of dead code, a rate-limit Map, and attack surface.

## Findings

- `POST /sessions` (~35 lines) — just boots user's existing station, no client calls it
- `POST /sessions/join` (~20 lines) — always returns 404 "Join codes are deprecated"
- `sessionCreationLog` Map + `MAX_SESSIONS_PER_USER_PER_HOUR` constant only used by legacy endpoints
- `stmtGetStationByFreq` prepared statement declared but never called

## Proposed Solutions

### Option 1: Delete all legacy code

**Approach:** Remove both endpoints, the rate-limit infrastructure, and unused prepared statement.

**Effort:** 15 minutes
**Risk:** Low (no clients use these)

## Technical Details

**Affected files:**
- `server/index.js` — legacy endpoints (~lines 255-322), sessionCreationLog, stmtGetStationByFreq

## Acceptance Criteria

- [ ] Legacy endpoints removed
- [ ] sessionCreationLog and MAX_SESSIONS_PER_USER_PER_HOUR removed
- [ ] stmtGetStationByFreq removed
- [ ] Server tests pass
