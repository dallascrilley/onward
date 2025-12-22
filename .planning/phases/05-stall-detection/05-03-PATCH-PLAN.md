# Phase 5 Stall Detection — Patch Plan (Small)

## Objective
Close the remaining design gaps for Phase 5 stall detection with minimal, targeted edits.

## Scope
- Behavior: multi-signal aggregation, decision threshold adjustment, and throttle hash consistency
- Tests: add missing stall scenarios (92–95)
- Docs: update `explain.sh` output if needed

## Plan

### Task 1 — Aggregate stall signals + apply risk thresholds
**Why:** Aligns behavior with design: multiple signals contribute to risk, and high risk tightens continuation threshold.

**Changes**
- Update `detect_stall()` to compute all three signals without early return; return structured flags or update caller to compute flags independently.
- Ensure `calculate_stall_risk()` receives correct flags for all signals.
- Apply high/moderate risk thresholds to continuation decision.

**Files**
- `hooks/lib/judge.sh`
- `hooks/claude-judge-continuation.sh`

**Acceptance Criteria**
- Stall risk reflects multiple simultaneous signals.
- High risk (>70) prevents continuation below stricter confidence threshold.
- Moderate risk (40–70) tightens the confidence threshold.

**Proving Command**
```bash
./test/evals/run-evals.sh
```

---

### Task 2 — Ensure context hash is persisted on continuation path
**Why:** Design assumes context hash is always tracked; current continue path omits the hash in throttle write.

**Changes**
- Pass `CURRENT_CONTEXT_HASH` to `throttle_write` on normal continue.

**Files**
- `hooks/claude-judge-continuation.sh`

**Acceptance Criteria**
- Throttle file v2 includes context hash for normal continues.

**Proving Command**
```bash
./test/evals/run-evals.sh
```

---

### Task 3 — Add missing stall scenarios (92–95)
**Why:** Design specifies 5 stall scenarios; only 91 exists.

**Changes**
- Add scenarios for:
  - 92: confidence declining
  - 93: repeated decision_category
  - 94: combined signals
  - 95: throttle limit + stall detected

**Files**
- `test/evals/scenarios/92-stall-confidence-declining.json`
- `test/evals/scenarios/93-stall-category-repeated.json`
- `test/evals/scenarios/94-stall-multi-signal.json`
- `test/evals/scenarios/95-stall-throttle-limit.json`

**Acceptance Criteria**
- New scenarios pass 5/5.
- Existing scenarios still pass.

**Proving Command**
```bash
./test/evals/run-evals.sh
```

---

### Task 4 — Verify `explain.sh` stall section (optional)
**Why:** Design expects stall risk surfaced in verbose mode; verify output matches spec.

**Changes**
- Confirm stall section renders risk, status, and recommendation when fields present.
- Update messaging if needed.

**Files**
- `scripts/explain.sh`

**Acceptance Criteria**
- `./scripts/explain.sh --verbose` shows stall risk and status when present in decision JSON.

**Proving Command**
```bash
./scripts/explain.sh --verbose
```

## Notes
- Do not change throttle file format unless explicitly requested.
- Avoid new dependencies or schema changes without approval.
