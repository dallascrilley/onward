# Redbull Phase Roadmap (2025-12-22)

**Complete Implementation Path for Phases 1–5**

---

## Executive Summary

Five-phase roadmap to evolve Redbull from basic continuation control to sophisticated task-aware work orchestration.

```
Phase 1 ──→ Phase 2 ──→ Phase 3 ──→ Phase 4 ──→ Phase 5
(Done)      (Ready)     (Ready)     (Ready)     (Optional)
   ✓          📋          📋          📋           📋
```

---

## Phase Comparison Matrix

| Phase | Goal | Key Files | Judge Calls | User Config | Test Scenarios |
|-------|------|-----------|-------------|-------------|---|
| **1** | ✓ Permission language prefilter | `judge.sh` prompt | Skip obvious | None | +5 (now 70) |
| **2** | Structured v2 schema | schema expansion | Still ~100% | None | +5 (now 75) |
| **3** | Signal heuristics | prefilter function | Skip 40–60% | None | +10 (now 85) |
| **4** | Definition of Done | config parsing | Same | Optional | +10 (now 95) |
| **5** | Stall detection | risk scoring | Same | Optional | +5 (now 100) |

---

## Phase Details at a Glance

### Phase 1: Permission Language Prefilter ✓
**Status:** SHIPPED
**Date:** 2025-12-22
**Impact:** Skip judge for obvious permission-seeking language

**Key idea:**
```
"Should I continue?" → BLOCK (obviously unfinished work)
"Want me to also add caching?" → APPROVE (wait for user decision)
```

**Files:** `judge.sh` (prompt only), test scenarios
**Judge calls:** Skip maybe 5–10% of obvious cases

---

### Phase 2: Structured Judge Output (v2 Schema)
**Status:** READY FOR IMPLEMENTATION
**Design Docs:** `2025-12-22-phase2-design.md`, `2025-12-22-phase2-implementation-guide.md`
**Impact:** Enriched judge output + better debugging

**Key idea:**
```json
{
  "should_continue": true,
  "reasoning": "...",
  "confidence": 0.92,              // NEW
  "decision_category": "explicit_continuation",  // NEW
  "signals": ["explicit_next_steps"],  // NEW
  "risk_level": "low"              // NEW
}
```

**Files:** schema expansion, CLI rendering, test scenarios
**Judge calls:** Same as Phase 1 (~95% still call judge)
**Benefits:**
- Automation-ready output (v2 fields enable Phase 3+)
- Better debugging (confidence + category visible)
- Backward compatible (v1 still works)

---

### Phase 3: Signal Heuristics
**Status:** READY FOR IMPLEMENTATION
**Design Doc:** `2025-12-22-phase3-design.md`
**Impact:** Skip judge for obvious signals

**Key idea:**
```
"Does this look good?" → APPROVE (detect via regex)
"Next I'll create logout" → BLOCK (detect via regex)
```

**Files:** prefilter functions, heuristic detection
**Judge calls:** Skip 40–60% (obvious cases need no evaluation)
**Before:**
```
Every transcript → Judge (100% calls)
```

**After:**
```
Transcript → Heuristic check → If matched, decide → Else judge
             ├─ Stop signal detected? → APPROVE
             ├─ Continue signal detected? → BLOCK
             └─ Ambiguous → Call judge
```

**Benefits:**
- ~50% faster decisions for obvious cases
- Reduced cost (Haiku calls for 40% fewer transcripts)
- More predictable behavior

---

### Phase 4: Definition of Done (DoD)
**Status:** READY FOR IMPLEMENTATION
**Design Doc:** `2025-12-22-phase4-design.md`
**Impact:** User-aligned completion criteria

**Key idea:**
```yaml
# .claude/redbull.local.md
definition_of_done:
  - "npm test shows 0 failures"
  - "No TODO comments"
  - "CHANGELOG.md updated"
```

Judge sees DoD context and refuses to stop until criteria are met (in strict mode).

