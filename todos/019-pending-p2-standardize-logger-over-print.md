---
status: pending
priority: p2
issue_id: "019"
tags: [code-review, quality, client]
dependencies: []
---

# Standardize os.Logger Over print() in SessionStore

## Problem Statement

`SessionStore` uses `os.Logger` in some methods but `print("[SessionStore]...")` in others. `os.Logger` supports privacy redaction, log levels, and Console.app filtering; `print` does not.

## Findings

Methods using `print`: `joinSessionById`, `fetchStations`, `handleStateSync`, `play`, `ensureSpotifyConnected`
Methods using `logger`: `claimFrequency`, `reassertPlayback`, `handleAppRemoteReconnected`

**Source:** Pattern Recognition Specialist and Security Sentinel agents

## Acceptance Criteria

- [ ] All `print("[SessionStore]...")` calls replaced with `logger.notice/debug/error`
- [ ] Sensitive data uses `privacy: .private` redaction

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-07 | Created from code review | Mixed logging is pre-existing but worth cleaning up |
