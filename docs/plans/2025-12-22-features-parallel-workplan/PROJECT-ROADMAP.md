# Redbull Plugin Feature Workplan (Parallelized)

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Ship the top feature ideas (control + transparency + safety) with minimal merge conflicts and no breaking changes to the hook I/O contract.

**Architecture:** Keep `hooks/claude-judge-continuation.sh` as a thin orchestrator and move reusable logic into `hooks/lib/*.sh` so multiple streams can work concurrently without editing the same file. New hook events (`PreToolUse`, `SessionStart`, `PostToolUse`) are implemented as separate scripts first, then registered in one controlled integration step.

**Tech Stack:** Bash hook scripts + `jq` + `claude` CLI + existing eval harness (`./test/evals/run-evals.sh`).

Source: `docs/ideas/2025-21-12-features/markdown/consolidated-feature-ideas.md`

## Execution Order & Dependencies (Sequential → Parallel → Sequential)

### Phase 1: Prerequisites (SEQUENTIAL — MUST MERGE FIRST)

⚠️ **BLOCKING** — All Phase 2 workstreams assume these foundations exist.

1) **WS-00: Hook modularization + shared utilities**
   - **Branch:** `feat/ws-00-hook-modularization`
   - **Why sequential:** Most features otherwise compete on `hooks/claude-judge-continuation.sh`.
   - **Est. time:** 1.5–3 hours
   - **Merge requirement:** Must be merged to `main` before Phase 2 starts.

2) **WS-01: Per-project settings reader (safe, fail-closed)**
   - **Branch:** `feat/ws-01-per-project-settings`
   - **Depends on:** WS-00 (uses `hooks/lib/*`)
   - **Why sequential:** Many later features need an opt-in settings switch.
   - **Est. time:** 1–2 hours
   - **Merge requirement:** Must be merged to `main` before enabling/landing new hook events.

### Phase 2: Parallel Development (PARALLEL — CAN BE DONE SIMULTANEOUSLY)

✅ **PARALLEL STREAMS** — Separate branches; minimal shared file contention if Phase 1 is merged.

3) **WS-02: Observability + “explain last decision” (FTR-005, FTR-006)**
   - **Branch:** `feat/ws-02-decision-logs`
   - **Can start:** After WS-00 is merged
   - **Depends on:** WS-00
   - **Est. time:** 2–4 hours
   - **Primary files:** `hooks/lib/decision-log.sh`, `hooks/redbull`, `test/`

4) **WS-03: Control plane (throttle/model/dry-run/ignore/rules) (FTR-023, FTR-004, FTR-007, FTR-020, FTR-002)**
   - **Branch:** `feat/ws-03-control-plane`
   - **Can start:** After WS-00 is merged
   - **Depends on:** WS-00 (+ optionally WS-01 for settings wiring)
   - **Est. time:** 3–6 hours
   - **Primary files:** `hooks/lib/config.sh`, `hooks/lib/throttle.sh`, `hooks/lib/prompt.sh`, `hooks/redbull`, `test/`

5) **WS-04: Handoff snapshot artifact (Stop-only) (FTR-009)**
   - **Branch:** `feat/ws-04-handoff-snapshot`
   - **Can start:** After WS-00 is merged
   - **Depends on:** WS-00
   - **Est. time:** 2–4 hours
   - **Primary files:** `hooks/lib/handoff.sh`, `test/`

6) **WS-05: PreToolUse guardrails script (script only; not registered yet) (FTR-014)**
   - **Branch:** `feat/ws-05-pretooluse-guardrails`
   - **Can start:** Immediately (independent script)
   - **Depends on:** WS-01 before registration (opt-in gate)
   - **Est. time:** 3–6 hours (payload-shape uncertainty)
   - **Primary files:** `hooks/claude-guardrail-pretooluse.sh`, `test/`

7) **WS-06: SessionStart brief script (script only; not registered yet) (FTR-010)**
   - **Branch:** `feat/ws-06-sessionstart-brief`
   - **Can start:** Immediately (independent script)
   - **Depends on:** WS-01 before registration (opt-in gate)
   - **Est. time:** 2–4 hours (payload-shape uncertainty)
   - **Primary files:** `hooks/claude-sessionstart-brief.sh`, `test/`

8) **WS-07: PostToolUse triage script (script only; not registered yet) (FTR-016)**
   - **Branch:** `feat/ws-07-posttooluse-triage`
   - **Can start:** Immediately (independent script)
   - **Depends on:** WS-01 before registration (opt-in gate)
   - **Est. time:** 3–6 hours (payload-shape uncertainty)
   - **Primary files:** `hooks/claude-posttooluse-triage.sh`, `test/`

### Phase 3: Integration (SEQUENTIAL — MUST WAIT FOR PHASE 2)

⚠️ **INTEGRATION TASKS** — One “traffic cop” branch to avoid `hooks/hooks.json` conflicts.

9) **INT-00: Register new hook events + wire opt-in**
   - **Branch:** `feat/int-00-register-new-hooks`
   - **Can start:** Only after WS-01 is merged and WS-05/06/07 scripts are merged (or ready-to-merge)
   - **Est. time:** 1–2 hours
   - **Primary files:** `hooks/hooks.json`, `hooks/*.sh`, `test/` (+ manual Claude Code verification)

## High-Contention Files / Integration Hotspots

- `hooks/claude-judge-continuation.sh` (Stop hook orchestrator)
- `hooks/hooks.json` (hook registration; change only in INT-00)
- `hooks/redbull` (CLI; avoid conflicts by adding subcommands as separate scripts in `hooks/cli/` per WS-02/WS-03)
- `test/evals/run-evals.sh` (keep stable; add separate `test/test-*.sh` where possible)

## Non-Negotiables / Constraints (Safety + Compatibility)

- Preserve hook I/O contract: stdin JSON → stdout JSON with at least `{ "decision": "block"|"approve", "reason": "..." }`.
- **No new runtime deps** (only bash + `jq` + `claude` CLI).
- Default to **safe / fail-open** for new hook events (approve / do nothing) unless explicitly enabled.
- All non-JSON debug output goes to **stderr** only.

## Proving Commands (Repo Standard)

- Primary regression: `./test/evals/run-evals.sh`
- Working-directory invariant: `./test/test-working-directory.sh`
- Feature-specific scripts (added by workstreams): `./test/test-*.sh`

## Developer Assignment Strategy

### 1 developer (sequential)
1) WS-00 → WS-01 → (WS-02/03/04) → (WS-05/06/07) → INT-00

### 2 developers (optimal parallelism)
- Dev A: WS-00 → WS-01 → INT-00
- Dev B (after WS-00): WS-02 + WS-03 + WS-04 (parallel in time, sequential in person)

### 3–5 developers (maximum parallelism)
- Dev A: WS-00 (then help merge/review)
- Dev B: WS-01
- Dev C: WS-02
- Dev D: WS-03
- Dev E: WS-04
- Any available: WS-05/06/07 (scripts only) once WS-01 exists for opt-in gating; INT-00 is owned by a single integrator.

