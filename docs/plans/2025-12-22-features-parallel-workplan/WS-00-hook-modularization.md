--- SELF-CONTAINED PLAN ---

# Hook Modularization (WS-00) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Refactor the Stop hook into small `hooks/lib/*.sh` modules so later feature work can happen in parallel with minimal merge conflicts.

**Architecture:** Extract existing logic from `hooks/claude-judge-continuation.sh` into pure helper modules (`emit`, `throttle`, `transcript`, `judge`) while preserving behavior. Keep stdout JSON-only via a single emitter.

**Tech Stack:** Bash + `jq` + existing eval harness.

## Summary

This repo’s features concentrate changes into `hooks/claude-judge-continuation.sh`, which creates merge conflicts. Your task is to extract stable helper functions into `hooks/lib/*.sh` and update the Stop hook to orchestrate them without changing behavior.

## Prerequisites

- Base branch: `main`
- Must not change the Stop hook external contract (stdin JSON → stdout JSON).
- Proving commands:
  - `./test/evals/run-evals.sh`
  - `./test/test-working-directory.sh`

## Codebase Context (What Exists Today)

- Stop hook: `hooks/claude-judge-continuation.sh`
  - Defines constants (throttle/context/model/workdir)
  - Defines `emit_decision()` and throttle helpers
  - Reads stdin JSON with `jq`
  - Extracts transcript context from NDJSON transcript file
  - Calls `claude --print ... --output-format json --json-schema ...`
  - Outputs `{decision, reason}` JSON only
- Hook registration: `hooks/hooks.json` (Stop only)
- Tests:
  - `./test/evals/run-evals.sh` (scenario suite)
  - `./test/test-working-directory.sh` (asserts `claude` runs in `~/.claude/double-shot-latte`)

## Files

- Create:
  - `hooks/lib/emit.sh`
  - `hooks/lib/throttle.sh`
  - `hooks/lib/transcript.sh`
  - `hooks/lib/judge.sh`
  - `hooks/lib/config.sh`
- Modify:
  - `hooks/claude-judge-continuation.sh`

## Implementation Steps (Small, Verifiable Units)

### Task 1: Create `hooks/lib/emit.sh`

**Step 1:** Create file with a single emitter.

```bash
#!/bin/bash

emit_decision() {
  local decision="$1"
  local reason="$2"
  jq -n --arg d "$decision" --arg r "$reason" '{"decision": $d, "reason": $r}'
}
```

**Step 2:** Ensure it’s executable: `chmod +x hooks/lib/emit.sh`

**Step 3:** Quick sanity: `bash -n hooks/lib/emit.sh`

### Task 2: Create `hooks/lib/throttle.sh` (move existing functions verbatim)

**Step 1:** Copy these functions from `hooks/claude-judge-continuation.sh` into the new file (no behavior changes):
- `throttle_file_for_session`
- `throttle_read`
- `throttle_write`
- `throttle_should_force_stop`
- `throttle_clear`

**Step 2:** Put them in a file with shebang:

```bash
#!/bin/bash

# Globals expected from caller:
# - CURRENT_TIME
# Globals set by throttle_read:
# - CONTINUE_COUNT
# - LAST_CONTINUE_TIME
```

**Step 3:** Ensure it’s executable and syntactically valid:
- `chmod +x hooks/lib/throttle.sh`
- `bash -n hooks/lib/throttle.sh`

### Task 3: Create `hooks/lib/transcript.sh` (move transcript validation + context extraction)

**Step 1:** Create a helper that validates the transcript file path and returns a safe, error string (empty = ok).

```bash
#!/bin/bash

validate_transcript_path() {
  local transcript_path="$1"
  if [ -z "$transcript_path" ]; then echo "No transcript path provided"; return 0; fi
  if [ ! -f "$transcript_path" ]; then echo "Transcript file not found"; return 0; fi
  if [ ! -r "$transcript_path" ]; then echo "Transcript file not readable"; return 0; fi
  if [ ! -s "$transcript_path" ]; then echo "Transcript file is empty"; return 0; fi
  echo ""
}
```

**Step 2:** Create `extract_recent_context_json_array()` that returns a JSON array (or `[]`) exactly like the current behavior:

```bash
extract_recent_context_json_array() {
  local transcript_path="$1"
  local context_lines="$2"

  tail -n 50 "$transcript_path" 2>/dev/null | \
    grep -v '^[[:space:]]*$' | \
    while IFS= read -r line; do
      printf '%s\n' "$line" | jq -e '.' >/dev/null 2>&1 && printf '%s\n' "$line"
    done | \
    tail -n "$context_lines" | \
    jq -s '.' 2>/dev/null
}
```

**Step 3:** Ensure executable + `bash -n`.

### Task 4: Create `hooks/lib/config.sh` (defaults only; no feature flags yet)