**Files:** config parsing, prompt injection, test scenarios
**Judge calls:** Same (~50% via heuristics + 50% via judge)
**User impact:**
- Default: advisory (inform judge, judge decides)
- Strict: enforce (judge refuses stop until DoD met)

**Benefits:**
- Aligns assistant stops with user intent
- "Done" means user's definition, not assistant's tone
- Prevents premature stopping

---

### Phase 5: Stall Detection
**Status:** READY FOR IMPLEMENTATION (OPTIONAL)
**Design Doc:** `2025-12-22-phase5-design.md`
**Impact:** Prevent infinite loops, learn from user corrections

**Key idea:**
```
Decision 1: context_hash = abc123, confidence = 0.90 → continue
Decision 2: context_hash = abc123, confidence = 0.75 → continue
Decision 3: context_hash = abc123, confidence = 0.62 → stall detected!

Risk Score: 95/100 → Force stop
```

**Files:** stall detection algorithm, risk scoring, override tracking
**User impact:**
- High stall risk → more conservative decisions
- Prevents "continue loop" experience
- Surfaces pattern: "work isn't progressing"

**Benefits:**
- Detects real infinite loops (same work, declining confidence)
- Learning loop (override feedback → adjust)
- Better throttling (smarter than blind count-based)

---

## Implementation Sequence Recommendation

### Quick Path (2–3 months)
```
Week 1–2:  Phase 2 (v2 schema + test infrastructure)
Week 3–4:  Phase 3 (heuristic prefilter)
Week 5–6:  Phase 4 (Definition of Done)
```

### With Phase 5 (3–4 months)
```
+ Week 7–8: Phase 5 (Stall detection + learning)
```

---

## Interdependencies

```
Phase 2 (v2 schema)
    ↓
    ├─→ Phase 3 (signals array enables heuristic detection)
    │       ↓
    │       └─→ Phase 4 (DoD uses signals + confidence)
    │               ↓
    │               └─→ Phase 5 (stall detection uses confidence + history)
```

