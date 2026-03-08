---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, devops, server]
dependencies: []
---

# Add --omit=dev to Dockerfile npm ci

## Problem Statement

The plan explicitly states "Use `--omit=dev` not `--production` (deprecated)" but the Dockerfile runs `npm ci` without `--omit=dev`, including devDependencies in the production image.

## Proposed Solutions

### Option 1: Add --omit=dev flag

**Approach:** Change `RUN npm ci` to `RUN npm ci --omit=dev` in the build stage.

**Effort:** 2 minutes
**Risk:** Low

## Technical Details

**Affected files:**
- `server/Dockerfile:4`

## Acceptance Criteria

- [ ] Dockerfile uses `npm ci --omit=dev`
- [ ] Docker build succeeds

## Work Log

### 2026-03-07 - Initial Discovery

**By:** Architecture Strategist agent
