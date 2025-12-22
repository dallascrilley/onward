# Redbull Continuation Judge: Roadmap (Phases 1–5)

**Date:** 2025-12-22
**Status:** Unified Design Document
**Goal:** Improve the speed, accuracy, and reliability of the Claude continuation judge by introducing linguistic prefilters, structured metadata, user-defined completion criteria, and loop protection.

---

## 1. Executive Summary & Architecture

The system evolves from a simple binary judge to a multi-tiered decision engine. The goal is to skip expensive LLM calls for obvious cases (~50%+ reduction) while ensuring the assistant never stops prematurely when core work remains.

### The Decision Pipeline
```text
Transcript
    ↓
1. IGNORE PATTERNS (Existing) -> .redbull/ignore.txt
    ↓
2. PREFILTER HEURISTICS (Phase 1 & 3) -> Regex matching (Linguistic signals)
    ├─ CONTINUE: "Should I proceed?", "Next I will..."
    └─ STOP: "Which option?", "I need credentials", "Want me to add X (optional)?"
    ↓
3. STALL DETECTION (Phase 5) -> Hash & Trend analysis
    └─ High Risk? Force STOP or increase confidence threshold.
    ↓
4. CONFIG & DoD LOADING (Phase 4) -> Project-specific rules
    └─ Advisory or Strict enforcement levels.
    ↓
5. STRUCTURED JUDGE (Phase 2) -> LLM Evaluation (JSON v2)
    └─ Returns: confidence, signals, category, reasoning.
```

---

## Phase 1 & 3: Heuristic Prefilters
**Goal:** Skip the judge for obvious cases using high-precision regex matching on the last assistant message.

### Stop Signals (Approve Stop / Wait for User)
| Signal Type | Pattern Examples | Logic |
| :--- | :--- | :--- |
| **User Choice** | "Which approach?", "Option A or B?", "Do you prefer...?" | Stop (Needs decision) |
| **Approval** | "Does this look good?", "Is this correct?" | Stop (Needs verification) |
| **Clarification** | "Can you explain...?", "What should I...?" | Stop (Needs info) |
| **Optional Work** | "I can also (optional)...", "Want me to add X?" | Stop (Optional offer) |
| **Blockers** | "I need the API key", "Where is the password?" | Stop (Missing info) |

### Continue Signals (Block Stop / Resume Work)
| Signal Type | Pattern Examples | Logic |
| :--- | :--- | :--- |
| **Permission Seeking**| "Should I continue?", "Shall I proceed?" | Continue (Obvious 'yes') |
| **Next Steps** | "Next I will...", "Now I'm going to..." | Continue (Stated intent) |
| **Pending Tasks** | "TODO:", "1. [x] 2. [ ]" | Continue (Unfinished list) |

---

## Phase 2: Structured Judge Output (JSON v2)
**Goal:** Upgrade the judge from a binary `true/false` to a data-rich response for better diagnostics and downstream logic.

### v2 JSON Schema
```json
{
  "should_continue": "boolean",
  "reasoning": "string",
  "confidence": "number (0-1)",
  "decision_category": "enum (task_completion|incomplete_work|waiting_for_user|...)",
  "signals": ["array of detected signals"],
  "risk_level": "low|medium|high",
  "next_action": "string (optional)"
}
```
*   **Backward Compatibility:** v1 fields (`should_continue`, `reasoning`) remain required.
*   **CLI Support:** `explain.sh --verbose` is updated to render these fields.

---

## Phase 4: Definition of Done (DoD)
**Goal:** Align stop decisions with project-specific completion criteria defined by the user in `.claude/redbull.local.md`.

### Configuration Format
```yaml
---
dod_enforcement: strict             # advisory | strict
definition_of_done:
  - "All tests pass (npm test)"
  - "No TODO comments remain in the code"
  - "README.md updated"
---
```

### Enforcement Levels
*   **Advisory (Default):** The judge considers the DoD as a guideline.
*   **Strict:** The judge is instructed to **refuse** a stop unless the assistant provides evidence that DoD criteria are met or an unresolvable blocker exists.

---

## Phase 5: Stall Detection
**Goal:** Prevent "infinite continue loops" where the assistant stays active without making meaningful progress.

### Detection Signals
1.  **Context Hash:** SHA256 fingerprint of normalized assistant messages. If the hash is identical across 3 turns, progress has stalled.
2.  **Confidence Trend:** If the judge's `confidence` score is steadily declining turn-over-turn.
3.  **Category Repetition:** Same reason (e.g., `incomplete_work`) repeated 4+ times.

### Stall Risk Scoring (0–100)
*   **Low Risk (0-40):** Proceed normally.
*   **Moderate Risk (40-70):** Increase the judge's confidence threshold (e.g., require `>0.8` to continue).
*   **High Risk (>70):** Force a stop and notify the user via `explain.sh` that the task may need reframing.

---

## Implementation Roadmap

| Phase | Description | Key Deliverable | Impact |
| :--- | :--- | :--- | :--- |
| **1** | Permission Prefilter | `detect_permission_language()` | ~10% Judge Skip |
| **2** | v2 JSON Schema | Structured Metadata in `last_decision.json` | Diagnostics |
| **3** | Signal Heuristics | 12+ Regex patterns for stop/continue | ~50% Judge Skip |
| **4** | Definition of Done | Config-driven prompts in `judge.sh` | Quality / Accuracy |
| **5** | Stall Detection | Context hashing & Risk scoring | Loop Prevention |

### Testing Strategy
*   **Scenario Library:** Expand from 65 to 100+ scenarios.
*   **Regression:** All previous phases must pass 5/5 runs before a new phase is merged.
*   **Proving Command:** `./test/evals/run-evals.sh`

### Files Impacted
*   `hooks/lib/judge.sh`: Core matching and prompt logic.
*   `hooks/lib/settings.sh`: DoD and config parsing.
*   `hooks/lib/throttle.sh`: Stall detection and hashing.
*   `hooks/claude-judge-continuation.sh`: Pipeline orchestration.
*   `scripts/explain.sh`: Rich data visualization for users.