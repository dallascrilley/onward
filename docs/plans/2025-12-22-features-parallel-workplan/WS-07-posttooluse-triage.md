--- SELF-CONTAINED PLAN ---

# PostToolUse Failure Triage Script (WS-07) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** On `PostToolUse`, detect failures (non-zero exit) and write a bounded triage artifact under `.claude/` with next steps, without auto-running fixes or blocking the user by default.

**Architecture:** Standalone hook script that fails open and only writes artifacts when it confidently detects an error. Do not register it in `hooks/hooks.json` in this workstream (that happens in INT-00). Stop gating behavior (blocking stop until triage acknowledged) is explicitly deferred to a follow-up integration step.

**Tech Stack:** Bash + `jq`.

## Summary

Tool failures often cause the assistant to stop too early without clear next steps. Your task is to implement a `PostToolUse` hook script that writes `.claude/triage.md` with a deterministic “what failed + what to try next” plan when a command fails.

## Prerequisites

- None to start (standalone script).
- For eventual activation: WS-01 must be merged (opt-in gate), then INT-00 registers it in `hooks/hooks.json`.

## Files

- Create:
  - `hooks/claude-posttooluse-triage.sh`
  - `test/test-posttooluse-triage.sh`

## Implementation Steps

### Task 1: Implement triage script (fail-open; artifact only)

**Step 1:** Create `hooks/claude-posttooluse-triage.sh`:
- Validate JSON input; invalid → approve.
- Opt-in gate: `REDBULL_TRIAGE_ENABLED=true` required, else approve.

**Step 2:** Extract likely error signals by trying multiple payload paths (because schema may vary):
- `exit_code`: `.exit_code // .tool_result.exit_code // .result.exit_code // empty`
- `command`: `.command // .tool.command // .tool_input.command // empty`
- `stdout`/`stderr`: `.stdout // .tool_result.stdout // empty`, `.stderr // .tool_result.stderr // empty`

If no `exit_code` detected → approve.

**Step 3:** If `exit_code != 0`, write `.claude/triage.md` containing:
- Timestamp + command
- Exit code
- First 40 lines of stderr/stdout (truncate)
- “Suggested next steps” (deterministic heuristics):
  - If stderr contains “command not found” → suggest installing deps / checking PATH
  - If contains “permission denied” → suggest checking permissions
  - If contains “Cannot find module” → suggest install step
  - Else suggest rerun with `-v` or show full output

### Task 2: Add deterministic tests

Create `test/test-posttooluse-triage.sh` that:
- Sends a minimal JSON event with `exit_code: 1` and stderr content
- Sets `REDBULL_TRIAGE_ENABLED=true`
- Asserts `.claude/triage.md` exists and includes “Exit code: 1”

## Immediate Next Task

Implement `hooks/claude-posttooluse-triage.sh` that writes `.claude/triage.md` on failure and otherwise approves.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
rg -n \"PostToolUse\" docs/ideas/2025-21-12-features/markdown/consolidated-feature-ideas.md
```

