# Phase 2 Plan 1: Structured v2 Output Schema Summary

**Extended judge output with v2 schema: confidence, decision_category, signals, risk_level**

## Performance

- **Duration:** ~8 min
- **Started:** 2025-12-22
- **Completed:** 2025-12-22
- **Tasks:** 4
- **Files modified:** 7

## Accomplishments

- Extended `JUDGE_JSON_SCHEMA` with v2 fields (confidence 0-1, decision_category enum, signals array, risk_level enum, reasons array)
- Updated `JUDGE_SYSTEM_PROMPT` to instruct Claude about v2 metadata
- Enhanced `build_evaluation_prompt()` with detailed v2 field instructions and calibration guidance
- Updated `explain.sh --verbose` to render v2 fields when present (confidence as %, category, signals list)
- Updated stub claude binary to return v2 fields for testing
- Created 5 new v2 test scenarios (76-80) for edge cases and metadata validation
- All 86 scenarios pass 5/5 runs (80 + 6 validation cases)

## Files Created/Modified

- `hooks/lib/judge.sh` - v2 JSON schema + enhanced evaluation prompt with v2 field instructions
- `scripts/explain.sh` - v2 metadata rendering in verbose mode
- `test/evals/bin/claude` - Stub returns v2 fields (confidence, category, signals, risk, reasons)
- `test/snapshots/prompt-schema.snapshot.json` - Updated snapshot with v2 schema
- `test/evals/scenarios/76-v2-low-confidence-edge.json` - Ambiguous case, low confidence expected
- `test/evals/scenarios/77-v2-high-risk-continuation.json` - Risky refactor continuation
- `test/evals/scenarios/78-v2-multi-signal.json` - Multiple signals detected
- `test/evals/scenarios/79-v2-uncertain-category.json` - Edge case boundary
- `test/evals/scenarios/80-v2-high-confidence.json` - Clear next steps, high confidence

## Schema Changes (v2)

| Field | Type | Description |
|-------|------|-------------|
| `confidence` | number 0-1 | Certainty in decision |
| `decision_category` | enum | Classification (explicit_continuation, task_completion, waiting_for_user, blocker, incomplete_work, uncertain) |
| `signals` | string[] | Detected signal types (12 possible values) |
| `risk_level` | enum | Risk assessment (low, medium, high) |
| `reasons` | string[] | Key factors for decision |

## Backward Compatibility

- v1 required fields unchanged (`should_continue`, `reasoning`)
- v2 fields are optional—missing fields gracefully handled with `// empty`
- explain.sh displays v2 section only if v2 fields present
- Existing 75 scenarios pass unchanged

## Deviations from Plan

None - plan executed as designed.

## Issues Encountered

- Transient test failure on first run (command timing issue), passed on retry

## Next Phase Readiness

- Phase 2 complete, v2 schema operational
- Ready for Phase 3 (Signal Heuristics) which uses v2 signals for pattern-based decisions
- Foundation laid for Phase 4 (DoD) and Phase 5 (Stall Detection)

---
*Phase: 02-structured-output*
*Completed: 2025-12-22*
