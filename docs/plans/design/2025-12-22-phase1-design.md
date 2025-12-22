# Phase 1: Permission Language Prefilter

**Date:** 2025-12-22
**Status:** Design (Foundational Phase)
**Depends On:** None (can ship immediately)

---
## Executive Summary

**Phase 1 adds a permission-language prefilter that decides “continue vs stop” without calling the judge in obvious cases.**  
It scans the **last assistant message** for highly specific phrases that indicate Claude is either:
- **Permission-seeking to continue** → we **BLOCK stop** (continue), or
- **Truly waiting on a user decision** → we **APPROVE stop** (stop)

This phase is intentionally conservative and designed to ship immediately.

## Problem

Claude often stops to ask for confirmation in situations where it’s clearly safe to proceed (e.g., “Should I continue?”).  
Today, we pay for a judge call on every stop attempt, even when the answer is obvious.

## Purpose

- Reduce premature stopping caused by politeness/caution.
- Avoid unnecessary judge calls for a predictable, frequent pattern category.
- Lay groundwork for later phases by adding structured, testable early-exit behavior.

## What This Phase Does

- Adds a new prefilter step between “ignore patterns” and “judge”.
- Uses **high precision** keyword/regex matching on the **last assistant message only**.
- Emits a final decision immediately when a match is detected.

## What This Phase Does NOT Do

- No changes to judge prompt/schema.
- No new persistence format or analytics.
- No multi-message or semantic reasoning beyond last assistant message.
- No “confidence scoring” or “soft prompt” behavior.

## Success Criteria

**Correctness**
- Existing scenarios: **all pass 5/5**
- New scenarios: **all pass 5/5**
- Target: **~0 false positives** in the eval suite
- In production: **extremely low**; ambiguous cases must fall back to judge

**Impact**
- Skip **~5–15%** of judge calls (measured via debug logs)
- Reduced “Should I continue?” annoyance in real usage

## Rollout / Safety Notes

- If no pattern matches, we fall back to the judge (unchanged behavior).
- If parsing fails or message extraction fails, we fall back to the judge.
- Debug logs must clearly indicate “permission prefilter” vs “judge” path.

## Goal

Skip the Claude evaluator for obvious cases where the assistant is asking for permission or clearly continuing work. Reduce unnecessary stops by recognizing explicit permission-language patterns before invoking the judge.

**Target:** Skip ~5–15% of judge calls for obvious permission-seeking and obvious continuation signals.

---

## Current State

- Judge evaluates every transcript (100% of cases)
- Hook flow: ignore patterns → judge → decision
- **Gap:** Common permission-seeking language ("Should I continue?") still goes to judge, even though the answer is obvious

---

## Phase 1 Design: Permission Language Prefilter

### Architecture: Two-Tier Pattern Matching

```
Transcript
    ↓
1. IGNORE PATTERNS (existing)
    └─ Match .redbull/ignore.txt → approve stop immediately
    ↓
2. PERMISSION LANGUAGE PREFILTER (NEW)
    ├─ PERMISSION-SEEKING patterns
    │  ├─ "Should I continue?"
    │  ├─ "Shall I proceed?"
    │  └─ "Is it OK if I...?"
    │  → BLOCK stop (work is ongoing, assistant asking for permission)
    │
    └─ NEEDS-USER-CHOICE patterns
       ├─ "Which/prefer/choose" (explicit decision)
       ├─ "Does this look good?" (approval needed)
       └─ "Want me to/should I also...?" + optional framing
       → APPROVE stop (waiting for user decision)
    ↓
3. JUDGE (fallback for ambiguous)
    └─ If no pattern matches, call judge for final decision
```

### Signal Patterns: Permission-Seeking → BLOCK (Continue)

Detect permission-language (assistant asking if it should keep going):

| Pattern | Detection | Example | Decision |
|---------|-----------|---------|----------|
| **Should I continue?** | Keyword: "should i continue" | "Should I continue implementing?" | BLOCK |
| **Asking to proceed** | Keywords: "shall i", "can i proceed", "ready to proceed" | "Shall I proceed with the next step?" | BLOCK |
| **Confirming intent** | Keywords: "is it ok if", "is it alright if", "would it be ok to" | "Is it OK if I now create the tests?" | BLOCK |

**Detection strategy:**
- Case-insensitive keyword matching
- Look in last assistant message only (most relevant)
- Err on side of caution: if unsure, fall back to judge

### Signal Patterns: User Input Needed → APPROVE (Stop)

Detect **explicit** requests for user input or truly optional offers:

#### 2a. Explicit User Choice Required → APPROVE (Stop)

