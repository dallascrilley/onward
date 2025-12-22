# Redbull v2.0: Comprehensive Improvement Cycle

## Current State (Updated: 2025-12-22)

**Shipped:** v1.1.5 (2025-12-22)
**Status:** Production — installed in Claude Code plugin marketplace
**Users:** Personal use (Dallas Crilley's development workflow)
**Feedback:** Judge accuracy is good but calls are expensive; throttling works but could be smarter

**Codebase:**
- ~800 lines of bash scripts
- Hook-based architecture (`hooks/claude-judge-continuation.sh`)
- 65 evaluation scenarios (5 runs each = 325 total tests)
- Claude Haiku for judgment calls via `claude --print --model haiku`

**Known Issues:**
- 100% of stop events call the judge (expensive)
- Binary decision output lacks debugging context
- No user-defined completion criteria
- Throttling is time-based only, not progress-aware

## v2.0 Goals

**Vision:** Transform redbull from a simple binary judge into a multi-tiered decision engine that skips 50%+ of expensive LLM calls while improving accuracy and user alignment.

**Motivation:**
- Cost reduction: Every judge call = Claude API usage
- Speed: Skip obvious decisions = faster UX
- Quality: Structured output = better debugging + downstream features
- Alignment: User-defined "Definition of Done" = stop when work is ACTUALLY complete

**Scope (v2.0):**

### Phase 1: Permission Language Prefilter
- Skip judge for "Should I continue?", "Want me to...?" patterns
- ~5-15% judge call reduction
- 5-10 new test scenarios

### Phase 2: Structured Judge Output (v2 Schema)
- Add confidence, decision_category, signals, risk_level to output
- Foundation for Phases 3-5
- Backward compatible with v1
- 5 new test scenarios

### Phase 3: Signal Heuristics
- Pattern-based decision making for obvious cases
- ~40-60% judge call reduction (biggest win)
- 12+ regex patterns for stop/continue signals
- 10 new test scenarios

### Phase 4: Definition of Done
- User-defined completion criteria in `.claude/redbull.local.md`
- Advisory mode (default) and Strict mode
- 10 new test scenarios

### Phase 5: Stall Detection
- Context hash fingerprinting
- Confidence trend analysis
- Risk scoring (0-100)
- Loop prevention
- 5 new test scenarios

**Success Criteria:**
- [ ] 50%+ reduction in judge calls (measured in Phase 3)
- [ ] All 100+ scenarios pass 5/5 runs
- [ ] v1 backward compatibility preserved
- [ ] No regressions on existing 65 scenarios
- [ ] explain.sh renders v2 fields correctly

**Not Building (this version):**
- Major architecture rewrites (keep bash hooks)
- TypeScript/Python rewrite
- New CLI tools beyond explain.sh enhancements
- GUI or web interface

## Constraints

- **Language**: Bash only (no TypeScript/Python rewrites)
- **Compatibility**: v1 output format must still work for existing integrations
- **Testing**: Must maintain 5/5 run reliability on all scenarios
- **Incremental**: Each phase must ship independently without breaking previous phases

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Execution order | Phase 1 → 2 → 3 → 4 → 5 | Phase 2 enables 3-5; Phase 1 is independent |
| Prefilter approach | Regex patterns | Fast, deterministic, no API calls |
| DoD format | YAML frontmatter in `.claude/redbull.local.md` | Simple, familiar, project-local |
| Stall detection | Context hash + confidence trend | Catches loops without false positives |

## Open Questions

- [ ] Should Phase 1 ship immediately before Phase 2, or bundle together?
- [ ] Stall detection threshold tuning: 3 identical hashes or 4?
- [ ] Should explain.sh gain a `--json` mode for v2 output?

---

## Original Vision (v1.0 - Archived)

<details>
<summary>Original Vision (v1.0 - Archived)</summary>

## Vision

Prevent Claude from stopping prematurely mid-task by using a separate Claude Haiku instance to judge whether continuation is appropriate.

## Problem

Claude Code sometimes stops when it shouldn't — in the middle of a multi-step task, after saying "next I'll..." without doing the next thing. This breaks flow and requires manual intervention.

## Success Criteria

- [x] Hook intercepts stop events
- [x] Judge evaluates continuation appropriateness
- [x] Throttling prevents infinite loops
- [x] Recursion prevention works
- [x] 65 scenarios pass 5/5 runs

## Scope

### Built
- Stop event hook
- Claude Haiku judge invocation
- Throttling (3 continues per 5 minutes)
- Recursion prevention
- 65 evaluation scenarios

### Not Built
- Prefiltering (all events call judge)
- Structured output (binary only)
- User-defined completion criteria
- Progress-aware throttling

</details>

---
*Initialized: 2025-12-22*
