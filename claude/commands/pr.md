---
description: Create a PR with a generated title and body based on git diff and commits
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(git status:*), Bash(git push:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(gh pr create:*), Bash(gh repo view:*)
---

## Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log origin/HEAD..HEAD --oneline 2>/dev/null || git log -10 --oneline`
- Changed files: !`git diff origin/HEAD..HEAD --stat 2>/dev/null || git diff HEAD~5..HEAD --stat`

## Rules

- NEVER use `--force` or `--force-with-lease` when pushing
- NEVER use `--no-verify` to skip hooks

## Your task

1. Run `git diff origin/HEAD..HEAD` (or `git diff HEAD~5..HEAD` if that fails) to understand the full diff
2. Extract the ticket ID from the current branch name (e.g. `ADEPT-35624` from `feat/ADEPT-35624-something`). If found, include the Ticket section; if not, omit it entirely.
3. Push the branch to origin if not pushed: `git push -u origin HEAD`
4. Create a PR using `gh pr create` with:
   - A short, descriptive title (under 70 chars) based on the actual changes
   - A body in this format (pass via HEREDOC). No Summary section — don't list file-by-file changes, the diff already shows that:

```
## Ticket

[TICKET-ID](https://adeptmind.atlassian.net/browse/TICKET-ID)

## Context

<short prose on what this PR changes and why — the problem, the approach, anything non-obvious a reviewer should know. Be honest about gaps/assumptions.>

## What to test

<short bullets of areas/flows/pages the reviewer or QA should check, e.g. "VSM page on lululemon — A-Z index and subcategory links". Not step-by-step test cases, no checkboxes.>

```

Notes on the format:
- Keep everything short, crisp, and easy to understand — plain simple English, no jargon, no fluff. A reviewer should get it in one quick read.
- **Context** = what + why, as prose. No file lists, no old → new value dumps.
- **What to test** = areas to check, not detailed test cases or steps.
- Omit the Ticket section entirely if no ticket ID is in the branch name.

Return the PR URL when done.