| Pattern | Detection | Example | Decision |
|---------|-----------|---------|----------|
| **Asking for decision** | Keywords: "which", "prefer", "choose" + offer 2+ options | "Which approach do you prefer?" | APPROVE |
| **Asking for approval** | Keywords: "does this look/seem good", "is this ok/correct" + change description | "Does this design look good?" | APPROVE |

**Detection:** Require either an explicit choice (A or B) or descriptive context ("Does this approach...")

#### 2b. Optional Work (Truly Optional) → APPROVE (Stop)

| Pattern | Detection | Example | Decision |
|---------|-----------|---------|----------|
| **Framed as optional** | Keywords: "optional", "nice.?to.?have", "if you want", "I can also" | "I can add error handling (optional)" | APPROVE |
| **Want me to add X?** | "want me to" + contains "optional" or "extra" or "nice" | "Want me to add caching? (nice to have)" | APPROVE |

**Detection:** Require explicit optional/nice-to-have/if-you-want framing

#### 2c. Unsure / Default to Continue

| Pattern | Example | Decision |
|---------|---------|----------|
| **Should I also X (core work)?** | "Should I also write tests?" | BLOCK (continue) |
| **Want me to X (core work)?** | "Want me to add validation?" | BLOCK (continue) |

**Rationale:** Many workflows expect "also add tests" as core completeness, not optional. Only stop if it's explicitly optional.

**Detection strategy:**
- Case-insensitive matching
- Require **question mark** in last message (high precision)
- Require decision context (A vs B, optional keyword, approval context)
- Conservative: if unsure, fall back to judge (bias toward continue)

### Implementation: Prefilter Function

**New in `hooks/lib/judge.sh`:**

```bash
# Detect permission language from transcript
detect_permission_language() {
    local recent_context="$1"

    # Extract last assistant message (most relevant)
    local last_assistant=$(echo "$recent_context" | jq -r '.[] | select(.role=="assistant") | .content' | tail -1)

    [[ -z "$last_assistant" ]] && return 1

    # Must have question mark (high precision)
    [[ ! "$last_assistant" =~ \? ]] && return 1

    # PERMISSION-SEEKING patterns (ask to continue work)
    # Note: "is it ok if" pattern loosened to match "Is it OK if I create tests?" (without requiring "continue")
    if grep -Eqi "should i continue|shall i proceed|is it (ok|alright|fine) if i|ready to proceed" <<< "$last_assistant"; then
        echo "permission_seeking"
        return 0
    fi

    # EXPLICIT CHOICE REQUIRED (which option? approval needed?)
    # Pattern: "which/prefer/choose" OR "does this...look/seem/sound good"
    if grep -Eqi "(which.*prefer|prefer.*which|choose|which option)" <<< "$last_assistant"; then
        echo "explicit_choice_required"
        return 0
    fi

    if grep -Eqi "does this.*(look|seem|sound).*(good|ok|correct|work)|is this.*ok" <<< "$last_assistant"; then
        echo "explicit_choice_required"
        return 0
    fi

    # OPTIONAL WORK (only if explicitly framed as optional)
    # Pattern: "want me to/should i also/add" + ("optional" OR "nice-to-have" OR "if you want")
    if grep -Eqi "(want me to|should i also).*(optional|nice.?to.?have|if you want)" <<< "$last_assistant"; then
        echo "optional_offer"
        return 0
    fi

    # Default: "should i also X" or "want me to X" without optional framing → CONTINUE
    # Don't detect as stop signal; fall back to judge

    # No detected pattern
    return 1
}

# Decide based on permission language
permission_language_decision() {
    local pattern="$1"

    case "$pattern" in
        permission_seeking)
            echo "block"  # CONTINUE (work is ongoing, assistant asking for permission)
            ;;
        explicit_choice_required|optional_offer)
            echo "approve"  # STOP (waiting for user decision/input)
            ;;
        *)
            echo ""  # Unknown pattern → fall back to judge
            ;;
    esac
}
```

### Hook Integration Point

**In `hooks/claude-judge-continuation.sh` between ignore patterns and judge (around line 148–150):**

```bash
# --- Check permission language (NEW, Phase 1) ---
PERMISSION_PATTERN=$(detect_permission_language "$RECENT_CONTEXT" 2>/dev/null) || true

if [ -n "$PERMISSION_PATTERN" ]; then
    PERMISSION_DECISION=$(permission_language_decision "$PERMISSION_PATTERN")

    if [ -n "$PERMISSION_DECISION" ]; then
        debug_log "permission_language" --arg pattern "$PERMISSION_PATTERN" --arg decision "$PERMISSION_DECISION"

        if [ "$PERMISSION_DECISION" = "block" ]; then
            emit_decision "block" "Permission-seeking language detected: assistant asking if it should continue → block stop (continue work)"
            exit 0
        elif [ "$PERMISSION_DECISION" = "approve" ]; then
            emit_decision "approve" "User choice needed: assistant offering optional work or asking for decision"
            exit 0
        fi
    fi
fi

# --- Call the judge (unchanged, fallback for ambiguous) ---
```

