# Refactoring Brainstorm: focus_area (project-wide default)

*Skill used: adaptive-analyzing (synthesis) to combine repo docs, hook scripts, and test harness findings.*

## Focus Summary
- **Purpose**: Hook-based plugin that decides whether Claude should continue by running a separate Claude evaluation on recent transcript context.
- **Key flows**: Stop hook event ingestion → event parsing + transcript sampling → Claude evaluator call with schema → throttle update → decision JSON output.
- **Current technical debt indicators**: Monolithic hook script with mixed concerns (IO, throttling, prompting, decision output), repeated `jq` parsing and file reads, hard-coded constants (time window, sample size), path drift between hook and eval runner, and limited validation/observability in the test harness.
- **Constraints**: Must preserve hook input/output contract, cross-platform compatibility (run-hook.cmd + bash), no new runtime dependencies, and behavioral parity with existing eval scenarios.
- **Risks/unknowns**: Prompt changes can shift classification, LLM non-determinism complicates regression guarantees, and Windows path resolution differences can cause subtle failures.

## Candidate Refactoring Opportunities (Unfiltered, max 20)
1. Normalize hook script paths across hooks and tests using a single source-of-truth constant.
2. Collapse event parsing into one `jq` pass with validation + defaults.
3. Extract throttle handling into small functions with consistent read/write/cleanup.
4. Reduce process spawning by batching `jq` reads and avoiding repeated `cat`/`cut` in the hook.
5. Externalize evaluation prompt + JSON schema into versioned template files with snapshot checks.
6. Add optional structured debug tracing for decision flow.
7. Create a shared bash helper library for JSON parsing, logging, and temp handling.
8. Validate scenario schema and normalize transcripts before running evals.
9. Add deterministic local harness to stub `claude` for fast unit checks.
10. Reduce dependency on `jq` in the eval runner for simple JSON assembly (if acceptable).
11. Simplify nested conditionals in the hook with early returns.
12. Split hook into a pure decision engine + IO wrapper with a CLI harness.

## Top Refactoring Tasks (Ranked)

| # | ID | Title | Cat. | Impact | Effort | Exp. | Risk | Novelty | Priority | Targets / Search |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | REF-001 | Normalize hook script paths and root resolution across hooks/tests | Conventional | 5 | 1 | 2 | 1 | 1 | 5.00 | hooks/claude-judge-continuation.sh; hooks/run-hook.cmd; hooks/hooks.json; test/evals/run-evals.sh; HOOK_SCRIPT; run-hook.cmd; claude-judge-continuation.sh; scripts/claude-judge-continuation.sh; CLAUDE_PLUGIN_ROOT |
| 2 | REF-002 | Consolidate hook event parsing and validation into a single jq pass | Conventional | 4 | 2 | 2 | 1 | 1 | 2.00 | hooks/claude-judge-continuation.sh; EVENT=; jq -r; stop_hook_active; transcript_path; session_id |
| 3 | REF-006 | Add scenario schema validation and normalization in eval runner | Conventional | 3 | 2 | 2 | 1 | 2 | 1.50 | test/evals/run-evals.sh; test/evals/scenarios/*.json; expected_decision; transcript; jq -r '.name' |
| 4 | REF-003 | Reduce hook process spawning and redundant reads | Conventional | 3 | 2 | 3 | 2 | 2 | 1.50 | hooks/claude-judge-continuation.sh; THROTTLE_FILE; cut -d:; cat "$THROTTLE_FILE"; tail -n 10; jq -s |
| 5 | REF-005 | Introduce shared bash helper library for hooks/tests | Conventional | 4 | 3 | 3 | 2 | 2 | 1.33 | hooks/claude-judge-continuation.sh; test/evals/run-evals.sh; test/test-working-directory.sh; hooks/lib/common.sh; SCRIPT_DIR=; cleanup(); trap cleanup |
| 6 | REF-004 | Externalize evaluation prompt and schema into versioned templates | Creative | 3 | 3 | 3 | 2 | 4 | 1.00 | hooks/claude-judge-continuation.sh; hooks/prompts/continuation-eval.txt; hooks/prompts/schema.json; EVALUATION_PROMPT; JSON_SCHEMA; SYSTEM_PROMPT |
| 7 | REF-007 | Add optional structured decision tracing for debug workflows | Creative | 3 | 3 | 3 | 2 | 4 | 1.00 | hooks/claude-judge-continuation.sh; decision; reason; DEBUG; trace |
| 8 | REF-008 | Split hook into a pure decision engine and IO wrapper | Moonshot | 5 | 5 | 4 | 4 | 5 | 1.00 | hooks/claude-judge-continuation.sh; hooks/decision-engine.sh; test/evals/run-evals.sh; decision; approve; block; claude --print |

## Rationale for #1
Normalizing the hook script path is a high-impact, low-effort fix that removes brittle coupling between hooks and tests. Path drift already exists, so this improves reliability and future-proofing without touching runtime behavior.

## Notes / Assumptions
- Focus area was unspecified; analysis defaults to a project-wide review.
- No additional dependencies are acceptable for runtime; refactors should stay in bash + jq + claude CLI.
