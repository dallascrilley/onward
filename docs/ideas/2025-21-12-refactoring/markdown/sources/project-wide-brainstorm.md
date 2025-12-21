# Project-Wide Refactoring Brainstorm

## Focus Summary
- **Purpose**: Hook-based plugin that decides whether Claude should continue by running a separate Claude evaluation on recent transcript context.
- **Key flows**: Stop hook event ingestion → event parsing + transcript sampling → Claude evaluator call with schema → throttle update → decision JSON output.
- **Current technical debt indicators**: Monolithic hook script with mixed concerns (IO, throttling, prompting, decision output), repeated `jq` parsing and file reads, hard-coded constants (time window, sample size), path drift between hook/tests (`hooks/` vs `scripts/`), and limited validation/observability in test harness.
- **Constraints**: Must preserve hook input/output contract, cross-platform compatibility (run-hook.cmd + bash), no new runtime dependencies, and behavioral parity with existing eval scenarios.
- **Risks/unknowns**: Prompt changes can shift classification, LLM non-determinism complicates regression guarantees, and Windows path resolution differences can cause subtle failures.

## Candidate Refactoring Opportunities (Unfiltered, max 20)
1. Normalize hook script paths across hooks and tests using a single source-of-truth constant (Impact 5, Effort 1, Exp 2, Risk 1, Novelty 1).
2. Collapse event parsing into one `jq` pass with validation + defaults (Impact 4, Effort 2, Exp 2, Risk 1, Novelty 1).
3. Extract throttle handling into small functions with consistent read/write/cleanup (Impact 4, Effort 2, Exp 2, Risk 1, Novelty 2).
4. Reduce process spawning by batching `jq` reads and avoiding repeated `cat`/`cut` in the hook (Impact 3, Effort 2, Exp 3, Risk 2, Novelty 2).
5. Externalize evaluation prompt + JSON schema into versioned template files with snapshot checks (Impact 3, Effort 3, Exp 3, Risk 2, Novelty 4).
6. Add optional structured debug tracing for decision flow (Impact 3, Effort 3, Exp 3, Risk 2, Novelty 4).
7. Create a shared bash helper library for JSON parsing, logging, and temp handling (Impact 4, Effort 3, Exp 3, Risk 2, Novelty 2).
8. Validate scenario schema and normalize transcripts before running evals (Impact 3, Effort 2, Exp 2, Risk 1, Novelty 2).
9. Add deterministic local harness to stub `claude` for fast unit checks (Impact 4, Effort 4, Exp 4, Risk 3, Novelty 4).
10. Reduce dependency on `jq` for simple JSON assembly in tests (Impact 2, Effort 2, Exp 2, Risk 1, Novelty 2).
11. Simplify nested conditionals in the hook with early returns (Impact 3, Effort 2, Exp 2, Risk 1, Novelty 1).
12. Split hook into a pure decision engine + IO wrapper with a CLI harness (Impact 5, Effort 5, Exp 4, Risk 4, Novelty 5).

## Top Refactoring Tasks (Ranked)

| # | ID | Title | Cat. | Impact | Effort | Exp. | Risk | Novelty | Priority | Targets / Search |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | REF-001 | Normalize hook script paths and root resolution across hooks/tests | Conventional | 5 | 1 | 2 | 1 | 1 | 5.00 | `hooks/claude-judge-continuation.sh`, `test/evals/run-evals.sh`, `HOOK_SCRIPT`, `run-hook.cmd` |
| 2 | REF-002 | Consolidate hook event parsing and validation into a single `jq` pass | Conventional | 4 | 2 | 2 | 1 | 1 | 2.00 | `hooks/claude-judge-continuation.sh`, `EVENT=`, `stop_hook_active`, `transcript_path` |
| 3 | REF-006 | Add scenario schema validation + normalization in eval runner | Conventional | 3 | 2 | 2 | 1 | 2 | 1.50 | `test/evals/run-evals.sh`, `test/evals/scenarios/*.json`, `expected_decision` |
| 4 | REF-003 | Reduce hook process spawning and redundant reads (performance) | Conventional | 3 | 2 | 3 | 2 | 2 | 1.50 | `hooks/claude-judge-continuation.sh`, `THROTTLE_FILE`, `cut -d:` |
| 5 | REF-005 | Introduce shared bash helper library for hooks/tests | Conventional | 4 | 3 | 3 | 2 | 2 | 1.33 | `hooks/lib/common.sh`, `SCRIPT_DIR=`, `cleanup()`, `trap cleanup` |
| 6 | REF-004 | Externalize evaluation prompt + schema into versioned templates | Creative | 3 | 3 | 3 | 2 | 4 | 1.00 | `EVALUATION_PROMPT`, `JSON_SCHEMA`, `hooks/prompts/*` |
| 7 | REF-007 | Add optional structured decision tracing for debug workflows | Creative | 3 | 3 | 3 | 2 | 4 | 1.00 | `reason`, `decision`, `DEBUG` |
| 8 | REF-008 | Split hook into pure decision engine + IO wrapper (moonshot) | Moonshot | 5 | 5 | 4 | 4 | 5 | 1.00 | `claude-judge-continuation.sh`, `decision`, `claude --print` |

## Rationale for #1
Path drift already exists between hooks and tests, making failures likely and debugging harder. Normalizing the hook script path in one place is high-impact and low-effort, reduces brittle coupling, and lowers the risk of silent breakages without touching runtime behavior.

## Notes / Assumptions
- Tests reference `scripts/claude-judge-continuation.sh` while the hook script lives in `hooks/`, indicating path divergence that should be reconciled.
- No additional dependencies are acceptable for runtime; refactors should stay in bash + jq + claude CLI.
- Focus area was treated as "project-wide" because no concrete focus area was provided.