### Files to Modify

| File | Change | Why |
|------|--------|-----|
| `hooks/lib/judge.sh` | Add `detect_permission_language()` + `permission_language_decision()` | Pattern matching functions |
| `hooks/claude-judge-continuation.sh` | Add permission check before judge invocation | Skip judge for obvious patterns |
| `test/evals/scenarios/` | Add 5–10 new scenarios (from existing 65) | Test permission language coverage |

### Test Scenarios (5–10 New Files)

Add to existing 65 scenarios to test Phase 1:

**New Scenarios for Permission-Seeking (BLOCK):**

- **New 1:** "Should I continue implementing?" → block (permission seeking)
- **New 2:** "Shall I proceed with creating tests?" → block (permission seeking)
- **New 3:** "Is it OK if I now create the migration?" → block (permission seeking)

**New Scenarios for Needs User Choice (APPROVE):**

- **New 4:** "Want me to add caching? (optional)" → approve (explicitly optional)
- **New 5:** "Should I also write documentation? (nice to have)" → approve (explicitly optional)
- **New 6:** "Does this design look good?" → approve (needs approval)
- **New 7:** "Which approach would you prefer?" → approve (asking for decision)

**Edge Cases:**

- **New 8:** "I should continue, right?" vs "Should I continue?" (guard false positives)
- **New 9:** Multiple questions in one message (handle correctly)
- **New 10:** Permission language in user message, not assistant (ignore)

### Acceptance Criteria

- [ ] Permission-language prefilter detects "should I continue?" accurately
- [ ] Permission-language prefilter detects "want me to...?" accurately
- [ ] Ambiguous transcripts fall back to judge (conservative)
- [ ] All new scenarios pass 5/5 runs
- [ ] All 65 existing scenarios still pass 5/5 runs
- [ ] Debug logs show which path (permission vs judge) was used
- [ ] Target: ~0 false positives in eval suite; ambiguous cases fall back to judge

### Proving Command

```bash
./test/evals/run-evals.sh

# Check permission language detection:
source hooks/lib/judge.sh
recent_context='[{"role":"assistant","content":"Should I continue implementing?"}]'
detect_permission_language "$recent_context"
# Expected: "permission_seeking"

# Check decision mapping:
permission_language_decision "permission_seeking"
# Expected: "block"
```

### Risk & Mitigations

| Risk | Mitigation |
|------|-----------|
| False positive: "should" appears in other context | High precision matching (require full phrase context) |
| Regex performance on large transcripts | Only scan last message (most relevant) |
| Pattern misses valid permission language | Scenarios catch misses; debug logs show "fell back to judge" |
| Keyword collision (e.g., "want" in narrative) | Require question mark or decision context |

---

## Implementation Order

1. **Implement pattern matcher** → `hooks/lib/judge.sh`
2. **Add hook integration** → `hooks/claude-judge-continuation.sh`
3. **Add test scenarios** → `test/evals/scenarios/` (5–10 new)
4. **Verify existing tests** → Ensure all 65 scenarios still pass
5. **Run full suite** → `./test/evals/run-evals.sh`

---

## Phase 1 Vs. Phase 3: Why Two Prefilters?

Both Phase 1 and Phase 3 skip the judge, but they use different signals:

| Phase | Signal Type | Detection | Why Separate |
|-------|---|---|---|
| **Phase 1** | Linguistic patterns | Regex/keywords | Ships immediately; simple; low risk |
| **Phase 3** | Structured signals | Judge output patterns | Depends on Phase 2 (v2 schema); more sophisticated |

**Timeline:**
- Phase 1: Ship first (simple, obvious cases)
- Phase 2: Add v2 schema (enables Phase 3)
- Phase 3: Add heuristics (deeper pattern analysis)

**Redundancy:** Phase 3 may re-detect Phase 1 patterns. This is OK:
- Phase 1 decides fast (linguistic)
- Phase 3 confirms or refines (structured signals)
- No conflict; just more confident decisions

---

## How Phase 1 Builds Toward Future Phases

