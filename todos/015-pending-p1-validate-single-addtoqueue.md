---
status: complete
priority: p1
issue_id: "015"
tags: [code-review, security, server]
dependencies: []
---

# Validate Single addToQueue Track Data

## Problem Statement

The `addToQueue` WebSocket handler accepted raw track data with no validation, while `batchAddToQueue` properly validated and clamped all fields.

## Resolution

Applied the same validation from `batchAddToQueue` to `addToQueue`:
- Duration validation: `Number.isFinite(durationMs) && durationMs > 0 && durationMs <= MAX_TRACK_DURATION_MS`
- String field clamping: `id` (64), `name` (256), `artist` (256), `albumName` (256), `albumArtURL` (512)
- Replaced spread operator (`...msg.data.track`) with explicit field extraction

All 25 server tests pass.

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-03-07 | Created from code review | Found by security-sentinel agent |
| 2026-03-07 | Fixed — applied same validation as batchAddToQueue | Always validate at the boundary, even for "trusted" clients |