**Can skip:** Phases can be skipped independently without breaking earlier phases:
- Phase 1 ✓ (shipped)
- Phase 2 ✓ (enrichment; graceful degradation if fields missing)
- Phase 3 ✓ (heuristics are optional; judge is fallback)
- Phase 4 ✓ (DoD is advisory; defaults to no DoD behavior)
- Phase 5 ✓ (stall detection is informational; doesn't block decisions)

---

## Test Scenario Growth

```
Phase 1:  65 scenarios (base)
Phase 2:  +5 scenarios → 70 total (v2 fields)
Phase 3:  +10 scenarios → 80 total (heuristic signals)
Phase 4:  +10 scenarios → 90 total (DoD enforcement)
Phase 5:  +5 scenarios → 95 total (stall detection)
         (+5 override feedback → 100 total, optional)
```

Each scenario runs 5× for reliability validation.

---

## Judge Call Reduction

| Phase | Judge Calls | Notes |
|-------|---|---|
| Before Phase 1 | 100% | Every transcript calls judge |
| After Phase 1 | ~95% | Permission language skips ~5% |
| After Phase 2 | ~95% | Same (v2 is enrichment, not logic change) |
| After Phase 3 | ~50% | Heuristics skip obvious cases (40–60%) |
| After Phase 4 | ~50% | Same (DoD is prompt injection, not new calls) |
| After Phase 5 | ~50% | Same (stall risk is decision input, not call change) |

**Cost impact:**
- Phase 1: ~5% cost reduction
- Phase 3: ~50% cost reduction (biggest gain)
- Phase 4–5: Decision quality improvement (no additional cost)

---

## User-Facing Features by Phase

| Feature | Phase | User Config | Default |
|---------|-------|---|---|
| Skip permission language | 1 | None | Always on |
| View confidence + signals | 2 | None | `explain.sh --verbose` |
| Heuristic decisions visible | 3 | None | Debug logs show "heuristic vs judge" |
| Definition of Done | 4 | Optional `.claude/redbull.local.md` | Advisory (no enforcement) |
| Stall risk warnings | 5 | Optional | Shows in `explain.sh --verbose` |

---

## Success Metrics

### Phase 1–2
- ✅ All test scenarios pass
- ✅ Backward compatible

### Phase 3
- ✅ All test scenarios pass
- ✅ Judge call reduction: 40–60%
- ✅ Heuristic accuracy: >95% precision

### Phase 4
- ✅ All test scenarios pass
- ✅ DoD parsed correctly from config
- ✅ Strict mode enforces DoD

### Phase 5
- ✅ All test scenarios pass
- ✅ Stall risk accuracy: correlates with actual loops
- ✅ High risk (>70) prevents infinite loops

---

## File Changes Summary (All Phases)

### Code Changes
```
hooks/lib/judge.sh              ✏️  (schema, prompt, heuristics, stall detection)
hooks/lib/settings.sh           ✏️  (DoD parsing)
hooks/lib/throttle.sh           ✏️  (context hashing for stall)
hooks/lib/emit.sh               ✏️  (stall risk persistence)
hooks/claude-judge-continuation.sh  ✏️  (heuristic check, stall calc)
scripts/explain.sh              ✏️  (v2 field rendering, stall display)
```

### Configuration
```
.claude/redbull.local.md        📝 (new optional file for DoD)
```

### Tests
```
test/evals/run-evals.sh         ✏️  (v2 + stall validation logic)
test/evals/scenarios/*.json     ➕ 30 new scenarios (71–95+5 override)
```

### Documentation
```
README.md                       ✏️  (v2 fields, DoD, stall risk)
CHANGELOG.md                    ✏️  (1.2.0, 1.3.0, 1.4.0, 1.5.0 entries)
docs/plans/                     📝 (this roadmap + phase designs)
```

---

## Design Philosophy

### Core Principles (Unchanged Across Phases)

1. **File-based, deterministic** — No background agents or daemons
2. **Graceful fallback** — If anything fails, default to allow stop
3. **Backward compatible** — Old configs/records still work
4. **Observable** — Debug logs + explain.sh show what happened
5. **User-controlled** — Optional features default to off (no surprises)

### Design Constraints

- ❌ No new dependencies
- ❌ No schema migrations (only additions)
- ❌ No breaking changes
- ✅ All logic deterministic (no randomness)
- ✅ All decisions explainable (why did we continue/stop?)

---

## Next Steps

1. **Read design documents** (in order):
   - Phase 2: `2025-12-22-phase2-design.md` + implementation guide
   - Phase 3: `2025-12-22-phase3-design.md`
   - Phase 4: `2025-12-22-phase4-design.md`
   - Phase 5: `2025-12-22-phase5-design.md`

2. **Choose implementation path**:
   - Quick path: Phases 2–4 (3 months)
   - Full path: Phases 2–5 (4 months)

3. **Start Phase 2**:
   - Use implementation guide (copy-paste ready)
   - Follow file modification order
   - Run tests frequently

4. **Block on decisions**:
   - Phase 4: Frontmatter format for DoD (chosen: `.claude/redbull.local.md`)
   - Phase 4: Enforcement level (chosen: advisory default, strict optional)
   - Phase 5: Wait for Claude Code override signal (if implementing feedback)

---

## Glossary

- **Judge:** Separate Claude Haiku instance evaluating continuation
- **Heuristic:** Pattern-matching rule (regex/keywords)
- **Signal:** Detected communication type (asking_for_approval, explicit_next_steps, etc.)
- **DoD:** Definition of Done (user-defined completion checklist)
- **Stall:** No progress despite continuations (context unchanged)
- **Risk Score:** Stall likelihood (0–100)
- **Advisory:** Judge considers criterion but can override
- **Strict:** Judge refuses to violate criterion

---

## Related Documentation

- **Original Plan:** `2025-12-22-redbull-improvement-plan.md`
- **Phase 2 Quick Ref:** `2025-12-22-phase2-quick-reference.md`
- **Hook Architecture:** `../CLAUDE.md` (Hook Flow section)
- **Current Setup:** `../README.md` (Technical Details)

