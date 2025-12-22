--- SELF-CONTAINED PLAN ---

# Decision Logs + Explain Command (WS-02) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Persist the last judge decision (and optional append-only decision log) and provide a CLI to explain what happened, without changing the hook’s stdout contract.

**Architecture:** Write JSON artifacts under a single state directory (`$REDBULL_STATE_DIR`, default `~/.claude/redbull`). Add a `hooks/redbull` CLI that dispatches to `hooks/cli/*.sh` subcommands to reduce merge conflicts with other workstreams.

**Tech Stack:** Bash + `jq`.

## Summary

Users don’t know why Redbull blocked or approved a stop. Your task is to persist the last decision to a stable path and implement `redbull explain` so users can inspect the reasoning quickly.

## Prerequisites

- WS-00 merged to `main`.
- Optional but recommended: WS-01 merged (for future opt-in toggles; not required for this workstream).
- Proving commands:
  - `./test/evals/run-evals.sh`
  - `./test/test-working-directory.sh`
  - New: `./test/test-explain.sh`

## Artifact Contract

**Directory:** `${REDBULL_STATE_DIR:-$HOME/.claude/redbull}`  
**Files:**
- `last_decision.json` (always overwritten)
- `decision-log.ndjson` (optional; bounded/rotated; gated by env var or settings)

**last_decision.json schema (example):**

```json
{
  "timestamp": "2025-12-22T12:34:56Z",
  "session_id": "abc123",
  "hook": "Stop",
  "decision": "block",
  "reason": "Claude evaluator determined continuation is appropriate: ...",
  "judge": {
    "model": "haiku",
    "should_continue": true,
    "reasoning": "…",
    "confidence": 83
  }
}
```

## Files

- Create:
  - `hooks/lib/state.sh`
  - `hooks/lib/decision-log.sh`
  - `hooks/redbull`
  - `hooks/cli/explain.sh`
  - `test/test-explain.sh`
- Modify:
  - `hooks/lib/judge.sh`
  - `hooks/claude-judge-continuation.sh`

## Implementation Steps

### Task 1: Add state directory helper (`hooks/lib/state.sh`)

**Step 1:** Implement:
- `state_dir()` → echoes state dir and ensures it exists
- `state_write_json <filename> <json_string>` → atomic write

Skeleton:

```bash
#!/bin/bash

state_dir() {
  local dir="${REDBULL_STATE_DIR:-$HOME/.claude/redbull}"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

state_write_json() {
  local filename="$1"
  local json="$2"
  local dir
  dir="$(state_dir)"
  local path="$dir/$filename"
  local tmp
  tmp="$(mktemp "${path}.tmp.XXXXXX")" || return 1
  printf '%s\n' "$json" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$path" || { rm -f "$tmp"; return 1; }
}
```

### Task 2: Extend judge structured output to include optional confidence (`hooks/lib/judge.sh`)

**Step 1:** Update the JSON schema to include optional `confidence`:

```json
{"type":"object","properties":{"should_continue":{"type":"boolean"},"reasoning":{"type":"string"},"confidence":{"type":"integer"}},"required":["should_continue","reasoning"]}
```

**Step 2:** Update the evaluation prompt to request confidence 0–100, but keep decision logic based only on `should_continue`:
- Add a single bullet: “Include `confidence` 0–100.”

**Step 3:** Ensure the parser still works if confidence is absent (treat as null).

### Task 3: Persist `last_decision.json` from the Stop hook

**Step 1:** Create `hooks/lib/decision-log.sh` with:
- `build_last_decision_json <session_id> <decision> <reason> <judge_json> <model>` → outputs JSON

Use `jq -n` to construct. Example:

```bash
build_last_decision_json() {
  local session_id="$1"
  local decision="$2"
  local reason="$3"
  local judge_json="$4"
  local model="$5"

  jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$session_id" \
    --arg decision "$decision" \
    --arg reason "$reason" \
    --arg model "$model" \
    --argjson judge "$judge_json" \
    '{timestamp:$ts, session_id:$sid, hook:"Stop", decision:$decision, reason:$reason, judge:($judge + {model:$model})}'
}
```

**Step 2:** In `hooks/claude-judge-continuation.sh`, after deciding:
- Build JSON via `build_last_decision_json`
- Write it via `state_write_json "last_decision.json" "$json"`
- This must happen for both `block` and `approve` paths.

### Task 4: Add `hooks/redbull` CLI with subcommand dispatch

**Step 1:** Create `hooks/redbull`:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cmd="${1:-}"
shift || true

case "$cmd" in
  explain) exec "$SCRIPT_DIR/cli/explain.sh" "$@" ;;
  *) echo "Usage: redbull explain" >&2; exit 2 ;;
esac
```

**Step 2:** `chmod +x hooks/redbull`

### Task 5: Implement `redbull explain` (`hooks/cli/explain.sh`)

**Step 1:** Read `${REDBULL_STATE_DIR:-$HOME/.claude/redbull}/last_decision.json` and pretty print:

- Show: decision, model, should_continue, confidence (if present), reasoning, timestamp.
- If missing file: print a helpful error and exit 1.

Example:

```bash
#!/bin/bash
set -euo pipefail

STATE_DIR="${REDBULL_STATE_DIR:-$HOME/.claude/redbull}"
FILE="$STATE_DIR/last_decision.json"
if [ ! -f "$FILE" ]; then
  echo "No last decision found at $FILE" >&2
  exit 1
fi

jq -r '
  "Decision: \(.decision)\nWhen: \(.timestamp)\nSession: \(.session_id)\nModel: \(.judge.model)\nShould continue: \(.judge.should_continue)\nConfidence: \(.judge.confidence // "n/a")\n\nReason:\n\(.reason)\n\nJudge reasoning:\n\(.judge.reasoning)\n"
' "$FILE"
```

### Task 6: Add a deterministic test (`test/test-explain.sh`)

**Step 1:** Create a temp state dir, write a minimal `last_decision.json`, and run `hooks/redbull explain`.

- Command: `REDBULL_STATE_DIR="$tmp" ./hooks/redbull explain`
- Expected: exit 0 and output includes “Decision: block” (or chosen fixture).

### Task 7: Prove no regressions

Run:
- `./test/test-explain.sh`
- `./test/evals/run-evals.sh`
- `./test/test-working-directory.sh`

## Immediate Next Task

Add `hooks/lib/state.sh` and wire the Stop hook to persist `last_decision.json`.

## First Step

```bash
cd /Users/dallascrilley/Code/dallas-plugin-marketplace/redbull
mkdir -p hooks/cli
```

