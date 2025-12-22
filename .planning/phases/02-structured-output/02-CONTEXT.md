# Phase 2: Structured Output - Context

## Vision

Upgrade the judge output from a binary decision to a rich v2 schema with confidence scores, decision categories, detected signals, and risk levels—enabling future phases (heuristics, DoD, stall detection) without changing core hook behavior.

## Boundaries

**In Scope:**
- Extend `JUDGE_JSON_SCHEMA` with v2 fields (confidence, decision_category, signals, risk_level)
- Update system prompt to instruct Claude to return v2 fields
- Extend `explain.sh --verbose` to render v2 fields when present
- Add 5 test scenarios for v2 field validation
- Maintain backward compatibility (v1 fields remain required)

**Out of Scope:**
- Decision logic changes (`should_continue` still drives block/approve)
- Prefilters or skip-judge logic (that's Phase 1/3)
- DoD enforcement or stall detection (Phase 4/5)

## Design Reference

See `docs/plans/design/2025-12-22-phase2-design.md` for:
- Full v2 JSON schema definition
- Implementation map with code patterns
- Backward compatibility strategy
- Test scenarios with expected v2 fields

## Key Files

- `hooks/lib/judge.sh` - Schema + prompt definitions
- `hooks/claude-judge-continuation.sh` - Judge invocation
- `scripts/explain.sh` - CLI decision display
- `test/evals/run-evals.sh` - Test harness
- `test/evals/scenarios/` - Test scenario files
