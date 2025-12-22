# Phase 5: Stall Detection + User Override Feedback

**Date:** 2025-12-22
**Status:** Design (Optional, For Later)
**Depends On:** Phase 2 (v2 confidence) + Phase 3 (heuristics)

---
## Executive Summary

**Phase 5 adds stall detection and (optionally) user override feedback** to prevent endless “continue” loops that don’t make progress.  
Instead of relying only on a blunt continuation throttle, we compute a stall risk score using:
- repeated context fingerprints
- confidence trends
- repeated decision categories

High stall risk makes the system more conservative and can force a stop with guidance.

## Problem

The existing throttle prevents infinite loops but cannot distinguish between:
- legitimate multi-step progress, and
- repeated “continue” cycles with no real movement.

Users also lack a mechanism for the system to learn when it keeps making the wrong choice.

## Purpose

- Detect non-progress loops early and stop safely.
- Provide better user-facing diagnostics (“you may be stalled”).
- Establish hooks for learning from manual overrides when available.

## What This Phase Does

- Computes a stall risk score (0–100) using recent decision history.
- Persists stall metadata (risk score + context fingerprint).
- Adjusts decision thresholds when stall risk is high:
  - require higher confidence to continue
  - prefer stopping when uncertain
- Enhances `explain.sh` output with stall insights.

## What This Phase Does NOT Do

- Does not run code or compare diffs to measure “real progress”.
- Does not introduce a background service.
- Does not require override learning to ship (override logging can remain optional).

## Success Criteria

**Correctness**
- Existing scenarios unaffected when stall detection has insufficient history.
- New stall scenarios pass 5/5.

**Effectiveness**
- High-risk stall cycles are detected and handled conservatively.
- Users receive actionable output in `explain.sh --verbose`.

**Performance**
- Hashing and log reads add negligible overhead.

## Rollout / Safety Notes

- Stall detection should be advisory/conservative at first (don’t hard stop too aggressively).
- Use normalized fingerprints (e.g., last assistant content) to avoid “false progress” from window shifts.
- Keep logic deterministic and transparent in logs.

## Goal

Prevent infinite continue loops that produce no progress, and learn from user manual overrides.

**Problem it solves:** Assistant loops on same work repeatedly; throttle limit (3 continuations per 5 min) is crude; better to detect "we're not moving forward" and force stop + suggest next action.

---

## Current State

- Throttle: 3 continuations per 5-minute window → hard stop
- **Gap:** Doesn't detect if all 3 continuations are on same work (no progress) vs legitimate multi-step tasks

---

## Phase 5 Design: Stall Detection + Learning

### Architecture: Three-Tier Stall Detection

```
Hook Decision
    ↓
1. THROTTLE (existing) — Count-based limit
    └─ Reached 3 continuations in 5 min? → Hard stop
    ↓
2. STALL DETECTOR (NEW) — Similarity-based detection
    └─ Context unchanged from last 2 continuations? → Likely stalled
    └─ Write stall risk summary to explain.sh
    └─ Signal to Phase 5 logic: "be conservative"
    ↓
3. OVERRIDE FEEDBACK (NEW) — User manual corrections
    └─ User forced a stop (overrode continue decision)? → Log override
    └─ User's override pattern repeats? → Learn + adjust
```

### Stall Detection Algorithm

**Goal:** Detect when the transcript isn't meaningfully progressing.

**Signals:**
- Context hasn't changed significantly across last 5-10 decisions
- Confidence scores are declining (judge less certain)
- Same decision_category repeated 3+ times in a row

**Implementation:**

```bash
detect_stall() {
    local current_context="$1"
    local decision_log_file="$2"

    # Read last 5-10 decisions from log (window size for pattern detection)
    local last_decisions=$(tail -n 10 "$decision_log_file" 2>/dev/null)
    [[ -z "$last_decisions" ]] && return 1  # Not enough history

    # Check if current context is similar to previous contexts
    # IMPORTANT: Normalize to assistant messages only (strip timestamps, metadata)
    # to avoid false progress detection from reordering or minor formatting changes
    local prev_context=$(echo "$last_decisions" | head -n 1 | jq -r '.evaluation.reasoning // empty')
    [[ -z "$prev_context" ]] && return 1

    # Similarity check: compare hashes of normalized assistant message only
    local current_hash=$(echo "$current_context" | grep -o 'role.*assistant[^}]*' | sha256sum | cut -d' ' -f1)
    local prev_hash=$(echo "$prev_context" | sha256sum | cut -d' ' -f1)

    if [[ "$current_hash" == "$prev_hash" ]]; then
        # Context unchanged
        echo "context_unchanged"
        return 0
    fi

    # Check if confidence is declining (judge becoming less certain)
    local confidence_trend=$(echo "$last_decisions" | \
        jq -r '.evaluation.confidence // empty' | \
        awk 'BEGIN{prev=1; declining=0} {if($1<prev)declining++; prev=$1} END{print declining}')

    if [[ "$confidence_trend" -ge 2 ]]; then
        echo "confidence_declining"
        return 0
    fi

    # Check if same decision_category repeated 3+ times (matches window size)
    local category_count=$(echo "$last_decisions" | \
        jq -r '.evaluation.decision_category // empty' | \
        sort | uniq -c | sort -rn | head -1 | awk '{print $1}')

    if [[ "$category_count" -ge 3 ]]; then
        echo "same_category_repeated"
        return 0
    fi

    return 1
}
```

