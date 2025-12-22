# Phase 3 Heuristics — Patch Plan (Design Alignment)

## Objective
Align Phase 3 implementation with `docs/plans/design/2025-12-22-phase3-design.md` by filling missing heuristic signals and matching the test plan.

## Scope
- Add missing stop-signal detection (approval, decision, optional work).
- Update tests to cover all designed signals and align scenario numbering or document the new numbering.
- Keep existing behavior and backward compatibility intact.

## Plan

### Task 1 — Add missing stop-signal detection
**Why:** Design specifies 5 stop signals; only 2 are implemented.

**Changes**
- Extend `detect_heuristic_signal()` with new patterns, evaluated after `asking_for_clarification` and `missing_information`, before continue signals:
  - `asking_for_approval`
    - Pattern: question-marked approval/validation prompts.
    - Example regex: `"(does this|does that|does it).*(look|work|seem|make sense)\\?"` or `"(ok|okay|sound good|good to go|look good)\\?"`
  - `asking_for_decision`
    - Pattern: explicit choice prompts with “which/choose/prefer/option A or B”.
    - Example regex: `"(which|choose|prefer).*(option|approach)|option.*or"`
  - `offering_optional_work`
    - Pattern: offers additional work or asks permission to proceed.
    - Example regex: `"(want me to|should i also|do you want me to|optional|nice-to-have)"`
- Keep detection conservative:
  - Require a `?` for approval/decision prompts.
  - Do not match “next” or “option” in descriptive sentences without a question.
  - Ensure missing-information and clarification checks remain higher priority.

**Files**
- `hooks/lib/judge.sh`

**Acceptance Criteria**
- All five stop signals are detected in clear cases.
- Ambiguous cases still fall back to judge.
- No regression in existing heuristic edge cases (86–90).

**Proving Command**
```bash
./test/evals/run-evals.sh
```

---

### Task 2 — Align test scenarios with design
**Why:** Design expects a full set of heuristic scenarios; current numbering and coverage diverge.

**Changes**
- Add scenarios for missing stop signals with clear, minimal transcripts:
  - `71-heuristic-asking-approval.json` (or `91-...` if using current numbering)
  - `72-heuristic-asking-decision.json`
  - `73-heuristic-offering-optional-work.json`
- Keep existing 81–90 scenarios; do not delete. If you want strict design alignment, add 71–80 to mirror the design doc.
- Decide on numbering approach:
  - **Option A (preferred):** Add new 71–80 files to match design; keep 81–90 as extended edge coverage.
  - **Option B:** Update the design doc’s scenario list and numbering to match 81–90.

**Files**
- `test/evals/scenarios/71-heuristic-asking-approval.json`
- `test/evals/scenarios/72-heuristic-asking-decision.json`
- `test/evals/scenarios/73-heuristic-offering-optional-work.json`
- `docs/plans/design/2025-12-22-phase3-design.md` (only if adopting Option B)

**Acceptance Criteria**
- All designed signals have scenarios.
- All scenarios pass 5/5 runs.
- Scenario expectations:
  - Stop signals → `expected_decision: false`, `expected_path: "heuristic"`
  - Continue signals → `expected_decision: true`, `expected_path: "heuristic"`
  - Ambiguous/edge cases → `expected_path: "judge"`

**Proving Command**
```bash
./test/evals/run-evals.sh
```

---

### Task 3 — Clarification detection policy (optional)
**Why:** Implementation currently requires a question mark; design does not explicitly require it.

**Changes**
- Choose one:
  - **Keep strict**: require `?` for clarification detection to prevent false positives; update design doc to document the rule.
  - **Relax**: allow “can you clarify/explain” without a `?`; ensure edge tests still pass.

**Files**
- `hooks/lib/judge.sh` and/or `docs/plans/design/2025-12-22-phase3-design.md`

**Acceptance Criteria**
- Clarification detection behavior matches documented intent.
- Edge cases still fall back to judge (e.g., “Let me clarify…” without a question mark if strict).

**Proving Command**
```bash
./test/evals/run-evals.sh
```

## Notes
- Avoid new dependencies or schema changes without approval.
- Keep heuristics conservative: false positives should fall back to judge.