- **Phase 2:** v2 schema captures signals that Phase 1 detects linguistically
- **Phase 3:** Structured signals enable more sophisticated heuristics
- **Phase 4:** DoD logic can reference Phase 1 patterns ("if asking_for_approval, check DoD first")
- **Phase 5:** Stall detection can skip Phase 1 decisions (they're deterministic, not LLM-based)

---

## Quick Reference: Permission Language Patterns

### BLOCK (Continue, Work Ongoing)

```bash
# Permission-seeking
grep -Eqi "should i continue" ← BLOCK
grep -Eqi "shall i proceed" ← BLOCK
grep -Eqi "is it (ok|alright) if" ← BLOCK
```

### APPROVE (Stop, Waiting for User)

```bash
# Explicit choice required
grep -Eqi "which.*prefer|choose" ← APPROVE
grep -Eqi "does this (look|seem).*good" ← APPROVE

# Optional work (only with explicit optional framing)
grep -Eqi "(want me to|should i also).*(optional|nice.?to.?have|if you want)" ← APPROVE

# Note: "want me to" or "should i also" WITHOUT optional framing → fall back to judge
```

---

## Glossary

- **Permission-seeking:** Assistant asking if it should keep working ("Should I continue?")
- **Needs user choice:** Assistant offering optional work or asking for decision ("Want me to...?")
- **Prefilter:** Check before calling judge (permission language, then judge)
- **Fallback:** Call judge if prefilter can't decide

---

## Example: Permission Language Detection

### Example 1: Permission-Seeking (BLOCK)

**Transcript:**
```
User:      "Create a REST API with CRUD operations"
Assistant: "I've created the GET and POST endpoints. Should I continue with PUT and DELETE?"
```

**Detection:**
```
detect_permission_language(...) → "permission_seeking"
permission_language_decision("permission_seeking") → "block"
Decision: BLOCK (continue work, assistant asking for permission)
```

**Why:** Work is incomplete, assistant asking if it should keep going. Obvious answer: yes, continue.

### Example 2: Needs User Choice (APPROVE)

**Transcript:**
```
User:      "Build a user service"
Assistant: "Created CRUD endpoints. Want me to add authentication? (optional)"
```

**Detection:**
```
detect_permission_language(...) → "optional_offer"
permission_language_decision("optional_offer") → "approve"
Decision: APPROVE (stop, wait for user decision)
```

**Why:** Assistant finished baseline work, offering optional feature with explicit optional framing. Should wait for user input.

**Note:** Without "(optional)" framing, this would fall back to judge (conservative approach).

### Example 3: Ambiguous (Fall Back to Judge)

**Transcript:**
```
User:      "Add user profiles"
Assistant: "Done. The user profile system is complete and tested."
```

**Detection:**
```
detect_permission_language(...) → "" (no match)
→ Fall back to judge
Judge: should_continue = false
Decision: APPROVE (stop, work complete)
```

**Why:** No permission language. Judge evaluates "done" status.

---

## Success Metrics

- ✅ All 65 existing scenarios pass 5/5 runs
- ✅ All 5–10 new permission-language scenarios pass 5/5 runs
- ✅ Permission-seeking detection accuracy: >95%
- ✅ Needs-user-choice detection accuracy: >95%
- ✅ Target: ~0 false positives in eval suite; ambiguous cases fall back to judge
- ✅ ~5–15% of judge calls skipped

---

## Acceptance Checklist

Before Phase 1 is complete:

- [ ] Permission pattern matcher implemented in `judge.sh`
- [ ] Hook integration added to `claude-judge-continuation.sh`
- [ ] 5–10 new test scenarios created
- [ ] All 75 scenarios (65 existing + 10 new) pass 5/5 runs
- [ ] Debug logs show "permission_language" path for detected cases
- [ ] No regression: all existing scenarios still pass
- [ ] False positive test: ambiguous transcripts still go to judge
- [ ] README.md updated to document Phase 1 behavior

---

## Files Checklist

| File | Change | Status |
|------|--------|--------|
| `hooks/lib/judge.sh` | Add pattern matcher functions | Implement |
| `hooks/claude-judge-continuation.sh` | Add prefilter check | Implement |
| `test/evals/scenarios/` | Add 5–10 new scenarios | Create |
| `README.md` | Document Phase 1 | Update |

---

## Timeline & Dependencies

- **Can ship:** Immediately (no dependencies)
- **Prerequisite:** None
- **Builds toward:** Phase 2 (v2 schema), Phase 3 (heuristics)
- **Estimated effort:** 2–3 days (pattern matching + tests)

---

## Comparison: Phase 1 vs Later Phases

| Aspect | Phase 1 | Phase 3 | Phase 4 | Phase 5 |
|--------|---------|---------|---------|---------|
| **Detection** | Regex keywords | v2 signals | DoD criteria | Context hash + confidence |
| **Complexity** | Low | Medium | Medium | High |
| **Judge calls skipped** | ~5–15% | ~40–60% (Phase 1 + 3) | Same as Phase 3 | Same as Phase 3 |
| **User config** | None | None | Optional | Optional |
| **Ship timing** | Immediately | After Phase 2 | After Phase 3 | Optional |

