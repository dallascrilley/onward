# Phase 2: Structured Judge Output (JSON v2) - Design Document

**Date:** 2025-12-22
**Status:** Design (Ready for Implementation)

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

## 1. Proposed v2 Schema

### Design Principle
- **Backward Compatible:** v1 fields (`should_continue`, `reasoning`) are required and unchanged
- **Automation-Ready:** New fields enable pattern detection and confidence-based decisions
- **Diagnostic:** Rich signal metadata helps debug edge cases
- **Phase-Ready:** Fields designed to support Phase 3, 4, 5 without schema changes

### v2 JSON Schema

```json
{
  "type": "object",
  "properties": {
    "should_continue": {
      "type": "boolean",
      "description": "Primary decision: should work continue?"
    },
    "reasoning": {
      "type": "string",
      "description": "Full explanation of the decision"
    },
    "reasons": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Structured list of reasons (for logging and analysis)"
    },
    "confidence": {
      "type": "number",
      "minimum": 0,
      "maximum": 1,
      "description": "Confidence in decision (0=uncertain, 1=very certain)"
    },
    "decision_category": {
      "type": "string",
      "enum": [
        "explicit_continuation",
        "task_completion",
        "waiting_for_user",
        "blocker",
        "incomplete_work",
        "uncertain"
      ],
      "description": "Why decision was made"
    },
    "signals": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": [
          "explicit_next_steps",
          "explicit_completion",
          "asking_for_approval",
          "asking_for_decision",
          "asking_for_clarification",
          "offering_optional_work",
          "incomplete_implementation",
          "error_blocking_progress",
          "missing_information",
          "mid_task_question",
          "stated_todo_items",
          "offering_continuation_question"
        ]
      },
      "description": "Detected signal types from transcript"
    },
    "risk_level": {
      "type": "string",
      "enum": ["low", "medium", "high"],
      "description": "Risk of continuing (high = edge case, low = safe)"
    },
    "next_action": {
      "type": "string",
      "description": "What the assistant should do next (if should_continue=true)"
    },
    "constraints": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Any constraints or blockers that affect the decision"
    }
  },
  "required": ["should_continue", "reasoning"]
}
```

### Field Rationale

| Field | Purpose | Phase Support | Example |
|-------|---------|---|---------|
| `should_continue` | Primary decision | All | `true` |
| `reasoning` | Human-readable full explanation | All | "Clear next steps stated" |
| `reasons` | Structured list for logging/analysis | Phase 3+ (pattern analysis) | `["explicit_next_steps", "tests_not_written"]` |
| `confidence` | Certainty score (0-1) | Phase 5 (stall detection), debugging | `0.95` |
| `decision_category` | Classification of decision | Phase 3 (heuristics), pattern analysis | `"explicit_continuation"` |
| `signals` | Detected signal types | Phase 3/4 (heuristics, DoD), debugging | `["explicit_next_steps", "incomplete_implementation"]` |
| `risk_level` | Continuation risk assessment | Phase 4 (DoD), Phase 5 (stall) | `"low"` |
| `next_action` | What happens if continue | Phase 4+ (DoD alignment) | `"Create logout handler"` |
| `constraints` | Blockers/constraints on decision | Phase 4+ (DoD analysis) | `["missing_api_key", "tests_failing"]` |

---

## 2. Phase 2 Implementation Map

### Files to Modify (in order)

#### **Step 1: Update Judge Schema & Prompt**
**File:** `hooks/lib/judge.sh`

**Changes:**
- Expand `JUDGE_JSON_SCHEMA` constant (line 8) to include new fields
- Update `JUDGE_SYSTEM_PROMPT` (line 10) to instruct evaluator about new fields
- Add helper function `build_v2_evaluation_prompt()` that instructs Claude to return signals + category + confidence
- Keep `build_evaluation_prompt()` unchanged (for snapshot testing)

**Code pattern:**
```bash
JUDGE_JSON_SCHEMA='{"type":"object","properties":{...},"required":["should_continue","reasoning"]}'

# New function for v2
build_v2_evaluation_prompt() {
    local context="$1"
    cat <<EOF
...existing rules...

ADDITIONALLY, respond with these fields:
- confidence: 0.0-1.0 (0=uncertain, 1=very certain)
- decision_category: which category applies
- signals: array of detected signals
- risk_level: low|medium|high
EOF
}
```

