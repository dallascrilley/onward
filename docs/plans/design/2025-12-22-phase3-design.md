# Phase 3: Signals and Heuristics Beyond Permission Language

**Date:** 2025-12-22
**Status:** Design
**Depends On:** Phase 2 (v2 schema with signals field)

---
## Executive Summary

**Phase 2 upgrades the judge output to a “v2” structured JSON response** by adding fields like
`confidence`, `decision_category`, `signals`, and `risk_level` while keeping the existing required fields
(`should_continue`, `reasoning`) intact.

This phase is the foundation for later improvements (heuristics, DoD enforcement, stall detection) without changing the core “approve vs block” hook behavior.

## Problem

We currently only get a binary decision from the judge. That makes it hard to:
- Explain decisions to the user
- Tune behavior (thresholds, escalation)
- Build deterministic prefilters that learn from judge “signals”
- Detect uncertainty, risk, or repeated patterns over time

## Purpose

- Make judge output automation-ready and diagnosable.
- Preserve backward compatibility so existing logic remains stable.
- Provide structured signals that later phases can consume.

## What This Phase Does

- Extends judge response schema with optional fields:
  - `confidence: 0..1`
  - `decision_category: enum`
  - `signals: enum[]`
  - `risk_level: low|medium|high`
- Updates judge prompt to reliably populate these fields.
- Updates CLI (`explain.sh`) to display v2 fields when present.
- Updates test harness to optionally validate v2 fields (ranges / any-of checks).

## What This Phase Does NOT Do

- Does not change the final decision rule: `should_continue` still drives block/approve.
- Does not add new prefilters or skip-judge logic (that’s Phase 1/3).
- Does not enforce “DoD” or stall detection yet.

## Success Criteria

**Compatibility**
- All existing scenarios pass (unchanged expectations).
- v1-only outputs remain acceptable (fields can be missing/null).

**Quality**
- New v2 scenarios pass with range-based expectations (confidence/category/risk/signals).
- `explain.sh --verbose` renders v2 fields safely (no crashes on missing fields).

**Diagnostics**
- Decision persistence includes the full evaluation payload when present.

## Rollout / Safety Notes

- If v2 fields are missing or invalid, treat them as null and proceed with v1 behavior.
- If the judge returns invalid JSON, fail open (approve stop) or fall back safely as current behavior dictates.
- Prefer range checks in tests to avoid flakiness.

## Goal

Reduce Claude evaluator calls by recognizing explicit signals in the transcript **without calling the judge**. Use pattern matching on clear "stop signals" and clear "continue signals" to make fast decisions upstream.

**Target:** Skip ~40–60% of judge calls for obvious cases (credential requests, explicit next steps, offering optional work).

---

## Current State (After Phase 2)

- Judge returns `signals` array: 12 predefined signal types
- Hook flow: ignore patterns → judge → decision
- Decision logic: based purely on `should_continue` boolean

**Gap:** Signals are detected but not used. Every transcript still goes to judge unless ignored.

---

## Phase 3 Design: Heuristic Prefilter

### Architecture: Three-Tier Signal Processing

```
Transcript
    ↓
1. IGNORE PATTERNS (existing)
    └─ Match .redbull/ignore.txt → approve stop immediately
    ↓
2. HEURISTIC PREFILTER (NEW)
    └─ Look for explicit stop signals
    ├─ asking_for_approval
    ├─ asking_for_decision
    ├─ asking_for_clarification
    ├─ offering_optional_work
    ├─ missing_information
    └─ → approve stop WITHOUT calling judge
    └─ Look for explicit continue signals
    ├─ explicit_next_steps
    ├─ stated_todo_items
    └─ → block stop WITHOUT calling judge
    ↓
3. JUDGE (fallback for ambiguous)
    └─ If no clear signal, call judge for final decision
```

### Signal Detection Heuristics

#### Stop Signals (Approve Stop Without Judge)

| Signal Pattern | Detection | Example |
|---|---|---|
| **Asking for approval** | Keywords: "approve", "ok?", "look good?", "wording clear?", "does this work?" | "Does this design look correct?" |
| **Asking for decision** | Keywords: "choose", "which", "prefer?", "option A or B?" | "Which approach is better?" |
| **Asking for clarification** | Keywords: "clarify", "explain", "what should", "how should" | "Can you clarify the requirements?" |
| **Offering optional work** | Keywords: "want me to", "should I also", "optional", "nice-to-have" | "Want me to add caching?" |
| **Missing information** | Keywords: "credentials", "API key", "need to know", "missing", "where is" | "I need database credentials" |

