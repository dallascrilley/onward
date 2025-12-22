--- SELF-CONTAINED PLAN ---

# PreToolUse Guardrails Script (WS-05) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Add a `PreToolUse` hook script that blocks a small set of catastrophic command patterns and suggests safe alternatives, while failing open (approve) for unknown payloads and when disabled.

**Architecture:** Implement as a standalone hook script (`hooks/claude-guardrail-pretooluse.sh`) with conservative parsing and a strict allowlist of block patterns. Do not register it in `hooks/hooks.json` in this workstream (that happens in INT-00).

**Tech Stack:** Bash + `jq`.

## Summary

Expanding beyond Stop is higher-stakes. Your task is to implement a safe-by-default `PreToolUse` guardrail hook script that only blocks when it confidently detects dangerous commands, and otherwise approves.

## Prerequisites

- None to start (standalone script).
- For eventual activation: WS-01 must be merged (opt-in gate), then INT-00 registers it in `hooks/hooks.json`.

## Safety Defaults

- If JSON is invalid → approve.
- If the tool type/command string cannot be extracted → approve.
- If disabled by config/settings → approve.
- Never output anything except the JSON decision to stdout.

## Files

- Create:
  - `hooks/claude-guardrail-pretooluse.sh`
  - `test/test-pretooluse-guardrails.sh`

## Implementation Steps

### Task 1: Implement the guardrail hook (fail-open)

**Step 1:** Create `hooks/claude-guardrail-pretooluse.sh` with:
- Shebang: `#!/bin/bash`
- Read event JSON from stdin
- Validate JSON via `jq empty`
- Extract a “candidate command string” from common fields (try multiple):
  - `.tool.command`
  - `.command`
  - `.tool_input.command`
  - `.input.command`
  - `.tool.parameters.command`

**Step 2:** Implement `emit_decision` locally (do not depend on WS-00 libs in this plan).

**Step 3:** Add opt-in gate (for now env-based):
- If `REDBULL_GUARDRAILS_ENABLED` != `true` → approve with reason “Guardrails disabled”

**Step 4:** Block patterns (literal or simple regex; keep tight):
- `rm -rf /`
- `rm -rf ~`
- `git reset --hard`
- `git clean -fdx`
- `curl .*\\|\\s*sh`
- `wget .*\\|\\s*sh`

**Step 5:** For each block, suggest a safer alternative in the reason string:
- Example: for `git reset --hard`, suggest `git status` and `git restore --staged ...` etc.

### Task 2: Add a deterministic test script

**Step 1:** Create `test/test-pretooluse-guardrails.sh` that:
- Pipes a minimal JSON payload containing a dangerous command into the hook
- Sets `REDBULL_GUARDRAILS_ENABLED=true`
- Asserts `.decision == "block"`

**Step 2:** Add a second case with unknown payload shape; assert approve.

### Task 3: Manual verification guidance (required before INT-00)

In the PR description, include:
- How to temporarily register the hook in `hooks/hooks.json` for local testing (do not commit that change in this workstream).
- How to capture a real `PreToolUse` event payload (set `REDBULL_DEBUG=true` and write event JSON to `/tmp/redbull-last-pretooluse.json` on stderr or a temp file).

## Immediate Next Task

Create `hooks/claude-guardrail-pretooluse.sh` that fails open and blocks only a tiny curated set of catastrophic commands.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
cat hooks/hooks.json
```