#### **Step 2: Update Judge Invoker**
**File:** `hooks/claude-judge-continuation.sh`

**Changes:**
- Line 151: Add optional flag to `judge_should_continue()` to request v2 output
- Keep existing parsing path (handle v1 gracefully)
- Add v2 parsing if new fields present
- No changes to decision logic (`should_continue` still drives block/approve)

**Code pattern:**
```bash
# Line ~150: Ask for v2 output
EVALUATION_RESULT=$(judge_should_continue "$RECENT_CONTEXT" "$CLAUDE_MODEL" "$CLAUDE_WORK_DIR" "v2")

# Line ~175-180: Parse - handle both v1 and v2
SHOULD_CONTINUE=$(echo "$EVALUATION_RESULT" | jq -r '.should_continue // false')
CONFIDENCE=$(echo "$EVALUATION_RESULT" | jq -r '.confidence // null')  # May not exist
# ... rest unchanged
```

#### **Step 3: Update Persistence**
**File:** `hooks/lib/emit.sh`

**Changes:**
- Already supports `evaluation` field in persist_decision()
- No code changes needed—v2 output automatically persists as-is
- Verify the `PERSIST_EVALUATION_RESULT` includes all v2 fields

**Testing only:** Verify decision JSON includes:
```json
{
  "timestamp": "...",
  "session_id": "...",
  "decision": "block|approve",
  "reason": "...",
  "evaluation": {
    "should_continue": true,
    "reasoning": "...",
    "confidence": 0.92,
    "decision_category": "explicit_continuation",
    "signals": ["explicit_next_steps"],
    "risk_level": "low"
  }
}
```

#### **Step 4: Update CLI**
**File:** `scripts/explain.sh`

**Changes:**
- Extend `--verbose` output to render new v2 fields
- Detect presence of `confidence`, `decision_category`, `signals` fields
- Keep v1 backward compatible (show "early exit, no evaluation" if missing)
- Add optional `--signals` flag to show signal list

**Output example:**
```
Last Decision: CONTINUE (blocked stop)
Timestamp:     2025-12-22T14:32:17Z
Session:       abc123xyz...

Reasoning:
  Clear next steps stated: logout and registration handlers needed

Evaluation Details:
  Confidence:      0.92
  Category:        explicit_continuation
  Risk Level:      low
  Signals Detected:
    - explicit_next_steps
    - incomplete_implementation
```

#### **Step 5: Add Test Scenarios**
**File:** `test/evals/scenarios/` (new files)

**Add ~5 new scenarios:**
- `66-low-confidence-edge-case.json` — intentional ambiguity, should_continue=true but confidence=0.65
- `67-high-risk-continuation.json` — risky but valid continuation, risk_level=high
- `68-multi-signal-decision.json` — multiple signals detected, verify signals array
- `69-uncertain-category.json` — edge case between categories, decision_category=uncertain
- `70-confidence-distribution.json` — mix of confidence levels across decision types

**Scenario structure (unchanged):**
```json
{
  "name": "Low confidence edge case",
  "description": "Ambiguous transcript with confidence <0.8",
  "expected_decision": true,
  "expected_v2_fields": {
    "confidence_range": [0.5, 0.8],
    "decision_category": "incomplete_work",
    "risk_level": "medium"
  },
  "transcript": [...]
}
```

#### **Step 6: Update Test Harness**
**File:** `test/evals/run-evals.sh`

**Changes:**
- Parse `expected_v2_fields` from scenario JSON (if present)
- After each run, validate v2 fields match expected ranges
- Log confidence values + categories for regression tracking
- Maintain v1 backward compatibility (scenarios without `expected_v2_fields` pass if decision is correct)

---

## 3. Backward Compatibility Strategy

### Approach: **Single-Version Shipping** (Simplest)

**Why:** Cleaner than maintaining two code paths; v2 adds fields that degrade gracefully.

### Strategy

**In Production:**
1. Ship v2 schema + new prompt to Claude
2. v2 output is persisted to `last_decision.json`
3. Hook continues to emit `{"decision": "block"|"approve", "reason": "..."}` (unchanged)
4. Old `explain.sh` output still works (just skips unknown fields)

**Graceful Degradation:**
- If Claude doesn't return v2 fields → they're `null` in parsed JSON
- `jq -r '.confidence // null'` safely returns `null` if missing
- `explain.sh --verbose` detects and skips missing fields

