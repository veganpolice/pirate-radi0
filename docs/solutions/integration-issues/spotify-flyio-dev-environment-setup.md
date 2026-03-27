---
title: "Spotify + Fly.io + Apple Developer Environment Setup"
category: integration-issues
tags: [spotify, fly-io, apple-developer, testflight, oauth, setup, onboarding]
module: project-setup
date: 2026-02-14
symptoms:
  - new project needs external service accounts
  - spotify client id not configured
  - fly cli not authenticated
  - testflight distribution blocked
---

# Spotify + Fly.io + Apple Developer Environment Setup

## Problem

Setting up a new iOS project that depends on Spotify SDK, a Fly.io backend, and Apple TestFlight distribution requires multiple external accounts, API keys, and CLI tools configured correctly before development can proceed.

## Key Learnings

### Spotify Developer Setup

1. **Create app at** https://developer.spotify.com/dashboard
2. **Client ID** is on the app overview page — a hex string like `441011e5cfc04417a7c9bc73fc295939`
3. **Client Secret is NOT needed** for iOS apps using PKCE auth flow
4. **Redirect URI** must be set in dashboard — use `pirate-radio://auth/callback` for dev, switch to Universal Link for production
5. **Enable iOS SDK**: App Settings → "Which APIs are you planning to use?" → check Web API + iOS
6. **Dev Mode caps you at 5 test users** — add them under User Management
7. **Apply for Extended Quota Mode immediately** — approval timeline is unpredictable and blocks testing beyond 5 users

### Fly.io Setup

1. Sign up at https://fly.io/app/sign-up
2. Install CLI: `brew install flyctl`
3. Authenticate: `fly auth login` (opens browser)
4. No app creation needed until backend code is ready — then `fly launch` + `fly deploy`

### Apple Developer Program

- **NOT required for local development** — you can build and run on your own iPhone with a free Apple ID (Personal Team signing in Xcode)
- **IS required for**: TestFlight, App Store, Push Notifications, Associated Domains (Universal Links)
- Free Apple ID signing: apps expire after 7 days, need to rebuild
- Enrollment is $99/year, can take up to 48 hours to activate
- **Address validation can lock you out** — ensure your Apple ID contact info at https://appleid.apple.com is complete before applying

### TestFlight Without Developer Program

- **Not possible** — TestFlight requires App Store Connect, which requires the Developer Program
- **Workaround**: Build directly to friend's iPhone via USB from Xcode (same 7-day limit)
- Set up the app in App Store Connect and add testers *before* uploading a build — then the first upload triggers invites immediately

## Configuration Locations

| Service | Key | Where It Goes |
|---------|-----|---------------|
| Spotify Client ID | `441011e5cfc04417a7c9bc73fc295939` | `PirateRadio/Core/Spotify/SpotifyAuth.swift:12` |
| Spotify Redirect URI | `pirate-radio://auth/callback` | `SpotifyAuth.swift:13` + Spotify Dashboard |
| Fly.io auth | CLI session | `fly auth login` stores locally |
| Backend URL | `pirate-radio-sync.fly.dev` | `WebSocketTransport.swift` |

## Order of Operations

1. Spotify Developer account + create app + get Client ID (blocks all Spotify work)
2. Fly.io account + CLI install + auth (blocks backend deployment)
3. Apple Developer enrollment (blocks TestFlight only — not local dev)
4. Download custom fonts (non-blocking, cosmetic)
5. Domain DNS setup (blocks Universal Links only — not needed for dev)

## Prevention / Future Reference

- When starting a new project with external dependencies, enumerate all accounts and API keys needed *before* writing code
- Apply for any quota/access extensions (like Spotify Extended Quota) on day one
- Apple Developer enrollment address issues can be resolved at https://appleid.apple.com → Personal Information → Contact Information
