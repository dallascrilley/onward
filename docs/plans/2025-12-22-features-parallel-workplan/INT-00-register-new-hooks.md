--- SELF-CONTAINED PLAN ---

# Integration: Register New Hook Events (INT-00) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Register new hook events (`PreToolUse`, `SessionStart`, `PostToolUse`) in `hooks/hooks.json` in a single controlled PR, with opt-in gating and safe-by-default behavior.

**Architecture:** Only `hooks/hooks.json` changes in this PR (plus tiny glue if required). Each new hook script must fail open and be gated by settings/env vars so enabling is explicit.

**Tech Stack:** Bash hooks + manual Claude Code verification.

## Summary

Multiple workstreams can implement new hook scripts, but registering them is a high-conflict, high-risk change. Your task is to update `hooks/hooks.json` once, wire the new scripts via `hooks/run-hook.cmd`, and validate they are opt-in and safe.

## Prerequisites

- WS-01 merged to `main` (opt-in settings exists).
- WS-05, WS-06, WS-07 merged to `main` (scripts exist and have tests).
- Proving commands:
  - `./test/evals/run-evals.sh`
  - `./test/test-working-directory.sh`
  - `./test/test-pretooluse-guardrails.sh`
  - `./test/test-sessionstart-brief.sh`
  - `./test/test-posttooluse-triage.sh`

## Files

- Modify:
  - `hooks/hooks.json`

## Implementation Steps

### Task 1: Register scripts in `hooks/hooks.json`

**Step 1:** Add new hook keys alongside `Stop` using the same wrapper pattern:

- `PreToolUse` → `claude-guardrail-pretooluse.sh`
- `SessionStart` → `claude-sessionstart-brief.sh`
- `PostToolUse` → `claude-posttooluse-triage.sh`

Each command must look like:

```json
"command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" <script-name>"
```

### Task 2: Validate Stop hook behavior unchanged

Run:
- `./test/evals/run-evals.sh`
- `./test/test-working-directory.sh`

### Task 3: Validate new script tests

Run:
- `./test/test-pretooluse-guardrails.sh`
- `./test/test-sessionstart-brief.sh`
- `./test/test-posttooluse-triage.sh`

### Task 4: Manual Claude Code verification (required)

**Step 1:** Install plugin locally:
- `/plugin marketplace add /path/to/redbull`
- `/plugin install redbull@redbull-dev`

**Step 2:** Restart Claude Code (required after `hooks/hooks.json` changes).

**Step 3:** Enable features explicitly (choose one):
- Env vars (session-level): set `REDBULL_GUARDRAILS_ENABLED=true`, `REDBULL_SESSION_BRIEF_ENABLED=true`, `REDBULL_TRIAGE_ENABLED=true`
- Or per-project settings (if WS-01 expanded to include these toggles)

**Step 4:** Verify:
- `SessionStart` produces `.claude/session-brief.md` (once per session)
- Dangerous shell command attempts get blocked by `PreToolUse`
- A failing command produces `.claude/triage.md` under `.claude/`

## Immediate Next Task

Update `hooks/hooks.json` to register `PreToolUse`, `SessionStart`, and `PostToolUse` using `hooks/run-hook.cmd`.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
cat hooks/hooks.json
```