### Stall Risk Scoring

**Combine signals into risk score (0–100):**

```bash
calculate_stall_risk() {
    local context_change="$1"
    local confidence_trend="$2"
    local category_repeat="$3"
    local throttle_count="$4"

    local risk=0

    # Context unchanged = high risk (30 points)
    [[ "$context_change" == "0" ]] && risk=$((risk + 30))

    # Confidence declining = moderate risk (20 points)
    [[ "$confidence_trend" == "true" ]] && risk=$((risk + 20))

    # Category repeated = moderate risk (20 points)
    [[ "$category_repeat" -ge 3 ]] && risk=$((risk + 20))

    # Throttle count (15 points per continuation in window)
    risk=$((risk + (throttle_count * 15)))

    # Max 100
    [[ $risk -gt 100 ]] && risk=100

    echo "$risk"
}
```

### Decision Adjustment Based on Stall Risk

**When stall risk is HIGH (>70):**

If next decision is "continue" → reduce confidence threshold:
- Normal: confidence > 0.5 → continue
- High stall risk: confidence > 0.75 → continue (stricter)

If next decision is "stop" → allow unconditionally (even if judge says continue).

### Implementation: Three Files

#### 1. `hooks/lib/throttle.sh` — Store Context Hash

**Extend throttle record to include context fingerprint:**

```bash
throttle_write() {
    local throttle_file="$1"
    local continue_count="$2"
    local last_continue_time="$3"
    local context_hash="$4"  # NEW

    local record
    record=$(jq -n \
        --arg count "$continue_count" \
        --arg time "$last_continue_time" \
        --arg hash "$context_hash" \
        '{continue_count: $count, last_continue_time: $time, context_hash: $hash}')

    printf '%s\n' "$record" > "$throttle_file"
}

# Modified signature in claude-judge-continuation.sh
context_hash=$(echo "$RECENT_CONTEXT" | sha256sum | cut -d' ' -f1)
throttle_write "$THROTTLE_FILE" "$CONTINUE_COUNT" "$CURRENT_TIME" "$context_hash"
```

#### 2. `hooks/lib/emit.sh` — Store Context + Stall Risk

**Extend decision persistence to include stall metadata:**

```bash
persist_decision() {
    local decision="$1"
    local reason="$2"
    local stall_risk="$3"  # NEW
    local context_hash="$4"  # NEW

    # ... existing persistence code ...

    decision_json=$(jq -n \
        --arg ts "$timestamp" \
        --arg sid "$PERSIST_SESSION_ID" \
        --arg dec "$decision" \
        --arg reason "$reason" \
        --arg risk "$stall_risk" \
        --arg hash "$context_hash" \
        --argjson eval "$PERSIST_EVALUATION_RESULT" \
        '{
            timestamp: $ts,
            session_id: $sid,
            decision: $dec,
            reason: $reason,
            stall_risk: $risk,
            context_hash: $hash,
            evaluation: $eval
        }')
}
```

#### 3. `scripts/explain.sh` — Surface Stall Risk

**Add stall analysis to --verbose output:**

```bash
if [[ "$VERBOSE" == "true" ]]; then
    # ... existing output ...

    # NEW: Stall risk summary
    STALL_RISK=$(echo "$DECISION_JSON" | jq -r '.stall_risk // "N/A"')
    CONTEXT_HASH=$(echo "$DECISION_JSON" | jq -r '.context_hash // "N/A"')

    if [[ "$STALL_RISK" != "N/A" ]]; then
        echo ""
        echo "Stall Detection:"
        echo "  Risk Score:   $STALL_RISK/100"

        if [[ "$STALL_RISK" -gt 70 ]]; then
            echo "  Status:       ⚠️  HIGH RISK"
            echo "  Recommendation: Consider manual stop or reframe work"
        elif [[ "$STALL_RISK" -gt 40 ]]; then
            echo "  Status:       ⚠️  MODERATE RISK"
        else
            echo "  Status:       ✓ Low risk"
        fi

        echo "  Context Hash: ${CONTEXT_HASH:0:8}..."
    fi

    # Override feedback (if available)
    if [[ $(echo "$DECISION_JSON" | jq 'has("override_count")') == "true" ]]; then
        OVERRIDE_COUNT=$(echo "$DECISION_JSON" | jq '.override_count')
        echo ""
        echo "User Overrides:"
        echo "  Total Overrides in Session: $OVERRIDE_COUNT"
        if [[ "$OVERRIDE_COUNT" -gt 2 ]]; then
            echo "  Pattern Detected: Frequent manual corrections"
        fi
    fi
fi
```