#### Continue Signals (Block Stop Without Judge)

| Signal Pattern | Detection | Example |
|---|---|---|
| **Explicit next steps** | Keywords: "next I", "then I'll", "moving on to", "now I need to" | "Next I need to create logout handler" |
| **Stated todo items** | Patterns: numbered lists, bullet points with pending items | "1. Create model  2. Add tests  3. Deploy" |

### Implementation: Signal Matcher Function

**New in `hooks/lib/judge.sh`:**

```bash
# Detect signal from transcript
detect_heuristic_signal() {
    local recent_context="$1"

    # Extract last assistant message (most relevant)
    local last_assistant=$(echo "$recent_context" | jq -r '.[] | select(.role=="assistant") | .content' | tail -1)

    # STOP signals (conservative: only if very clear)
    if grep -qi "does this.*\(look\|work\|seem\)" <<< "$last_assistant"; then
        echo "asking_for_approval"
        return 0
    fi

    if grep -Eqi "(which|choose|prefer|option.*or)" <<< "$last_assistant"; then
        echo "asking_for_decision"
        return 0
    fi

    if grep -Eqi "(clarif|explain|what should|how should)" <<< "$last_assistant"; then
        echo "asking_for_clarification"
        return 0
    fi

    if grep -Eqi "(want me to|should i also|optional|nice-to-have)" <<< "$last_assistant"; then
        echo "offering_optional_work"
        return 0
    fi

    if grep -Eqi "(credential|api.?key|need.*(password|token)|where is)" <<< "$last_assistant"; then
        echo "missing_information"
        return 0
    fi

    # CONTINUE signals (conservative: only if very clear)
    if grep -Eqi "(next i|then i'll|moving on to|now i need to)" <<< "$last_assistant"; then
        echo "explicit_next_steps"
        return 0
    fi

    if echo "$last_assistant" | grep -Eqi "^[[:space:]]*[0-9]+\.|^[[:space:]]*-[[:space:]]" > /dev/null; then
        # Check if list has uncompleted items
        if grep -Eqi "(todo|pending|need|remaining|not yet)" <<< "$last_assistant"; then
            echo "stated_todo_items"
            return 0
        fi
    fi

    # No clear signal
    return 1
}

# Decide based on heuristic signal (if detected)
heuristic_should_stop() {
    local signal="$1"

    case "$signal" in
        asking_for_approval|asking_for_decision|asking_for_clarification|offering_optional_work|missing_information)
            echo "true"  # STOP
            ;;
        explicit_next_steps|stated_todo_items)
            echo "false" # CONTINUE
            ;;
        *)
            echo ""  # Unknown signal
            ;;
    esac
}
```

### Hook Integration Point

**In `hooks/claude-judge-continuation.sh` around line 148–150:**

```bash
# --- Check heuristic signals (NEW, Phase 3) ---
HEURISTIC_SIGNAL=$(detect_heuristic_signal "$RECENT_CONTEXT" 2>/dev/null) || true

if [ -n "$HEURISTIC_SIGNAL" ]; then
    HEURISTIC_DECISION=$(heuristic_should_stop "$HEURISTIC_SIGNAL")

    if [ "$HEURISTIC_DECISION" = "true" ]; then
        # Clear stop signal - don't call judge
        debug_log "heuristic_signal" --arg signal "$HEURISTIC_SIGNAL" --arg decision "approve"
        emit_decision "approve" "Heuristic detected '$HEURISTIC_SIGNAL' → user input needed"
        exit 0
    elif [ "$HEURISTIC_DECISION" = "false" ]; then
        # Clear continue signal - don't call judge
        debug_log "heuristic_signal" --arg signal "$HEURISTIC_SIGNAL" --arg decision "block"
        emit_decision "block" "Heuristic detected '$HEURISTIC_SIGNAL' → work continues"
        exit 0
    fi
fi

# --- Call the judge (unchanged, fallback for ambiguous) ---
```

### Files to Modify

| File | Change | Why |
|------|--------|-----|
| `hooks/lib/judge.sh` | Add `detect_heuristic_signal()` + `heuristic_should_stop()` | Pattern matching functions |
| `hooks/claude-judge-continuation.sh` | Add heuristic check before judge invocation | Skip judge for obvious signals |
| `test/evals/scenarios/` | Add 10 new scenarios (71–80) for heuristic coverage | Test signal detection |

### Test Scenarios (10 New Files, 71–80)

Each tests one heuristic signal path:

- **71:** "Does this look good?" → approve (asking_for_approval)
- **72:** "Which approach?" → approve (asking_for_decision)
- **73:** "Can you clarify?" → approve (asking_for_clarification)
- **74:** "Want me to add caching?" → approve (offering_optional_work)
- **75:** "Need API credentials" → approve (missing_information)
- **76:** "Next I'll create logout" → block (explicit_next_steps)
- **77:** "TODO: 1. Create 2. Test 3. Deploy" → block (stated_todo_items)
- **78:** Ambiguous transcript → falls back to judge (should match judge output)
- **79:** Signal detection with context variations (multiple messages)
- **80:** Edge case: looks like signal but isn't (false positive guard)

### Acceptance Criteria

- [ ] Heuristic prefilter detects all 5 stop signals accurately (high precision)
- [ ] Heuristic prefilter detects all 2 continue signals accurately
- [ ] Ambiguous transcripts fall back to judge (conservative)
- [ ] All 10 new scenarios pass 5/5 runs
- [ ] All 70 existing scenarios still pass 5/5 runs
- [ ] Debug logs show which path (heuristic vs judge) was used
- [ ] ~40–60% of judge calls are skipped (measured via debug logs)

### Proving Command

```bash
./test/evals/run-evals.sh

# Check heuristic usage:
REDBULL_DRY_RUN=true EVAL_OFFLINE=1 bash -x ./hooks/claude-judge-continuation.sh \
    <<< '{"session_id":"test","transcript_path":"/path/to/transcript.json","stop_hook_active":false}'
# Should show "heuristic_signal" in debug output
```

### Risk & Mitigations

| Risk | Mitigation |
|------|-----------|
| False positive: pattern matches wrong case | Conservative matching (high precision); ambiguous → judge |
| Regex performance on large transcripts | Only scan last message (most relevant) |
| Pattern misses real signals | Debug logs show "fell back to judge"; scenarios catch misses |
| Keyword collision ("next" in other context) | Require phrase context ("next I", not just "next") |
| Credential detection matches normal text | Require credential-ish noun nearby (token, key, password, env, secret) OR phrase pattern ("I need X" / "I can't proceed without") |
| Clarification pattern catches normal explanations | Add `?` requirement or explicit phrase patterns ("can you clarify", "what would you like") |

### How Phase 3 Relates to Phase 2

- **Independent from Phase 2 technically** — Phase 3 uses regex/keyword heuristics (not judge output)
- **Informed by Phase 2** — v2 schema provides a taxonomy and lets you compare heuristic guesses vs judge output for tuning/validation
- **Detection:** Uses simple keyword patterns (regex) instead of judge evaluation
- **Fallback:** If no pattern matches, calls judge (which returns full v2 signals array for analysis/comparison)
- **Preserves:** All v2 field generation when judge is called

### Phase 4 & 5 Impact

- **Phase 4 (DoD):** DoD rules can reference heuristic signals ("if asking_for_approval, ask user for confirm")
- **Phase 5 (Stall):** Stall detection skips heuristic decisions (they're already deterministic, not LLM-based)

---

## Implementation Order

1. **Implement signal matcher** → `hooks/lib/judge.sh`
2. **Add hook integration** → `hooks/claude-judge-continuation.sh`
3. **Add test scenarios** → `test/evals/scenarios/71-80`
4. **Update harness** → Log heuristic vs judge paths
5. **Verify** → Run tests, measure judge call reduction

---

## Quick Reference: Signal Detection Patterns

### Stop Signals (Approve Without Judge)

```bash
# Asking for approval
grep -Eqi "does this.*(look|work|seem|make sense)" ← STOP

# Asking for decision
grep -Eqi "(which|choose|prefer|option.*or)" ← STOP

# Asking for clarification
grep -Eqi "(clarif|explain|what should|how should)" ← STOP

# Offering optional work
grep -Eqi "(want me to|should i also|optional)" ← STOP

# Missing information
grep -Eqi "(credential|api key|password|need)" ← STOP
```

### Continue Signals (Block Without Judge)

```bash
# Explicit next steps
grep -Eqi "(next i|then i'll|moving on to|now i)" ← CONTINUE

# Stated todos
grep -Eqi "^[[:space:]]*[0-9]+\.|^[[:space:]]*-" + grep "todo|pending" ← CONTINUE
```

---

## Glossary

- **Heuristic:** Pattern-matching rule (regex or keyword)
- **Signal:** Type of communication in transcript (asking_for_approval, etc.)
- **Prefilter:** Check before calling judge (ignore patterns, heuristics)
- **Fallback:** Call judge if prefilter can't decide