**Step 1:** Create a `load_defaults()` function that sets variables exactly as the current script does.

```bash
#!/bin/bash

load_defaults() {
  MAX_CONTINUATIONS=3
  THROTTLE_WINDOW_SECONDS=300
  TRANSCRIPT_CONTEXT_LINES=10
  CLAUDE_MODEL="haiku"
  CLAUDE_WORK_DIR="$HOME/.claude/double-shot-latte"
}
```

**Step 2:** Ensure executable + `bash -n`.

### Task 5: Create `hooks/lib/judge.sh` (move schema/prompt/call/parse)

**Step 1:** Create a function that takes `recent_context_json_array` and returns `structured_output` JSON (or empty string).

```bash
#!/bin/bash

judge_should_continue() {
  local recent_context="$1"
  local claude_model="$2"
  local claude_work_dir="$3"

  local json_schema='{"type":"object","properties":{"should_continue":{"type":"boolean"},"reasoning":{"type":"string"}},"required":["should_continue","reasoning"]}'
  local system_prompt="You are a conversation state classifier. Your only job is to analyze conversation transcripts and determine if the assistant has more autonomous work to do. You output structured JSON. You do not write code or use tools."

  mkdir -p "$claude_work_dir"

  local evaluation_prompt
  evaluation_prompt="Analyze this conversation and determine: Does the assistant have more autonomous work to do RIGHT NOW?

Conversation:
$recent_context

CONTINUE (should_continue: true) ONLY IF the assistant explicitly states what it will do next:
- Phrases indicating intent to continue (e.g., 'Next I need to...', 'Now I'll...', 'Moving on to...')
- Incomplete todo list with remaining items marked pending
- Stated follow-up tasks not yet performed

STOP (should_continue: false) in ALL other cases:

1. TASK COMPLETION - The assistant indicates work is finished:
   - Completion statements (done, complete, finished, ready, all set)
   - Summary of accomplished work with no stated next steps
   - Confirming something is working/verified/installed

2. QUESTIONS - The assistant needs user input:
   - Asking for approval, decisions, clarification, or confirmation
   - Offering optional actions (e.g., 'Want me to...?', 'Should I also...?')
   - Note: Mid-task continuation questions (e.g., 'Should I continue?' when work is ongoing) = CONTINUE

3. BLOCKERS - The assistant cannot proceed:
   - Unresolved errors or missing information
   - Uncertainty about requirements

KEY: If the assistant is WAITING for the user (whether after completing work OR asking a question), that means STOP. Waiting ≠ more autonomous work to do.

Default to STOP when uncertain."

  local claude_response
  claude_response=$(printf '%s' "$evaluation_prompt" | (cd "$claude_work_dir" && CLAUDE_HOOK_JUDGE_MODE=true claude --print --model "$claude_model" --output-format json --json-schema "$json_schema" --system-prompt "$system_prompt" --disallowedTools '*') 2>/dev/null) || return 1

  printf '%s' "$claude_response" | jq '.[] | select(.type == "result") | .structured_output // empty' 2>/dev/null
}
```

**Step 2:** Ensure executable + `bash -n`.

### Task 6: Update `hooks/claude-judge-continuation.sh` to orchestrate libs

**Step 1:** At top of file, source the new modules (use absolute path based on the script location):

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/emit.sh"
source "$SCRIPT_DIR/lib/throttle.sh"
source "$SCRIPT_DIR/lib/transcript.sh"
source "$SCRIPT_DIR/lib/judge.sh"
```

**Step 2:** Replace the inlined constants with `load_defaults`:
- Call `load_defaults` once after sourcing.

**Step 3:** Replace the inlined transcript validation/extraction with:
- `validation_error=$(validate_transcript_path "$TRANSCRIPT_PATH")`
- `RECENT_CONTEXT=$(extract_recent_context_json_array "$TRANSCRIPT_PATH" "$TRANSCRIPT_CONTEXT_LINES")`

**Step 4:** Replace the inlined judge call/parse with:
- `EVALUATION_RESULT=$(judge_should_continue "$RECENT_CONTEXT" "$CLAUDE_MODEL" "$CLAUDE_WORK_DIR")`

**Step 5:** Keep all existing early-exit behavior the same (invalid JSON input, missing transcript, judge mode, etc).

### Task 7: Prove no regressions

**Step 1:** Run eval suite:
- Run: `./test/evals/run-evals.sh`
- Expected: all scenarios pass (5/5 each).

**Step 2:** Run working directory test:
- Run: `./test/test-working-directory.sh`
- Expected: PASS, claude ran in `~/.claude/double-shot-latte`.

## Immediate Next Task

Create `hooks/lib/emit.sh` and wire it into the Stop hook.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
mkdir -p hooks/lib
```

