# Project State

## Project Summary

**Building:** Multi-tiered decision engine to reduce expensive LLM judge calls by 50%+ while improving accuracy and user alignment

**Core requirements:**
- 50%+ reduction in judge calls (measured in Phase 3)
- All 100+ scenarios pass 5/5 runs
- v1 backward compatibility preserved
- No regressions on existing 65 scenarios
- explain.sh renders v2 fields correctly

**Constraints:**
- Bash only (no TypeScript/Python rewrites)
- Each phase ships independently without breaking previous phases
- Must maintain 5/5 run reliability on all scenarios

## Current Position

Phase: 4 of 5 (Definition of Done)
Plan: 1 of 1 complete
Status: Phase complete
Last activity: 2025-12-22 - Completed 04-01 (DoD with strict/advisory modes)

Progress: ████████░░ 80%

## Performance Metrics

**Velocity:**
- Total plans completed: 4
- Average duration: 8 min
- Total execution time: 0.52 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 1 | 4 min | 4 min |
| 2 | 1 | 8 min | 8 min |
| 3 | 1 | 9 min | 9 min |
| 4 | 1 | 10 min | 10 min |

**Recent Trend:**
- Last 5 plans: 4m, 8m, 9m, 10m
- Trend: Stable execution

*Updated after each plan completion*

## Accumulated Context

### Decisions Made

| Phase | Decision | Rationale |
|-------|----------|-----------|
| 0 | Execution order 1→2→3→4→5 | Phase 2 enables 3-5; Phase 1 is independent |
| 0 | Prefilter uses regex | Fast, deterministic, no API calls |
| 0 | DoD format: YAML frontmatter | Simple, familiar, project-local |
| 0 | Stall detection: hash + trend | Catches loops without false positives |
| 1 | Require question mark in patterns | High precision - prevents false positives on statements |
| 1 | Optional framing required for "want me to" | Conservative - ambiguous offers fall to judge |
| 2 | v2 fields optional in schema | Backward compatibility - v1 consumers unaffected |
| 2 | Confidence calibration in prompt | 0.9-1.0 very clear, 0.7-0.9 strong, 0.5-0.7 uncertain |
| 2 | 12 signal types defined | Comprehensive coverage for Phase 3 heuristics |
| 3 | Selective ? requirement | Required for asking_for_* signals, not for missing_information |
| 3 | 4 heuristic signals implemented | asking_for_clarification, missing_information, explicit_next_steps, stated_todo_items |
| 3 | Heuristic emits v2 metadata | Keeps explain.sh consistent; decision_category, signals, risk_level |
| 3 | Three-tier path logging | permission → heuristic → judge for skip rate measurement |
| 4 | YAML frontmatter config format | Simple `.claude/redbull.local.md` with frontmatter for DoD rules |
| 4 | Advisory mode default | Lean toward continuing if DoD unmet, non-blocking |
| 4 | Strict mode requires evidence | Only approve stop if DoD met WITH verification output |
| 4 | DoD injected into judge prompt | `_build_dod_section()` adds mode-specific instructions |

### Deferred Issues

None yet.

### Blockers/Concerns Carried Forward

None yet.

## Project Alignment

Last checked: Project start
Status: ✓ Aligned
Assessment: No work done yet - baseline alignment.
Drift notes: None

## Session Continuity

Last session: 2025-12-22
Stopped at: Phase 3 complete - Signal Heuristics shipped
Resume file: None
