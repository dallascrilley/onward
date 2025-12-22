# Redbull Phase Planning: Complete Documentation Index

**Last Updated:** 2025-12-22
**Total Documentation:** ~4000 lines across 8 design documents + this index
**Status:** All phases (1–5) fully designed and ready for implementation

---

## Reading Guide (Start Here)

### 1️⃣ Executive Overview (5 minutes)
Start here to understand the complete roadmap:
- **File:** `2025-12-22-phase-roadmap.md`
- **Contains:** Phase comparison matrix, interdependencies, timeline (2–4 months), judge call reduction targets
- **Decide:** Quick path (Phases 2–4) or full path (Phases 2–5)?

### 2️⃣ Phase 1: Permission Language (10 minutes)
Foundational prefilter (can ship immediately):
- **File:** `design/2025-12-22-phase1-design.md`
- **Goal:** Skip judge for "Should I continue?" and "Want me to...?" patterns
- **Impact:** ~5–15% judge calls skipped
- **New scenarios:** 5–10
- **Effort:** 2–3 days

### 3️⃣ Phase 2: Structured Judge Output (15 minutes)
Enriched evaluation output (foundation for Phase 3+):
- **Files:**
  - `design/2025-12-22-phase2-design.md` (full spec, v2 schema rationale)
- **Goal:** Add confidence, decision_category, signals, risk_level to judge output
- **Impact:** Enables Phase 3–5; v1 backward compatible
- **New scenarios:** 5
- **Effort:** 1–2 weeks

