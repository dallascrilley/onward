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
- REF-001, REF-012

### Stream B — Hook Core Safety & Robustness (validate after Stream A)
- REF-003, REF-002, REF-011, REF-006, REF-010

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

| ID | Stream | Primary Files | Can Start Now | Merge Blockers | Proving Commands |
|---|---|---|---|---|---|
| REF-001 | A | `test/evals/run-evals.sh` | Yes | None | `./test/evals/run-evals.sh` |
| REF-003 | B | `hooks/claude-judge-continuation.sh` | Yes | REF-001 | `./test/evals/run-evals.sh`, `./test/test-working-directory.sh` |
| REF-002 | B | `hooks/claude-judge-continuation.sh` | Yes | REF-001 | `./test/evals/run-evals.sh`, `./test/test-working-directory.sh` |
| REF-007 | C | `test/evals/run-evals.sh`, `hooks/hooks.json`, `RELENG.md`, `CLAUDE.md` | Yes | Coordinate with REF-001 | `./test/evals/run-evals.sh` |
| REF-013 | A/B | `hooks/claude-judge-continuation.sh`, `test/` | Yes | REF-001 | `./test/evals/run-evals.sh` + snapshot script |
| REF-011 | B | `hooks/claude-judge-continuation.sh` | Yes | REF-001 (and ideally REF-003) | `./test/evals/run-evals.sh` |
| REF-019 | C | `RELENG.md`, `CLAUDE.md`, `README.md` | Yes | Coordinate with REF-001 | `rg \"scripts/\" -n` + `./test/evals/run-evals.sh` |
| REF-012 | A | `test/evals/run-evals.sh` | Yes | None | `./test/evals/run-evals.sh` |
| REF-020 | D | `hooks/claude-judge-continuation.sh` | Yes | REF-001 | `./test/evals/run-evals.sh` |
| REF-006 | B | `hooks/claude-judge-continuation.sh` | Yes | REF-001 | `./test/evals/run-evals.sh` |
| REF-016 | E | `test/evals/` (+ optional hook env seams) | Yes | REF-001 | mock-mode script + `./test/evals/run-evals.sh` |
| REF-010 | B | `hooks/claude-judge-continuation.sh` | Yes | REF-001 | `./test/evals/run-evals.sh` |

## Deliverables (Files to be Created by This Plan)

- One markdown plan per refactor item (see `docs/plans/2025-12-21-refactoring-workplan/`).