### Test Scenarios (5 New Files, 91–95)

Each tests stall detection:

- **91:** Context identical for 3 continuations → high stall risk
- **92:** Confidence declining across 3 decisions → medium stall risk
- **93:** Same decision_category (incomplete_work) repeated 4x → medium risk
- **94:** Multiple stall signals combined → very high risk
- **95:** Throttle at limit (3/3) + stall detected → force stop

### Acceptance Criteria

- [ ] Stall detection calculates risk score (0–100) based on signals
- [ ] High stall risk (>70) forces conservative decision-making
- [ ] `explain.sh --verbose` shows stall risk + recommendations
- [ ] Decision log persists context hash for comparison
- [ ] All 5 new scenarios pass 5/5 runs
- [ ] All 90 previous scenarios still pass
- [ ] No performance degradation from hash calculations

### Proving Command

```bash
./test/evals/run-evals.sh

# Test stall detection:
source hooks/lib/judge.sh
detect_stall "$context" "$decision_log_file"
calculate_stall_risk "$context_change" "$confidence_trend" "$category_repeat" "$throttle_count"

# View stall risk in decision:
./scripts/explain.sh --verbose
```

### Files to Modify

| File | Change | Why |
|------|--------|-----|
| `hooks/lib/throttle.sh` | Add context hash to throttle record | Detect unchanged context |
| `hooks/lib/emit.sh` | Persist stall_risk + context_hash | Store stall metadata |
| `hooks/claude-judge-continuation.sh` | Calculate stall risk before judge call | Input to decision logic |
| `scripts/explain.sh` | Add stall risk rendering | User visibility |
| `test/evals/scenarios/` | Add 5 new scenarios (91–95) | Test stall detection |

### Optional: User Override Feedback (Future Enhancement)

When Claude Code exposes a signal for user-initiated stops:

```bash
# Pseudocode: on user manual stop (force-quit)
if [ "$USER_FORCED_STOP" = "true" ]; then
    # Log override
    override_record=$(jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg reason "$LAST_DECISION_REASON" \
        '{"timestamp": $ts, "overrode": $reason}')

    echo "$override_record" >> "$DECISION_DIR/overrides.jsonl"

    # Pattern analysis (if 3+ similar overrides)
    # → suggest reframing to user
fi
```

---

## Implementation Roadmap

### Phase 5a (Core Stall Detection)
1. Add context hashing to throttle
2. Calculate stall risk in hook
3. Adjust confidence threshold on high risk
4. Render stall risk in explain.sh

### Phase 5b (Override Learning, Optional)
1. Expose user-forced-stop signal (Claude Code feature)
2. Log overrides with context
3. Pattern analysis: "user frequently overrides after 2 continuations"
4. Suggestion: "This task might need reframing"

---

## Risk & Mitigations

| Risk | Mitigation |
|------|-----------|
| False positive: legitimate slow-moving work | Stall risk is input, not blocker; judge still decides |
| Context hash collision | Use SHA256 (negligible collision probability) |
| Stall detection too aggressive | Bias toward judge, not toward forced stop |
| Performance hit from hashing | Hashing is O(n) on context size; acceptable |
| User override data requires feature not yet exposed | Build framework now, activate when Claude Code supports it |

---

## How Phase 5 Builds on Earlier Phases

- **Phase 2:** Uses `confidence` score to detect declining certainty
- **Phase 3:** Heuristic signals bypass stall detection (they're deterministic)
- **Phase 4:** DoD logic combined with stall risk ("work incomplete + stalled" → force rethink)

---

## Stall Risk Interpretation

| Score | Status | Action |
|-------|--------|--------|
| 0–40 | ✓ Low Risk | Continue normally; judge makes decision |
| 40–70 | ⚠ Moderate Risk | Be conservative; judge uses higher confidence threshold |
| >70 | 🚨 High Risk | Force stop; suggest manual review of task framing |

---

## Example: Stall Risk Calculation

**Scenario:** 3 continuations, same context, declining confidence

```
Decision 1: confidence 0.90, context_hash abc123 → continue
Decision 2: confidence 0.75, context_hash abc123 → continue
Decision 3: confidence 0.62, context_hash abc123 → continue (now?)

Stall Risk Calculation:
  - Context unchanged (3/3): 30 points
  - Confidence declining (3 decisions): 20 points
  - Throttle count (3/3): 45 points (15 per decision)
  ─────────────────────────────────────
  Total: 95/100 → HIGH RISK 🚨

Action: Force stop + suggest rethinking task
```

---

## Glossary

- **Stall:** No progress despite continuations (context unchanged)
- **Stall Risk:** Score (0–100) indicating likelihood of stall
- **Context Hash:** SHA256 fingerprint of recent transcript
- **Override:** User manually stops despite judge recommendation to continue
- **Confidence Trend:** Whether judge confidence is increasing or declining

