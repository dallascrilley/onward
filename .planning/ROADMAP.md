# Roadmap: Redbull v2.0

## Overview

Transform redbull from a simple binary judge into a multi-tiered decision engine that skips 50%+ of expensive LLM calls while improving accuracy and user alignment. The journey progresses from quick-win prefiltering through structured output foundations, pattern-based heuristics, user-defined criteria, and finally intelligent stall detection.

## Domain Expertise

None (bash scripting, internal tooling)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Permission Prefilter** - Skip judge for permission-seeking language
- [ ] **Phase 2: Structured Output** - v2 schema with confidence and signals
- [ ] **Phase 3: Signal Heuristics** - Pattern-based decisions for obvious cases
- [ ] **Phase 4: Definition of Done** - User-defined completion criteria
- [ ] **Phase 5: Stall Detection** - Context hashing and loop prevention

## Phase Details

### Phase 1: Permission Prefilter
**Goal**: Reduce judge calls by 5-15% by detecting permission-seeking language patterns
**Depends on**: Nothing (first phase, independent)
**Research**: Unlikely (bash regex patterns, internal work)
**Plans**: TBD

Key deliverables:
- Regex patterns for "Should I continue?", "Want me to...?", "Would you like me to...?"
- Early-exit logic before Claude judge invocation
- 5-10 new test scenarios

### Phase 2: Structured Output
**Goal**: Extend judge output with confidence, decision_category, signals, risk_level
**Depends on**: Nothing (can run parallel to Phase 1)
**Research**: Unlikely (existing `claude --json-schema` patterns)
**Plans**: TBD

Key deliverables:
- v2 JSON schema definition
- Backward compatibility with v1 consumers
- explain.sh updates for v2 field rendering
- 5 new test scenarios

### Phase 3: Signal Heuristics
**Goal**: Reduce judge calls by 40-60% through pattern-based pre-evaluation
**Depends on**: Phase 2 (uses structured output format)
**Research**: Unlikely (bash pattern matching, internal heuristics)
**Plans**: TBD

Key deliverables:
- 12+ regex patterns for stop/continue signals
- Pattern confidence scoring
- Fallback to judge for ambiguous cases
- 10 new test scenarios

### Phase 4: Definition of Done
**Goal**: Let users define project-specific completion criteria
**Depends on**: Phase 2 (uses structured output for advisory feedback)
**Research**: Unlikely (standard YAML config pattern)
**Plans**: TBD

Key deliverables:
- `.claude/redbull.local.md` config format (YAML frontmatter)
- Advisory mode (default): inform judge of criteria
- Strict mode: hard-fail if criteria unmet
- 10 new test scenarios

### Phase 5: Stall Detection
**Goal**: Detect and prevent infinite loops through context fingerprinting
**Depends on**: Phase 2, Phase 3 (needs structured output and heuristics baseline)
**Research**: Unlikely (bash hashing algorithms, internal work)
**Plans**: TBD

Key deliverables:
- Context hash fingerprinting
- Confidence trend analysis
- Risk scoring (0-100)
- Loop prevention with configurable thresholds
- 5 new test scenarios

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5
(Note: Phase 1 and 2 can run in parallel if desired)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Permission Prefilter | TBD | Not started | - |
| 2. Structured Output | TBD | Not started | - |
| 3. Signal Heuristics | TBD | Not started | - |
| 4. Definition of Done | TBD | Not started | - |
| 5. Stall Detection | TBD | Not started | - |
