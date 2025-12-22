--- SELF-CONTAINED PLAN ---

# SessionStart Auto-Brief Script (WS-06) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** On `SessionStart`, generate a bounded `.claude/session-brief.md` that summarizes repo guidance files (AGENTS/README/plans) to reduce re-orientation costs.

**Architecture:** Standalone hook script that scans a small, fixed set of files with strict size limits and writes a deterministic brief. Do not register it in `hooks/hooks.json` in this workstream (that happens in INT-00).

**Tech Stack:** Bash + coreutils (optional `rg` if available).

## Summary

Starting a session often requires re-reading repo conventions. Your task is to implement a `SessionStart` hook script that writes a small “brief” file under `.claude/` using bounded, deterministic extraction.

## Prerequisites

- None to start (standalone script).
- For eventual activation: WS-01 must be merged (opt-in gate), then INT-00 registers it in `hooks/hooks.json`.

## Files

- Create:
  - `hooks/claude-sessionstart-brief.sh`
  - `test/test-sessionstart-brief.sh`

## Implementation Steps

### Task 1: Implement the brief generator (deterministic, bounded)

**Step 1:** Create `hooks/claude-sessionstart-brief.sh`:
- Read event JSON (ignore if invalid; approve).
- Opt-in gate: `REDBULL_SESSION_BRIEF_ENABLED=true` required, else approve.
- Create `.claude/` and write `.claude/session-brief.md`.

**Step 2:** Collect file snippets (max 60 lines per file, max 5 files):
- `AGENTS.md`
- `README.md`
- `CLAUDE.md`
- `PLAN.md` (if present)
- Newest `docs/plans/**/PLAN-OVERVIEW.md` (if present; optional)

Implementation suggestions:
- Use `head -n 60` for each file.
- Include missing-file handling in the brief.

**Step 3:** Output format:
- Title + timestamp
- “Key Commands” section (extract only from these files; do not execute anything)
- “Quality Gates” section if detected
- “Notes / Gotchas” section with short excerpts

### Task 2: Add a deterministic test

**Step 1:** Create `test/test-sessionstart-brief.sh`:
- Run hook from a temp dir containing stub `AGENTS.md`/`README.md`
- Set `REDBULL_SESSION_BRIEF_ENABLED=true`
- Assert `.claude/session-brief.md` exists and contains expected headings

## Immediate Next Task

Implement `hooks/claude-sessionstart-brief.sh` to write `.claude/session-brief.md` with strict size bounds and opt-in gating.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
ls
```

