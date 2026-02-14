---
title: "XcodeGen Succeeds but xcodebuild Fails Without Xcode.app"
category: build-errors
tags: [xcode, xcodegen, ios, swift, command-line-tools]
module: iOS Build
symptom: "xcodegen generate succeeds but xcodebuild fails with 'unable to find a destination matching the provided destination specifier'"
root_cause: "xcode-select points to CommandLineTools, not Xcode.app; xcodebuild requires full Xcode installation"
date: 2026-02-14
---

# XcodeGen Succeeds but xcodebuild Fails Without Xcode.app

## Problem

When scaffolding an iOS project with XcodeGen, `xcodegen generate` succeeds and creates a valid `.xcodeproj`, but `xcodebuild` fails because only Command Line Tools are installed (not the full Xcode.app).

### Error

```
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

Or destination-related errors when trying to build for iOS simulator.

## Root Cause

- `xcodegen` only needs Swift and basic tooling to generate the project file
- `xcodebuild` requires the full Xcode.app to compile iOS targets, access simulators, and link iOS SDKs
- `xcode-select -p` shows `/Library/Developer/CommandLineTools` instead of `/Applications/Xcode.app/Contents/Developer`

## Solution

### Install Xcode

Xcode can be installed for free from the Mac App Store — no Apple Developer Program membership required. A free Apple ID is sufficient.

After installation:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Workaround: Scaffold without building

If Xcode is still downloading, you can still:
1. Run `xcodegen generate` to create the `.xcodeproj`
2. Write all Swift source files
3. Write server-side code and tests
4. Run server tests with `node --test`

Everything except `xcodebuild` works without the full Xcode installation.

## Prevention

- When setting up a new iOS dev environment, install Xcode.app first (it's a large download)
- Plan non-Xcode tasks (server work, file scaffolding, tests) while Xcode downloads
- Verify with `xcode-select -p` that it points to Xcode.app before attempting builds
