--- SELF-CONTAINED PLAN ---

# Control Plane: Throttle + Model + Dry-Run + Ignore + Rules (WS-03) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Make the Stop hook configurable and safer to operate (throttle knobs, model selection, dry-run, bypass patterns, project rules), without changing default behavior when unset.

**Architecture:** Consolidate configuration reads in `hooks/lib/config.sh` (env + settings), keep fast early exits, and keep stdout JSON contract stable. Extend the `hooks/redbull` CLI by adding subcommands as separate scripts under `hooks/cli/`.

**Tech Stack:** Bash + `jq`.

## Summary

The hook currently hard-codes throttle limits, context window size, and judge model, and always calls the judge even when obvious “bypass” conditions exist. Your task is to add environment/config knobs and a small CLI control surface while keeping the default behavior unchanged.

## Prerequisites

- WS-00 merged to `main`.
- WS-02 merged (recommended) if you want to add CLI subcommands without conflicts.
- WS-01 merged (recommended) for per-repo opt-in gating.
- Proving commands:
  - `./test/evals/run-evals.sh`
  - `./test/test-working-directory.sh`
  - New: `./test/test-control-plane.sh`

## Configuration Contract (Env Vars; Safe Defaults)

- `REDBULL_THROTTLE_LIMIT` (default `3`)
- `REDBULL_THROTTLE_WINDOW_SECONDS` (default `300`)
- `REDBULL_TRANSCRIPT_CONTEXT_LINES` (default `10`)
- `REDBULL_JUDGE_MODEL` (default `haiku`)
- `REDBULL_DRY_RUN` (`true|false`, default `false`)
- `REDBULL_IGNORE_PATTERNS_PATH` (optional; file with one literal substring per line)
- `REDBULL_PROJECT_RULES_PATH` (optional; overrides `.redbull/rules.md` and `.claude/redbull-rules.md`)

## Files

- Create:
  - `hooks/lib/prompt.sh`
  - `hooks/lib/ignore.sh`
  - `hooks/cli/status.sh`
  - `hooks/cli/reset.sh`
  - `test/test-control-plane.sh`
- Modify:
  - `hooks/lib/config.sh`
  - `hooks/lib/judge.sh`
  - `hooks/claude-judge-continuation.sh`
  - `hooks/redbull` (add dispatch entries if WS-02 exists; otherwise create it here)

## Implementation Steps

### Task 1: Extend `hooks/lib/config.sh` to support env overrides (no behavior change by default)

**Step 1:** Replace static defaults with:

```bash
MAX_CONTINUATIONS="${REDBULL_THROTTLE_LIMIT:-3}"
THROTTLE_WINDOW_SECONDS="${REDBULL_THROTTLE_WINDOW_SECONDS:-300}"
TRANSCRIPT_CONTEXT_LINES="${REDBULL_TRANSCRIPT_CONTEXT_LINES:-10}"
CLAUDE_MODEL="${REDBULL_JUDGE_MODEL:-haiku}"
REDBULL_DRY_RUN="${REDBULL_DRY_RUN:-false}"
```

**Step 2:** Add numeric validation helpers:
- If a numeric env var is set but not numeric, ignore it and keep defaults.

### Task 2: Add project rules injection (`hooks/lib/prompt.sh`)

**Step 1:** Create `prompt_build_evaluation_prompt <recent_context_json_array>` that:
- Starts from the existing prompt text (copy it from current script)
- If a rules file exists, appends:
  - `ADDITIONAL PROJECT RULES:` then the file content
- Bounds rules size (e.g., max 8KB); if bigger, truncate and add “…(truncated)”

**Rules file search order:**
1) `REDBULL_PROJECT_RULES_PATH` (if set, must exist + be readable)
2) `.redbull/rules.md` (relative to CWD)
3) `.claude/redbull-rules.md` (relative to CWD)

### Task 3: Add ignore-pattern bypass (`hooks/lib/ignore.sh`)

**Step 1:** Implement `ignore_should_approve_stop <recent_context_json_array>` that:
- Loads patterns from:
  - `REDBULL_IGNORE_PATTERNS_PATH` if set, else:
  - `.claude/redbull-ignore.txt` (relative to CWD) if present
- Treat each non-empty, non-comment line as a literal substring.
- If any pattern matches the compacted transcript text, echo the matched pattern and return success; otherwise echo empty.

Implementation approach:
- Convert JSON array to a single string via `jq -r '.[].content' | tr '\n' ' '`
- Use `grep -F` for literal matching (avoids regex footguns).

### Task 4: Wire prompt + ignore bypass into the Stop hook

**Step 1:** Before calling the judge:
- Call `matched="$(ignore_should_approve_stop "$RECENT_CONTEXT")"`
- If matched non-empty:
  - `emit_decision "approve" "Approved by ignore pattern: $matched"`
  - Clear throttle file
  - Exit 0

**Step 2:** Replace the prompt construction inside `judge_should_continue` to use `prompt_build_evaluation_prompt`.

### Task 5: Add dry-run mode (never blocks stopping)

**Step 1:** After getting `EVALUATION_RESULT`, compute `would_decision` as if normal.

**Step 2:** If `REDBULL_DRY_RUN=true`:
- Always output `approve` (allow stop)
- Still persist `last_decision.json` if WS-02 is merged (store a marker like `dry_run: true` in the artifact if you have that file)
- Do not increment throttle counts (dry-run should not create loops)

### Task 6: Add throttle CLI subcommands (`hooks/cli/status.sh`, `hooks/cli/reset.sh`)

**Step 1:** Implement `status` as:
- List all `/tmp/.claude-continue-throttle-*` files
- For each file, print: filename, count, timestamp, age in seconds
- Exit 0 even if none found.

**Step 2:** Implement `reset` as:
- Remove all `/tmp/.claude-continue-throttle-*` files, or accept `--session-id` to remove only one (optional).

### Task 7: Add a deterministic test (`test/test-control-plane.sh`)

Cover at least:
- Setting `REDBULL_THROTTLE_LIMIT=1` and simulating two “block” decisions causes the second run to approve due to throttle (you can use stub mode + `stop_hook_active=true`).
- `REDBULL_DRY_RUN=true` always yields `.decision="approve"` even when stub indicates should_continue=true.

### Task 8: Prove no regressions

Run:
- `./test/test-control-plane.sh`
- `./test/evals/run-evals.sh`
- `./test/test-working-directory.sh`

## Immediate Next Task

Add env-var overrides for throttle/model/context lines in `hooks/lib/config.sh` and validate they don’t change defaults when unset.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
sed -n '1,120p' hooks/lib/config.sh
```