### 4️⃣ Phase 3: Signal Heuristics (10 minutes)
Pattern-based decision making (biggest cost reduction):
- **File:** ``esign/2025-12-22-phase3-design.md`
- **Goal:** Skip judge for obvious signals using regex patterns
- **Impact:** ~40–60% judge calls skipped; ~50% cost reduction
- **New scenarios:** 10
- **Depends on:** Phase 2 (v2 signals array)
- **Effort:** 1–2 weeks

### 5️⃣ Phase 4: Definition of Done (10 minutes)
User-aligned completion criteria (quality improvement):
- **File:** `design/2025-12-22-phase4-design.md`
- **Goal:** User-defined completion checklist enforced by judge
- **Impact:** Stop when user considers work done, not when assistant sounds done
- **New scenarios:** 10
- **Depends on:** Phase 2 (v2 schema)
- **Effort:** 1 week
- **Optional:** Features (DoD config, strict mode)

### 6️⃣ Phase 5: Stall Detection (10 minutes)
Intelligent loop prevention (optional, for later):
- **File:** `design/2025-12-22-phase5-design.md`
- **Goal:** Prevent infinite loops via stall risk scoring
- **Impact:** Better throttling, smarter decisions, optional learning loop
- **New scenarios:** 5 (+5 optional for override feedback)
- **Depends on:** Phase 2 (confidence field)
- **Effort:** 1–2 weeks
- **Status:** Optional (can ship without this)

---

## Document Map (All Files)

### Master Planning
| File | Purpose | Length | Read Time |
|------|---------|--------|-----------|
| **INDEX.md** | This file — navigation guide | - | 5 min |
| **2025-12-22-phase-roadmap.md** | Master roadmap + phase comparison | 11 KB | 10 min |

### Phase Design Documents (One per Phase)
| File | Phase | Goal | Length | Read Time |
|------|-------|------|--------|-----------|
| **2025-12-22-phase1-design.md** | 1 | Permission language prefilter | 10 KB | 10 min |
| **2025-12-22-phase2-design.md** | 2 | Structured v2 schema | 16 KB | 15 min |
| **2025-12-22-phase3-design.md** | 3 | Signal heuristics | 10 KB | 10 min |
| **2025-12-22-phase4-design.md** | 4 | Definition of Done | 9.4 KB | 10 min |
| **2025-12-22-phase5-design.md** | 5 | Stall detection | 12 KB | 10 min |

### Phase 2 Supplementary (Deep Dive)
| File | Purpose | Length | Read Time |
|------|---------|--------|-----------|
| **2025-12-22-phase2-design.md** | Full design spec (schema, rationale, fields, backward compat) | 16 KB | 15 min |
| **2025-12-22-phase2-implementation-guide.md** | Line-by-line code changes (copy-paste ready) | 24 KB | 20 min |
| **2025-12-22-phase2-quick-reference.md** | One-pager (during implementation) | 10 KB | 5 min |

### Original Planning
| File | Purpose | Length |
|------|---------|--------|
| **2025-12-22-redbull-improvement-plan.md** | Original Phase 1–5 spec (high-level) | 8.3 KB |

---

## Implementation Paths

### Quick Path (3 months)
```
Week 1–2:   Phase 2 (structured v2 schema)
Week 3–4:   Phase 3 (signal heuristics, 50% cost reduction)
Week 5–6:   Phase 4 (Definition of Done)
```

**Reading order:**
1. `2025-12-22-phase-roadmap.md` (5 min)
2. `2025-12-22-phase2-design.md` (15 min)
3. `2025-12-22-phase2-implementation-guide.md` (20 min during implementation)
4. `2025-12-22-phase3-design.md` (10 min)
5. `2025-12-22-phase4-design.md` (10 min)

### Full Path (4 months)
```
Week 1–2:   Phase 2
Week 3–4:   Phase 3
Week 5–6:   Phase 4
Week 7–8:   Phase 5 (optional stall detection)
```

**Add to Quick Path:**
6. `2025-12-22-phase5-design.md` (10 min)

### Foundation First (Start Now)
```
Before choosing quick vs full:
1. Phase 1 (permission language) — ships immediately
2. Then decide: Phase 2+ or wait?
```

**Reading order:**
1. `2025-12-22-phase-roadmap.md` (5 min)
2. `2025-12-22-phase1-design.md` (10 min)

---

## Key Metrics by Phase

### Judge Call Reduction

| Phase | Before | After | Reduction | Cumulative |
|-------|--------|-------|-----------|-----------|
| Start | 100% | - | - | 100% |
| Phase 1 | 100% | 95% | 5% | 95% |
| Phase 2 | 95% | 95% | 0% | 95% |
| Phase 3 | 95% | ~50% | **50%** | **50%** |
| Phase 4 | 50% | 50% | 0% | 50% |
| Phase 5 | 50% | 50% | 0% | 50% |

**Biggest win:** Phase 3 (heuristics) cuts judge calls in half.

### Test Scenario Growth

| Phase | New Scenarios | Total | Multiplier |
|-------|---|---|---|
| Start | - | 65 | - |
| Phase 1 | 5–10 | 70–75 | 1.08x |
| Phase 2 | 5 | 75–80 | 1.15x |
| Phase 3 | 10 | 85–90 | 1.31x |
| Phase 4 | 10 | 95–100 | 1.46x |
| Phase 5 | 5 (+5) | 100–110 | 1.69x |

Each scenario runs 5× for reliability.

---

## Quick Decision Tree

```
START HERE
    │
    ├─ "I want to understand the complete roadmap"
    │  └─ Read: phase-roadmap.md (5 min)
    │
    ├─ "I'm ready to start Phase 1 (permission language)"
    │  └─ Read: phase1-design.md (10 min)
    │
    ├─ "I'm implementing Phase 2 (v2 schema)"
    │  ├─ First: phase2-design.md (15 min)
    │  ├─ Then: phase2-implementation-guide.md (copy-paste during implementation)
    │  └─ Ref: phase2-quick-reference.md (one-pager)
    │
    ├─ "I'm implementing Phase 3 (heuristics)"
    │  └─ Read: phase3-design.md (10 min)
    │
    ├─ "I'm implementing Phase 4 (DoD)"
    │  └─ Read: phase4-design.md (10 min)
    │
    ├─ "I'm implementing Phase 5 (stall detection)"
    │  └─ Read: phase5-design.md (10 min)
    │
    └─ "Show me everything at once"
       └─ This INDEX.md file (you are here)
