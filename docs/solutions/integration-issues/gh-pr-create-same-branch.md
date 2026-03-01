---
title: "gh pr create Fails When Default Base Matches Current Branch"
category: integration-issues
tags: [github, gh-cli, pull-request, git]
module: CI/CD
symptom: "gh pr create fails with 'can't open pull request with same base and head'"
root_cause: "gh defaults --base to current branch when repo has no default branch configured or HEAD is ambiguous"
date: 2026-02-14
---

# gh pr create Fails When Default Base Matches Current Branch

## Problem

Running `gh pr create` on a feature branch fails because the CLI picks the current branch as both `--base` and `--head`.

### Error

```
pull request create failed: GraphQL: No commits between main and main
```

Or:

```
can't open a pull request with the same base and head
```

## Root Cause

When a repository is newly created or the default branch isn't clearly configured in the remote, `gh` may default `--base` to the current branch instead of `main`/`master`.

## Solution

Always specify `--base` and `--head` explicitly:

```bash
gh pr create --base main --head feat/my-feature --title "My PR" --body "Description"
```

## Prevention

- Always use `--base main` (or your default branch) when creating PRs with `gh`
- For new repos, ensure the default branch is set: `gh repo edit --default-branch main`