**Migration Path:**
- Phase 2 ships v2; old decision records have no `evaluation` field
- Phase 2+ tools (explain.sh, future analytics) handle both
- No breaking changes

### Implementation Safeguards

```bash
# In judge.sh: Check if v2 parsing is safe
if echo "$EVALUATION_RESULT" | jq -e '.confidence' > /dev/null 2>&1; then
    HAS_V2_FIELDS=true
else
    HAS_V2_FIELDS=false
fi

# In explain.sh: Only render fields that exist
if [[ "$VERBOSE" == "true" ]] && [[ $(echo "$DECISION_JSON" | jq 'has("evaluation")') == "true" ]]; then
    CONFIDENCE=$(echo "$DECISION_JSON" | jq -r '.evaluation.confidence // "N/A"')
    [[ "$CONFIDENCE" != "null" ]] && echo "  Confidence: $CONFIDENCE"
fi
```

---

## 4. Test Scenarios for v2 Fields

### Existing Scenarios (65 files)
- Run as-is; no changes needed
- Still validate `expected_decision` (true = continue, false = stop)
- No v2 field expectations yet

### New Scenarios (5 files to add)

#### **66: Low Confidence Edge Case**
```json
{
  "name": "Low confidence edge case",
  "description": "Assistant mentions next steps but with ambiguous phrasing ('might', 'could'). Decision: continue, but low confidence.",
  "expected_decision": true,
  "expected_v2_fields": {
    "confidence_min": 0.55,
    "confidence_max": 0.75,
    "decision_category_any": ["explicit_continuation", "incomplete_work"],
    "risk_level_any": ["low", "medium"]
  },
  "transcript": [
    { "role": "user", "content": "Create a REST API" },
    { "role": "assistant", "content": "I'll create an API. Maybe I'll add authentication, could also add caching..." }
  ]
}
```

#### **67: High Risk Continuation**
```json
{
  "name": "High risk but valid continuation",
  "description": "Assistant explicitly states next step, but it's a risky refactor. Decision: continue, but flag risk.",
  "expected_decision": true,
  "expected_v2_fields": {
    "decision_category": "explicit_continuation",
    "risk_level": "high",
    "confidence_min": 0.75
  },
  "transcript": [
    { "role": "user", "content": "Build authentication system" },
    { "role": "assistant", "content": "Created JWT logic. Now I'll refactor to support OAuth providers..." }
  ]
}
```

#### **68: Multi-Signal Decision**
```json
{
  "name": "Multiple signals detected",
  "description": "Transcript shows both explicit next steps AND incomplete implementation. Decision: continue.",
  "expected_decision": true,
  "expected_v2_fields": {
    "decision_category": "explicit_continuation",
    "signals_include": ["explicit_next_steps", "incomplete_implementation"],
    "signals_length_min": 2
  },
  "transcript": [
    { "role": "user", "content": "Build user service with CRUD + auth" },
    { "role": "assistant", "content": "Created user model. Now I need to add auth middleware. Also tests are missing." }
  ]
}
```

#### **69: Uncertain Category**
```json
{
  "name": "Uncertain decision boundary",
  "description": "Edge case: could be task completion OR waiting for user. Decision: stop, but acknowledge uncertainty.",
  "expected_decision": false,
  "expected_v2_fields": {
    "decision_category_any": ["waiting_for_user", "uncertain"],
    "confidence_max": 0.80,
    "risk_level": "high"
  },
  "transcript": [
    { "role": "user", "content": "Refactor module X" },
    { "role": "assistant", "content": "Created new module structure. Should I also update all imports?" }
  ]
}
```

#### **70: Confidence Distribution Across Categories**
```json
{
  "name": "Confidence varies by category",
  "description": "Verify confidence is high for explicit signals, lower for uncertain ones.",
  "expected_decision": true,
  "expected_v2_fields": {
    "decision_category": "explicit_continuation",
    "confidence_min": 0.85,
    "signals_include": ["explicit_next_steps"],
    "risk_level": "low"
  },
  "transcript": [
    { "role": "user", "content": "Implement payment processing" },
    { "role": "assistant", "content": "Created Stripe integration. Next I need to add webhook handlers." }
  ]
}
```

### Test Harness Updates

**Validation Logic (in `run-evals.sh`):**