```

---

## Document Structure (Each Phase)

Every phase design document contains:

1. **Goal** — What problem does this phase solve?
2. **Current State** — What exists now? What's the gap?
3. **Architecture** — How does it work? Flowchart/diagram.
4. **Implementation** — Line-by-line changes (Phase 2) or pseudocode (Phases 3–5).
5. **Test Scenarios** — New test files to add (5–10 per phase).
6. **Acceptance Criteria** — How to know it's done.
7. **Proving Command** — How to verify it works.
8. **Risk & Mitigations** — What can go wrong? How to prevent it.
9. **Dependencies** — What does this phase depend on? What does it enable?

---

## Implementation Checklist (All Phases)

Use this to track progress across all phases:

### Phase 1
- [ ] Permission language pattern matcher implemented
- [ ] Hook integration added
- [ ] 5–10 test scenarios created
- [ ] All 75 scenarios pass 5/5 runs
- [ ] No regression on existing scenarios

### Phase 2
- [ ] v2 JSON schema created
- [ ] Judge system prompt updated
- [ ] Judge invocation returns v2 fields
- [ ] Hook parsing handles v2 gracefully
- [ ] Persistence stores v2 output
- [ ] explain.sh renders v2 fields
- [ ] 5 new v2 scenarios created
- [ ] All 80 scenarios pass 5/5 runs

### Phase 3
- [ ] Heuristic prefilter implemented
- [ ] Signal detection functions created
- [ ] Hook calls prefilter before judge
- [ ] 10 new heuristic scenarios created
- [ ] All 90 scenarios pass 5/5 runs
- [ ] ~40–60% judge call reduction verified

### Phase 4
- [ ] DoD parsing from config file
- [ ] Judge prompt injection for DoD
- [ ] Hook loads DoD at runtime
- [ ] 10 new DoD scenarios created
- [ ] Advisory mode works (default)
- [ ] Strict mode works (optional)
- [ ] All 100 scenarios pass 5/5 runs

### Phase 5
- [ ] Stall detection algorithm implemented
- [ ] Risk score calculation working
- [ ] Throttle file includes context hash
- [ ] Decision persistence includes stall_risk
- [ ] explain.sh renders stall risk
- [ ] 5 new stall detection scenarios created
- [ ] All 105 scenarios pass 5/5 runs
- [ ] (Optional) Override feedback tracking

---

## File Organization (Repo Structure)

```
redbull/
├── docs/plans/
│   ├── INDEX.md                              ← You are here
│   ├── 2025-12-22-phase-roadmap.md           ← Start: master roadmap
│   ├── 2025-12-22-phase1-design.md           ← Phase 1: permission language
│   ├── 2025-12-22-phase2-design.md           ← Phase 2: v2 schema (full spec)
│   ├── 2025-12-22-phase2-implementation-guide.md  ← Phase 2: line-by-line changes
│   ├── 2025-12-22-phase2-quick-reference.md ← Phase 2: one-pager
│   ├── 2025-12-22-phase3-design.md           ← Phase 3: heuristics
│   ├── 2025-12-22-phase4-design.md           ← Phase 4: DoD
│   ├── 2025-12-22-phase5-design.md           ← Phase 5: stall detection
│   └── 2025-12-22-redbull-improvement-plan.md  ← Original spec
├── hooks/
│   ├── claude-judge-continuation.sh          ← Main hook (modify all phases)
│   └── lib/
│       ├── judge.sh                          ← Judge logic (modify all phases)
│       ├── settings.sh                       ← Config parsing (Phase 4)
│       ├── throttle.sh                       ← Throttling (Phase 5)
│       ├── emit.sh                           ← Persistence (Phase 2, 5)
│       ├── prompt.sh                         ← Prompt building (Phase 4)
│       └── ...
├── scripts/
│   └── explain.sh                            ← CLI tool (modify Phases 2, 4, 5)
├── test/
│   ├── evals/
│   │   ├── run-evals.sh                      ← Test harness (modify Phases 2–5)
│   │   └── scenarios/
│   │       ├── 01-*.json                     ← Original 65 scenarios
│   │       ├── 66-*.json                     ← Phase 2 (5 new)
│   │       ├── 71-*.json                     ← Phase 3 (10 new)
│   │       ├── 81-*.json                     ← Phase 4 (10 new)
│   │       └── 91-*.json                     ← Phase 5 (5 new)
│   └── test-snapshot.sh                      ← Schema consistency test
├── README.md                                 ← Update for each phase
└── CHANGELOG.md                              ← Version entries (1.2.0, 1.3.0, etc.)
```

---

## Key Concepts (Glossary)

**Cross-Phase:**
- **Judge:** Separate Claude Haiku instance evaluating continuation
- **Hook:** Stop event handler in Claude Code
- **Prefilter:** Decision-making logic before calling judge
- **Fallback:** Call judge if prefilter can't decide

**Phase 1:**
- **Permission-seeking:** Assistant asking if it should keep working ("Should I continue?")
- **Needs user choice:** Assistant offering optional work ("Want me to...?")

**Phase 2:**
- **v2 Schema:** Extended judge output {should_continue, reasoning, confidence, decision_category, signals, risk_level}
- **Signal:** Detected communication type (asking_for_approval, explicit_next_steps, etc.)

**Phase 3:**
- **Heuristic:** Pattern-matching rule (regex/keywords)
- **Ambiguous:** Transcript where no clear signal detected → call judge

**Phase 4:**
- **Definition of Done (DoD):** User-defined completion criteria
- **Advisory:** Judge considers DoD but can override
- **Strict:** Judge enforces DoD (refuses to stop until met)

**Phase 5:**
- **Stall:** No progress despite continuations (same context, declining confidence)
- **Stall Risk:** Score (0–100) indicating loop likelihood
- **Context Hash:** SHA256 fingerprint of transcript (detect unchanged context)

---

## Performance Impact Summary

| Phase | Judge Calls | Cost | Speed | Decision Quality |
|-------|---|---|---|---|
| Phase 1 | 95% | -5% | -5% | Slight improvement |
| Phase 2 | 95% | 0% | 0% | Better debugging |
| Phase 3 | 50% | **-50%** | **2x faster** | **Better accuracy** |
| Phase 4 | 50% | 0% | 0% | **Better alignment** |
| Phase 5 | 50% | 0% | 0% | Better loop prevention |

**Phase 3 is the biggest win** (50% cost + speed reduction).

---

## Getting Help

### Questions About a Phase?
- Read the phase design document (e.g., `2025-12-22-phase3-design.md`)
- Check the "Risk & Mitigations" section
- Look at test scenario examples

### Questions About Implementation?
- See `2025-12-22-phase2-implementation-guide.md` (Phase 2 has detailed line-by-line guide)
- Other phases: refer to design documents (pseudocode + explanation)

### Questions About Overall Roadmap?
- Read `2025-12-22-phase-roadmap.md` (master overview)

### Questions About Dependencies?
- Check "Depends On" section in each phase design
- Refer to "Interdependencies" in phase-roadmap.md

---

## Next Steps

1. **Read:** `2025-12-22-phase-roadmap.md` (5 min) to understand the big picture
2. **Decide:** Quick path (Phases 2–4) or full path (Phases 2–5)?
3. **Choose Starting Phase:**
   - Phase 1 (immediate): `2025-12-22-phase1-design.md`
   - Phase 2 (foundation): `2025-12-22-phase2-design.md` + implementation guide
4. **Begin Implementation:**
   - Follow file modification checklist in each design doc
   - Use implementation guide for Phase 2 (copy-paste ready)
   - Run `./test/evals/run-evals.sh` frequently

---

## Summary Statistics

- **Total Documentation:** ~4000 lines
- **Design Documents:** 5 (one per phase)
- **Supplementary Docs:** 3 (Phase 2 deep dive)
- **Estimated Reading Time:** ~90 minutes (all documents)
- **Estimated Implementation Time:** 8–12 weeks (all phases)
- **Test Scenarios:** 65 existing + 35–40 new = 100–105 total
- **Judge Call Reduction:** 100% → 50% (Phase 3 biggest impact)

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-22 | 1.0 | Initial design package (Phases 1–5) |

---

**Last Updated:** 2025-12-22
**Status:** ✅ All phases fully designed and ready for implementation
**Next Action:** Start Phase 1 or Phase 2 implementation

