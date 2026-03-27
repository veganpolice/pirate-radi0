---
title: "Fly.io Deploy Fails: Invalid Region and Missing Billing"
category: deployment-issues
tags: [fly-io, deployment, docker, node, region, billing]
module: Server
symptom: "fly launch --region sea fails with 'region not found'; first deploy fails requiring billing"
root_cause: "Seattle (SEA) is not an available Fly.io region; free tier requires billing info for machine-based apps"
date: 2026-02-14
---

# Fly.io Deploy Fails: Invalid Region and Missing Billing

## Problem

When deploying a Node.js backend to Fly.io, two sequential issues occurred:

1. `fly launch --region sea` failed with region not found
2. After fixing the region, `fly deploy` failed requiring billing information

### Error Messages

```
Error: region "sea" not found
```

```
Error: We need your payment information to continue!
```

## Investigation

Checked available regions:

```bash
fly platform regions
```

Seattle (SEA) was not in the list. The closest West Coast options were:
- `sjc` - San Jose, California
- `lax` - Los Angeles, California
- `pdx` - Portland, Oregon (not always available)

## Root Cause

1. **Region**: Fly.io uses its own region codes, not always matching airport codes. Seattle is not an available deployment region.
2. **Billing**: Even for small apps, Fly.io requires billing information on file before the first deploy. This is true even if usage falls within free tier limits.

## Solution

### Step 1: Use a valid region

```bash
fly launch --region sjc    # San Jose - closest to Seattle
```

### Step 2: Add billing information

Visit https://fly.io/dashboard/personal/billing and add a payment method, then redeploy:

```bash
fly deploy
```

### Fly.toml configuration that worked

```toml
app = 'pirate-radio-sync'
primary_region = 'sjc'

[build]

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 0

[[vm]]
  memory = '1gb'
  cpu_kind = 'shared'
  cpus = 1
```

## Prevention

- Check `fly platform regions` before choosing a region
- Have billing info added to Fly.io account before first deploy
- Use `sjc` as default West Coast US region for Fly.io deployments
