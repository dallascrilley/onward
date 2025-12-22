# Phase 3 Plan 1: Signal Heuristics Prefilter Summary

**Pattern-based decisions to skip judge for obvious stop/continue cases**

## Performance

- **Duration:** ~9 min
- **Started:** 2025-12-22
- **Completed:** 2025-12-22
- **Tasks:** 5
- **Files modified:** 4

## Accomplishments

- Added `detect_heuristic_signal()` to detect 4 signal types via regex patterns
- Added `heuristic_should_stop()` to map signals to stop/continue decisions
- Added `build_heuristic_evaluation()` to emit v2 metadata for heuristic decisions
- Integrated heuristic check between Phase 1 (permission) and judge in main hook
- Added path logging (`permission | heuristic | judge`) for skip rate measurement
- Created 10 new test scenarios (81-90) for heuristic signal paths
- All 96 scenarios pass 5/5 runs

## Signal Types Implemented (4 of 7)

| Signal | Detection | Decision | Priority |
|--------|-----------|----------|----------|
| `asking_for_clarification` | "can you clarify?", "what should?" (requires ?) | STOP (approve) | 1st |
| `missing_information` | "need credentials", "can't proceed without" (no ? needed) | STOP (approve) | 2nd |
| `explicit_next_steps` | "Next I'll", "Then I will", "Moving on to" | CONTINUE (block) | 3rd |
| `stated_todo_items` | Numbered/bulleted list with "pending", "todo", "need to" | CONTINUE (block) | 4th |

**First match wins** - if multiple signals present, earlier priority takes precedence.

## Signals Deferred to Phase 1 / Judge

| Signal | Why Deferred |
|--------|--------------|
| `asking_for_approval` | Covered by Phase 1 `explicit_choice_required` ("does this look good?") |
| `asking_for_decision` | Covered by Phase 1 `explicit_choice_required` ("which option?") |
| `offering_optional_work` | Covered by Phase 1 `optional_offer` (requires explicit framing) |

## Files Created/Modified

- `hooks/lib/judge.sh` - Added 3 new functions: detect_heuristic_signal(), heuristic_should_stop(), build_heuristic_evaluation()
- `hooks/claude-judge-continuation.sh` - Integrated heuristic check before judge, added path logging
- `test/evals/scenarios/81-90` - 10 new heuristic test scenarios
- `test/evals/scenarios/77-78` - Modified to avoid heuristic triggers (v2 field testing requires judge)

## Three-Tier Architecture

```
Transcript
    ↓
1. IGNORE PATTERNS (Phase 0)
    └─ Match .redbull/ignore.txt → approve stop
    ↓
2. PERMISSION LANGUAGE (Phase 1)
    └─ "Should I continue?" → block (continue)
    └─ "Which option?" → approve (stop)
    ↓
3. HEURISTIC PREFILTER (Phase 3) ← NEW
    └─ asking_for_clarification → approve (stop)
    └─ missing_information → approve (stop)
    └─ explicit_next_steps → block (continue)
    └─ stated_todo_items → block (continue)
    ↓
4. JUDGE (fallback)
    └─ Ambiguous cases → full Claude evaluation
```

## v2 Metadata Emission

Heuristic decisions now emit v2-compatible JSON:
```json
{
  "should_continue": false,
  "reasoning": "Heuristic detected signal 'asking_for_clarification' - approve without judge",
  "decision_category": "waiting_for_user",
  "signals": ["asking_for_clarification"],
  "risk_level": "low",
  "reasons": ["heuristic:asking_for_clarification"]
}
```

## Backward Compatibility

- Judge-only scenarios continue to work (fall through to judge)
- v2 field tests modified to avoid heuristic triggers
- Permission language prefilter (Phase 1) runs first, heuristics second

## Deviations from Plan

- Tightened `missing_information` pattern to avoid false positives on "need validation", "password strength"
- Modified scenarios 77-78 to use phrasing that falls through to judge (required for v2 field testing)

## Issues Encountered

- Initial false positive on "Now I need to add... password strength checks" → fixed with proximity limit `.{0,15}`
- v2 scenarios triggered heuristics instead of judge → modified phrasing to preserve test intent

## Next Phase Readiness

- Phase 3 complete, heuristic prefilter operational
- Ready for Phase 4 (Definition of Done) which uses DoD rules for advisory feedback
- Ready for Phase 5 (Stall Detection) which uses context hashing

---
*Phase: 03-signal-heuristics*
*Completed: 2025-12-22*
