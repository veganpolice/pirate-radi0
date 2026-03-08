---
status: pending
priority: p2
issue_id: "016"
tags: [code-review, security, server]
dependencies: []
---

# Wire Up Rate Limiting on /auth Endpoint

## Problem Statement

`checkRateLimit()` and `recordRateLimit()` functions exist in `server/index.js` alongside `joinAttemptLog` and `MAX_JOIN_ATTEMPTS_PER_IP_PER_MIN`, but are never called. The `/auth` endpoint is unauthenticated and unthrottled.

## Findings

- Functions defined at lines 988-999 of server/index.js
- No endpoint calls them
- `/auth` accepts any `spotifyUserId` and issues a JWT

**Source:** Security Sentinel agent (F1)

## Proposed Solutions

Apply rate limiter to `/auth` and WebSocket upgrade handler:
```javascript
app.post("/auth", (req, res) => {
  if (!checkRateLimit(joinAttemptLog, req.ip, MAX_JOIN_ATTEMPTS_PER_IP_PER_MIN, 60_000)) {
    return res.status(429).json({ error: "Too many requests" });
  }
  recordRateLimit(joinAttemptLog, req.ip);
  // ... rest
});
```
- Effort: Small
- Risk: None

## Acceptance Criteria

- [ ] `/auth` returns 429 after exceeding rate limit
- [ ] Server test covers rate limiting

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-07 | Created from code review | Found by security-sentinel agent |
