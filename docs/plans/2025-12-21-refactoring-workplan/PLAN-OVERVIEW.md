# Refactoring Workplan (Parallelized) — Redbull Plugin

Date: 2025-12-21  
Source: `/docs/ideas/2025-21-12-refactoring/markdown/consolidated-refactoring-ideas.md`  
Scope: Items above the cutoff (#1–#12) from the re-rank.

## Objective

Make refactoring safe and high-velocity by first restoring **trustworthy regression signals**, then hardening the hook’s **I/O correctness** and **input boundaries**, while keeping the hook’s external behavior and contract unchanged.

## Non‑Negotiables / Constraints

- **No behavior changes** to the Stop hook decision semantics unless explicitly approved.
- Preserve hook I/O contract: **stdin JSON → stdout JSON**.
- Keep the runtime footprint: **bash + jq + claude CLI** (no new runtime deps).
- All optional output must go to **stderr** (stdout stays JSON-only).

## Proving Commands (Repo Standard)

- Primary regression: `./test/evals/run-evals.sh`
- Working directory invariants: `./test/test-working-directory.sh`

## Workstreams (Designed for Parallel Implementation)

### Stream A — Regression Harness (unblocks everything)
- ~~REF-001~~ ✓, ~~REF-012~~ ✓

### Stream B — Hook Core Safety & Robustness (validate after Stream A)
- ~~REF-003~~ ✓, ~~REF-002~~ ✓, ~~REF-011~~ ✓, ~~REF-006~~ ✓, ~~REF-010~~ ✓

### Stream C — Path + Docs Alignment (can run in parallel; coordinate with Stream A)
- REF-007, REF-019

### Stream D — Debuggability (parallel; strictly opt-in)
- REF-020

### Stream E — Deterministic Local Testing (parallel; mostly harness-side)
- REF-016

## Dependency / Blockers Map

- **Hard blocker:** REF-001 is required before claiming “no drift” on anything else.
- **Coordination needed:** REF-007 + REF-019 must align with the final, corrected hook path used by REF-001.
- **Best done after REF-003:** REF-011/REF-010 changes often want a single safe emitter path to fail-closed.
- **REF-016** can be started anytime, but its usefulness depends on having a clean harness and stable fixture IO.

## Execution Plan (Parallel)

### Phase 0 (Day 0): Create baseline + lock the harness
- Stream A starts immediately.
- Streams B/C/D/E can open PRs in parallel but should not merge until Stream A is green.

### Phase 1 (Day 1): Merge in safe increments
Recommended merge order after Stream A is green:
1) REF-003 (safe output)  
2) REF-002 (constants)  
3) REF-011 (validation)  
4) REF-006 (throttle functions)  
5) REF-010 (transcript robustness)  
6) Stream C docs/path polish (if still needed)  
7) REF-020 (debug logging)  
8) REF-016 (offline deterministic mode)

## Work Item Matrix (Top 12)

| ID | Stream | Primary Files | Status | Merge Blockers | Proving Commands |
|---|---|---|---|---|---|
| REF-007 | C | `test/evals/run-evals.sh`, `hooks/hooks.json`, `RELENG.md`, `CLAUDE.md` | Pending | Coordinate with REF-001 | `./test/evals/run-evals.sh` |
| REF-013 | A/B | `hooks/claude-judge-continuation.sh`, `test/` | Pending | REF-001 | `./test/evals/run-evals.sh` + snapshot script |
| REF-019 | C | `RELENG.md`, `CLAUDE.md`, `README.md` | Pending | Coordinate with REF-001 | `rg \"scripts/\" -n` + `./test/evals/run-evals.sh` |
| REF-020 | D | `hooks/claude-judge-continuation.sh` | Pending | REF-001 | `./test/evals/run-evals.sh` |
| REF-016 | E | `test/evals/` (+ optional hook env seams) | Pending | REF-001 | mock-mode script + `./test/evals/run-evals.sh` |

## Deliverables (Files to be Created by This Plan)

- One markdown plan per refactor item (see `docs/plans/2025-12-21-refactoring-workplan/`).

---

## ✅ Completed Items (Merged to main)

### Stream A — Regression Harness

| ID | PR | Commit | Description | Merged |
|---|---|---|---|---|
| REF-001 | #1 | e5df2d4 | fix: Repair eval harness hook script path and error handling | 2025-12-21 |
| REF-012 | #4 | 6cb9bcb | feat: speed up eval suite with stub claude binary | 2025-12-21 |

**Status:** Harness baseline established. All regression signals trustworthy. Unblocked all dependent streams.

### Stream B — Hook Core Safety & Robustness

| ID | PR | Commit | Description | Merged |
|---|---|---|---|---|
| REF-003 | #3 | 6bdbf6c | refactor: Normalize decision output via single emit_decision helper | 2025-12-21 |
| REF-002 | #6 | 4abb575 | refactor: Extract configuration constants to top of hook script | 2025-12-21 |
| REF-006 | #5 | 4b4ca62 | refactor: Refactor throttle helpers in judge continuation | 2025-12-21 |
| REF-011 | #7 | 5a8f32a | feat: Tighten input validation boundaries | 2025-12-21 |
| REF-010 | #8 | dc6d212 | feat: improve transcript extraction robustness + Add eval coverage | 2025-12-21 |

**Status:** Hook core hardened with:
- Centralized decision emission (REF-003)
- Configuration constant extraction (REF-002)
- Refactored throttle logic with helper functions (REF-006)
- Input validation boundaries tightened (REF-011)
- Transcript extraction made robust with validation + eval coverage (REF-010)

### Remaining Items

| Stream | Items | Status |
|---|---|---|
| C (Path + Docs) | REF-007, REF-019 | Pending coordination |
| D (Debuggability) | REF-020 | Pending |
| E (Deterministic) | REF-016 | Pending |
| Uncategorized | REF-013 | Pending (eval coverage extension) |