```bash
validate_v2_fields() {
    local result="$1"
    local expected="$2"

    # If expected_v2_fields exists, validate them
    if [[ -n "$expected" ]]; then
        local confidence=$(echo "$result" | jq '.confidence // empty')
        local category=$(echo "$result" | jq -r '.decision_category // empty')
        local signals=$(echo "$result" | jq '.signals // empty')
        local risk=$(echo "$result" | jq -r '.risk_level // empty')

        # Check confidence range (if specified)
        if echo "$expected" | jq -e '.confidence_min' > /dev/null; then
            local min=$(echo "$expected" | jq '.confidence_min')
            [[ $(echo "$confidence >= $min" | bc) -eq 0 ]] && return 1
        fi

        # Check category (exact or any-of list)
        if echo "$expected" | jq -e '.decision_category' > /dev/null; then
            local expected_cat=$(echo "$expected" | jq -r '.decision_category')
            [[ "$category" != "$expected_cat" ]] && return 1
        fi

        # ... more checks for signals, risk_level
    fi
    return 0
}
```

---

## 5. Risk & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Claude doesn't return new fields | Parsing fails silently | Default to v1; store raw if invalid |
| v2 fields bloat decision records | Storage grows | Pre-decide: only persist if valid JSON |
| Breaking tool ecosystem | Scripts fail on missing fields | Defensive field access (jq `// null`) |
| Test scenarios are flaky | False failures due to LLM variance | Use ranges (confidence_min/max) not exact values |

---

## 6. Proving Command

```bash
# Run full test suite with v2 validation
./test/evals/run-evals.sh

# Test snapshot (ensure v2 schema matches prompts)
./test/test-snapshot.sh

# View a v2 decision with new fields
./scripts/explain.sh --verbose --json
```

**Expected outcome:**
- All 70 scenarios pass 5/5 runs
- Snapshot test validates schema consistency
- `explain.sh --verbose` renders confidence, category, signals, risk_level (or "N/A" if early exit)

---

## 7. Files Checklist (for Phase 2)

```
[ ] hooks/lib/judge.sh
    - Expand JUDGE_JSON_SCHEMA to v2
    - Update JUDGE_SYSTEM_PROMPT
    - Add build_v2_evaluation_prompt() (optional, for clarity)

[ ] hooks/claude-judge-continuation.sh
    - Optional: add v2 request flag to judge_should_continue()
    - Parsing already handles additional fields safely

[ ] hooks/lib/emit.sh
    - Verify PERSIST_EVALUATION_RESULT includes all v2 fields
    - No code changes (already handles evaluation field)

[ ] scripts/explain.sh
    - Extend --verbose to render new v2 fields
    - Add --signals flag (nice-to-have)

[ ] test/evals/scenarios/
    - Add 5 new scenarios (66-70)
    - Existing 65 scenarios run unchanged

[ ] test/evals/run-evals.sh
    - Add expected_v2_fields validation logic
    - Log confidence + category for regression tracking

[ ] README.md
    - Document v2 fields in "Technical Details" section
    - Mention new explain.sh fields

[ ] CHANGELOG.md
    - Add Phase 2 v1.2.0 entry with v2 schema notes
```

---

## 8. Implementation Order

1. **Test infrastructure first** → Add v2 validation to harness, add new scenarios
2. **Judge schema** → Expand JSON schema in judge.sh
3. **Judge prompt** → Update system prompt to explain new fields
4. **Hook parsing** → Verify it handles v2 gracefully
5. **CLI rendering** → Add explain.sh v2 output
6. **Verify** → Run full test suite; all 70 scenarios pass
7. **Document** → README + CHANGELOG

**Why this order:** Tests fail fast if schema/prompt are wrong; parsing is already flexible.

---

## 9. Acceptance Criteria (Phase 2)

- ✅ Evaluator returns valid JSON matching v2 schema
- ✅ v2 fields are optional (existing v1 logic unchanged)
- ✅ Hook behavior unchanged: still emits `approve` or `block`
- ✅ All 65 existing scenarios pass 5/5 runs
- ✅ All 5 new v2 scenarios pass 5/5 runs
- ✅ Persistence: `last_decision.json` includes full v2 output
- ✅ `explain.sh --verbose` renders v2 fields when present
- ✅ `explain.sh` still works for v1-only decisions (early exits)
- ✅ Snapshot test validates schema consistency

**Proving command:** `./test/evals/run-evals.sh` → all pass

