--- SELF-CONTAINED PLAN ---

# Handoff Snapshot Artifact (WS-04) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** On approved stop, write a bounded, deterministic `.claude/handoff.md` snapshot in the project so the next session can pick up quickly.

**Architecture:** Generate the handoff artifact without extra model calls (deterministic). Include recent transcript excerpts and optional git signals. Never write outside the repo CWD; never run in judge mode.

**Tech Stack:** Bash + `jq` (+ `git` if available).

## Summary

Stopping loses context and forces re-orientation. Your task is to write a deterministic handoff file under `.claude/` on legitimate stops (decision = approve), without changing the hook’s stdout contract or adding new dependencies.

## Prerequisites

- WS-00 merged to `main`.
- Proving commands:
  - `./test/evals/run-evals.sh`
  - `./test/test-working-directory.sh`
  - New: `./test/test-handoff.sh`

## Artifact Contract

- Path: `.claude/handoff.md` (relative to hook CWD)
- Size bound: max 200 lines (truncate transcript excerpt if needed)
- Content sections:
  - Timestamp + session id
  - Stop decision reason
  - “Recent context” excerpt (last N messages)
  - Optional git info (if `git` repo and `git` exists): branch, `git diff --name-only` (max 50 lines)

## Files

- Create:
  - `hooks/lib/handoff.sh`
  - `test/test-handoff.sh`
- Modify:
  - `hooks/claude-judge-continuation.sh`

## Implementation Steps

### Task 1: Implement handoff writer (`hooks/lib/handoff.sh`)

**Step 1:** Create a function:
- `handoff_write_if_needed <decision> <session_id> <reason> <recent_context_json_array>`

Behavior:
- Only write if `decision="approve"`
- Skip if `CLAUDE_HOOK_JUDGE_MODE=true`
- Ensure `.claude/` exists (`mkdir -p .claude`)

**Step 2:** Deterministic markdown build (use `printf`):

- Render transcript excerpt as:
  - `- user: ...`
  - `- assistant: ...`
  - Truncate each content line to 200 chars to keep bounded.

**Step 3:** Add optional git section:
- If `git rev-parse --is-inside-work-tree` succeeds:
  - Branch: `git rev-parse --abbrev-ref HEAD`
  - Files touched: `git diff --name-only | head -n 50`

### Task 2: Wire handoff into the Stop hook

**Step 1:** Source `hooks/lib/handoff.sh`.

**Step 2:** After the decision is determined (both approve/block paths), call:
- `handoff_write_if_needed "$decision" "$SESSION_ID" "$final_reason" "$RECENT_CONTEXT"`

Ensure it’s called only after `RECENT_CONTEXT` exists; if context extraction failed, do nothing.

### Task 3: Add a deterministic test (`test/test-handoff.sh`)

**Step 1:** Use a temp directory as CWD, run the hook from there:
- Copy or reference the hook script by absolute path.
- Create `.claude/` in the temp dir.
- Create a transcript file in the temp dir.
- Run the hook with the transcript path and `STUB_EXPECTED_DECISION=false` (so it approves).

**Step 2:** Assert:
- `.claude/handoff.md` exists
- File contains “Session:” and “Reason:”

### Task 4: Prove no regressions

Run:
- `./test/test-handoff.sh`
- `./test/evals/run-evals.sh`
- `./test/test-working-directory.sh`

## Immediate Next Task

Create `hooks/lib/handoff.sh` and make it write `.claude/handoff.md` only when the hook approves stopping.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
mkdir -p .claude
```

