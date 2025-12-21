# Consolidated Refactoring Ideas — Redbull Plugin

Generated: 2025-12-21  
Source: Synthesized from 4 brainstorming iterations

---

## Focus Summary

### Purpose
Hook-based Claude Code plugin that intercepts **Stop** events and decides whether to **block** stopping (continue working) or **approve** stopping, using a secondary Claude instance for classification.

### Key Flows
1. **Stop hook entrypoint**: `hooks/claude-judge-continuation.sh` reads event JSON from stdin
2. **Recursion prevention**: `CLAUDE_HOOK_JUDGE_MODE=true` short-circuits to allow stop
3. **Throttle**: `/tmp/.claude-continue-throttle-<session>` limits continuations (3 per 5 minutes)
4. **Transcript context**: reads last N NDJSON lines from `transcript_path`, wraps into JSON array
5. **Claude evaluation**: `claude --print --output-format json --json-schema ...` returns structured output
6. **Decision mapping**: `should_continue=true` → `{decision:"block"}` else `{decision:"approve"}`

### Current Technical Debt Indicators
- **Eval harness path mismatch**: `test/evals/run-evals.sh` references non-existent `../../scripts/claude-judge-continuation.sh` instead of `hooks/claude-judge-continuation.sh`, causing false passes
- **Monolithic bash script**: mixes parsing, throttling, prompt construction, command execution, and output formatting
- **High external-process churn**: repeated `jq` invocations and multiple `cat/cut/tr/tail` spawns
- **Magic numbers and hard-coded policy**: throttle window, max continuations, transcript line count, model name, and workdir are inline
- **Inconsistent JSON output construction**: some paths `echo` raw JSON strings, others use `jq -n` (risk of escaping issues)
- **Docs drift**: `RELENG.md` and test harness reference `scripts/` while implementation lives under `hooks/`
- **Plugin name inconsistency**: `double-shot-latte` in plugin.json vs `redbull` in repo name

### Constraints
- **No external behavior changes**: hook I/O contract must remain `stdin JSON` → `stdout JSON` with same decision semantics
- **Keep bash + jq + claude CLI**: project is intentionally buildless; cross-platform wrapper must remain functional
- **Deterministic + fast**: hook should remain quick; any additional work should be optional/guarded

### Risks / Unknowns
- Small changes to prompt/evaluator integration can alter classification outcomes; refactors must be validated via eval suite (once fixed) and targeted regression tests
- Throttle behavior relies on `/tmp` semantics; refactor must preserve file naming/sanitization and time window logic
- LLM non-determinism complicates regression guarantees

---

## Consolidated Refactoring Ideas (Ranked by Priority Score)

### Scoring Criteria
- `impact`, `effort`, `expertise`, `risk`, `novelty` are integers 1–5
- `priority_score` = `round(impact/effort, 2)`
- **Tie-breakers**: lower risk → lower expertise → higher impact

| # | ID | Title | Category | Type | Area | Impact | Effort | Expertise | Risk | Novelty | Priority Score | Targets / Search |
|---:|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | REF-001 | Repair eval harness hook script path | Conventional | testing | build | 5 | 1 | 2 | 1 | 1 | **5.00** | `test/evals/run-evals.sh`, `HOOK_SCRIPT=`, `../../scripts/claude-judge-continuation.sh` |
| 2 | REF-002 | Extract configuration constants into named variables | Conventional | refactor | infra | 4 | 1 | 1 | 1 | 1 | **4.00** | `hooks/claude-judge-continuation.sh`, `300`, `3`, `tail -n 10`, `--model haiku`, `MAX_CONTINUATIONS`, `THROTTLE_WINDOW_SECONDS` |
| 3 | REF-003 | Normalize decision + error output via single emitter | Conventional | refactor | infra | 3 | 1 | 2 | 1 | 1 | **3.00** | `echo '{\"decision\"`, `jq -n --arg reason`, `emit_approve`, `emit_block`, `emit_error` |
| 4 | REF-004 | Add ShellCheck linting with CI/local script | Conventional | DX | CI | 3 | 1 | 1 | 1 | 1 | **3.00** | `shellcheck`, `hooks/*.sh`, `test/*.sh`, `.shellcheckrc` |
| 5 | REF-005 | Consolidate event JSON parsing into single jq pass | Conventional | perf | infra | 4 | 2 | 2 | 2 | 2 | **2.00** | `echo "$EVENT" \| jq`, `STOP_HOOK_ACTIVE`, `TRANSCRIPT_PATH`, `session_id` |
| 6 | REF-006 | Extract throttle logic into focused functions | Conventional | refactor | infra | 4 | 2 | 2 | 2 | 1 | **2.00** | `THROTTLE_FILE`, `CONTINUE_COUNT`, `TIME_SINCE_LAST`, `throttle_read`, `throttle_write`, `throttle_should_force_stop` |
| 7 | REF-007 | Centralize and parameterize script paths | Conventional | DX | build | 4 | 2 | 2 | 1 | 2 | **2.00** | `RELENG.md`, `CLAUDE.md`, `run-evals.sh`, `hooks/`, `CLAUDE_PLUGIN_ROOT` |
| 8 | REF-008 | Refactor into functional core + injected runner for testability | Creative | refactor | infra | 4 | 2 | 3 | 2 | 4 | **2.00** | `CLAUDE_RESPONSE=`, `CURRENT_TIME=`, `run_claude_evaluator`, `CLAUDE_BIN`, `NOW_BIN` |
| 9 | REF-009 | Reduce external command dependencies (tr, cut) | Conventional | perf | infra | 3 | 2 | 2 | 2 | 2 | **1.50** | `tr '/' '_'`, `cut -d:`, bash parameter expansion, `IFS=: read -r` |
| 10 | REF-010 | Improve transcript extraction robustness | Conventional | refactor | infra | 3 | 2 | 2 | 2 | 1 | **1.50** | `tail -n`, `jq -s`, NDJSON handling, empty/invalid lines |
| 11 | REF-011 | Tighten input validation boundaries | Conventional | refactor | infra | 3 | 2 | 2 | 2 | 1 | **1.50** | `jq -r '.transcript_path'`, `session_id`, validate event JSON shape |
| 12 | REF-012 | Add scenario schema validation + normalization in eval runner | Conventional | testing | build | 3 | 2 | 2 | 1 | 2 | **1.50** | `test/evals/run-evals.sh`, `test/evals/scenarios/*.json`, `expected_decision`, `transcript` |
| 13 | REF-013 | Add snapshot tests for prompt + schema | Conventional | testing | build | 3 | 2 | 2 | 1 | 2 | **1.50** | prompt text, `JSON_SCHEMA=`, snapshot fixture |
| 14 | REF-014 | Introduce prompt templating (guarded, no behavior change) | Creative | DX | infra | 3 | 2 | 2 | 2 | 4 | **1.50** | `EVALUATION_PROMPT=`, `SYSTEM_PROMPT=`, `build_evaluation_prompt`, `hooks/prompts/` |
| 15 | REF-015 | Add performance timing instrumentation | Conventional | perf | infra | 3 | 2 | 2 | 1 | 2 | **1.50** | `date +%s`, `HOOK_START_TIME`, `HOOK_DURATION`, optional metrics |
| 16 | REF-016 | Add deterministic offline eval mode | Creative | testing | build | 4 | 3 | 3 | 2 | 4 | **1.33** | `PATH` mocking, `CLAUDE_HOOK_JUDGE_MODE`, `claude --print`, mock claude runner |
| 17 | REF-017 | Introduce shared bash helper library for hooks/tests | Conventional | refactor | infra | 4 | 3 | 3 | 2 | 2 | **1.33** | `hooks/lib/common.sh`, `SCRIPT_DIR=`, `cleanup()`, `trap cleanup`, JSON helpers |
| 18 | REF-018 | Fix plugin name inconsistency | Conventional | DX | design | 2 | 1 | 1 | 1 | 1 | **2.00** | `plugin.json`, `double-shot-latte`, `redbull`, `CLAUDE_WORK_DIR` |
| 19 | REF-019 | Align docs naming + paths | Conventional | DX | design | 2 | 2 | 1 | 1 | 1 | **1.00** | `RELENG.md`, `scripts/`, plugin naming, remove `scripts/` references |
| 20 | REF-020 | Add optional structured debug logging | Conventional | DX | infra | 2 | 2 | 2 | 1 | 2 | **1.00** | `DEBUG`, timestamps, stderr, structured fields, guarded by env var |
| 21 | REF-021 | Moonshot: modularize into `hooks/lib/*.sh` modules | Moonshot | refactor | infra | 5 | 4 | 4 | 3 | 5 | **1.25** | `source`, `hooks/lib`, `emit_*`, `throttle_*`, `json.sh`, `prompt.sh`, `claude-runner.sh` |

---

## Detailed Refactoring Tasks (Ticket-Ready)

### REF-001 — Repair eval harness hook script path

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `testing`
- **area**: `build`
- **owner_role**: `QA`
- **parent_epic_id**: `EPIC-01`
- **current_state_assessment**:
  - `test/evals/run-evals.sh` references `../../scripts/claude-judge-continuation.sh` but the real hook script is `hooks/claude-judge-continuation.sh`.
  - The harness converts execution failures into `{"decision":"error"}`, which incorrectly "passes" scenarios expecting STOP and obscures real regressions.
- **scores**:
  - impact: 5
  - effort: 1
  - expertise: 2
  - risk: 1
  - novelty: 1
- **priority_score**: 5.00
- **scope**:
  - Update `test/evals/run-evals.sh` to point at the correct hook entrypoint.
  - Adjust harness failure handling so "hook execution failed" fails the scenario (rather than mapping to STOP silently).
- **implementation_steps**:
  1. Replace `HOOK_SCRIPT=.../../../scripts/...` with `.../../../hooks/claude-judge-continuation.sh`.
  2. If hook execution fails (non-zero or invalid JSON), mark the run as failed with a clear error message.
  3. Add a preflight check that `HOOK_SCRIPT` exists + is executable; fail fast otherwise.
  4. Update `RELENG.md` and any docs that reference the old `scripts/` path (if needed to keep docs consistent).
- **acceptance_criteria**:
  - [ ] `./test/evals/run-evals.sh` fails fast if the hook script path is wrong
  - [ ] Hook execution failures fail scenarios (no silent "error == stop" masking)
  - [ ] Existing scenario expectations remain unchanged
  - [ ] No behavior changes in the hook itself (verification: the hook script is not modified by this ticket)
- **test_plan**:
  - Level: integration (test harness)
  - Location: `test/evals/run-evals.sh`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `HOOK_SCRIPT=`
  - `../../scripts/claude-judge-continuation.sh`
  - `hook_output=`
  - `{"decision": "error"}`
- **expected_improvements**:
  - Restore confidence in refactors by making regressions observable.
  - Reduce time wasted debugging false positives/negatives.

### REF-002 — Extract configuration constants into named variables

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `refactor`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **current_state_assessment**:
  - Magic numbers and policy knobs are embedded throughout the script (`3`, `300`, `tail -n 10`, model name).
  - Threshold semantics are harder to review and tune without risking accidental drift.
- **scores**:
  - impact: 4
  - effort: 1
  - expertise: 1
  - risk: 1
  - novelty: 1
- **priority_score**: 4.00
- **scope**:
  - `hooks/claude-judge-continuation.sh` only.
- **implementation_steps**:
  1. Add constants near the top (e.g., `MAX_CONTINUATIONS`, `THROTTLE_WINDOW_SECONDS`, `TRANSCRIPT_CONTEXT_LINES`, `CLAUDE_MODEL`, `CLAUDE_WORK_DIR`).
  2. Replace inline literals with those constants.
  3. Ensure prompt text references remain unchanged (only variable substitution for counts where safe).
  4. Run regression tests after `REF-001` is complete.
- **acceptance_criteria**:
  - [ ] All policy values exist as clearly-named variables in one place
  - [ ] No logic changes (only replacing literals with variables)
  - [ ] No behavior changes verification: `./test/evals/run-evals.sh` results unchanged vs baseline
  - [ ] Working directory test still passes: `./test/test-working-directory.sh`
- **test_plan**:
  - Level: regression/integration
  - Location: `test/evals/` + `test/test-working-directory.sh`
  - Commands: `./test/test-working-directory.sh` and `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `300`
  - `-ge 3`
  - `tail -n 10`
  - `--model haiku`
  - `~/.claude/double-shot-latte`
- **expected_improvements**:
  - Easier reviews and safer future tuning.
  - Clearer policy intent; fewer accidental inconsistencies.

### REF-003 — Normalize decision + error output via single emitter

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `refactor`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **current_state_assessment**:
  - Some paths output JSON with `echo '{...}'` while others use `jq -n`, risking inconsistent escaping and format drift.
  - Error paths don't have a consistent structure (harder to grep and reason about).
- **scores**:
  - impact: 3
  - effort: 1
  - expertise: 2
  - risk: 1
  - novelty: 1
- **priority_score**: 3.00
- **scope**:
  - `hooks/claude-judge-continuation.sh` only.
- **implementation_steps**:
  1. Create helper functions: `emit_approve <reason>`, `emit_block <reason>`, `emit_error <reason>` (or a single `emit_decision <decision> <reason>`).
  2. Replace all `echo '{...}'` JSON paths with the helper(s) using `jq -n --arg`.
  3. Ensure reasons remain semantically identical (same strings, just safely encoded).
  4. Keep stdout-only behavior; avoid extra noise unless explicitly requested by env flag.
- **acceptance_criteria**:
  - [ ] All outputs are produced via one helper path (no raw JSON `echo` remains)
  - [ ] Output JSON shape remains compatible with current hook contract
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Failure reasons remain readable and stable for logging/debugging
- **test_plan**:
  - Level: regression/integration
  - Location: `test/evals/` + manual pipe test
  - Commands: `./test/evals/run-evals.sh` and `echo '{...}' | ./hooks/claude-judge-continuation.sh`
- **targets_search_tokens**:
  - `echo '{\"decision\"`
  - `jq -n --arg reason`
  - `"decision": "approve"`
  - `"decision": "block"`
- **expected_improvements**:
  - Lower risk of malformed JSON.
  - Easier future changes to output format without missing branches.

### REF-004 — Add ShellCheck linting with CI/local script

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `DX`
- **area**: `CI`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **current_state_assessment**:
  - No shellcheck or bash linting configured despite AGENTS.md noting this gap.
  - Quoting issues and bash nits can be caught automatically.
- **scores**:
  - impact: 3
  - effort: 1
  - expertise: 1
  - risk: 1
  - novelty: 1
- **priority_score**: 3.00
- **scope**:
  - Add shellcheck to local development workflow and/or CI.
  - Fix any violations found.
- **implementation_steps**:
  1. Create `.shellcheckrc` with appropriate exclusions for hook-specific patterns.
  2. Add shellcheck to local script or CI workflow.
  3. Fix any violations found (focus on quoting, variable expansion, etc.).
  4. Document linting process in README or CLAUDE.md.
- **acceptance_criteria**:
  - [ ] Shellcheck runs successfully on all `.sh` files
  - [ ] No critical violations remain (warnings acceptable if documented)
  - [ ] Linting is documented and easy to run locally
- **test_plan**:
  - Level: static analysis
  - Location: `hooks/*.sh`, `test/**/*.sh`
  - Command: `shellcheck hooks/*.sh test/**/*.sh`
- **targets_search_tokens**:
  - `shellcheck`
  - `hooks/*.sh`
  - `test/*.sh`
  - `.shellcheckrc`
- **expected_improvements**:
  - Catch quoting and bash nits before they cause issues.
  - Improve code quality and consistency.

### REF-005 — Consolidate event JSON parsing into single jq pass

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `perf`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **current_state_assessment**:
  - Event fields are extracted via multiple `jq -r` calls, each spawning a new process.
  - This increases latency and adds cognitive overhead (values can diverge if parsing changes).
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 2
- **priority_score**: 2.00
- **scope**:
  - `hooks/claude-judge-continuation.sh` parsing section.
- **implementation_steps**:
  1. Parse all needed fields from `$EVENT` with a single `jq` invocation (e.g., output TSV/JSON and read into vars).
  2. Validate parsed values early (empty transcript path, missing session id).
  3. Keep default values identical to today (`// false`, `// ""`, etc.).
  4. Re-run evals and working-dir test to confirm no drift.
- **acceptance_criteria**:
  - [ ] Only one `jq` invocation is used to parse the incoming event JSON
  - [ ] Default values match current behavior
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Hook still handles missing fields gracefully
- **test_plan**:
  - Level: regression/integration
  - Location: `test/evals/` + manual smoke tests
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `echo \"$EVENT\" | jq -r`
  - `.stop_hook_active`
  - `.transcript_path`
  - `.session_id`
- **expected_improvements**:
  - Fewer subprocesses → lower hook latency.
  - Clearer boundary for event parsing and validation.

### REF-006 — Extract throttle logic into focused functions

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `refactor`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **current_state_assessment**:
  - Throttle behavior is implemented inline with multiple nested conditionals and duplicated file parsing logic.
  - Session id sanitization and throttle file parsing use extra external commands (`tr`, `cut`).
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 1
- **priority_score**: 2.00
- **scope**:
  - Throttle-related logic in `hooks/claude-judge-continuation.sh`.
- **implementation_steps**:
  1. Extract throttle helpers: `throttle_file_for_session`, `throttle_read`, `throttle_write`, `throttle_should_force_stop`, `throttle_clear`.
  2. Replace `tr '/' '_'` with bash substitution (same output).
  3. Replace `cut -d:` parsing with safe bash parsing (`IFS=: read -r ...`).
  4. Flatten nested conditionals with early returns/guards.
- **acceptance_criteria**:
  - [ ] Throttle logic is isolated behind small functions with single responsibilities
  - [ ] Throttle file format and semantics are unchanged
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Throttle files are still cleared on legitimate stops
- **test_plan**:
  - Level: regression/integration + targeted throttle cases
  - Location: `test/evals/scenarios/` (add/adjust only if missing throttle coverage)
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `THROTTLE_FILE=`
  - `/tmp/.claude-continue-throttle-`
  - `cut -d:`
  - `tr '/' '_'`
  - `TIME_SINCE_LAST`
- **expected_improvements**:
  - Lower complexity and safer future changes to throttle policy.
  - Fewer external processes (small perf gain).

### REF-007 — Centralize and parameterize script paths

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `DX`
- **area**: `build`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **current_state_assessment**:
  - Paths to hook scripts are hardcoded in multiple places (test harness, docs, wrapper scripts).
  - Path drift already exists between hooks and tests, making failures likely and debugging harder.
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 2.00
- **scope**:
  - `test/evals/run-evals.sh`, `RELENG.md`, `CLAUDE.md`, `hooks/run-hook.cmd`.
- **implementation_steps**:
  1. Define hook script path as a constant in test harness (e.g., `HOOK_SCRIPT`).
  2. Use `${CLAUDE_PLUGIN_ROOT}` or similar for relative path resolution.
  3. Update all references to use the centralized constant.
  4. Ensure cross-platform compatibility (Windows via `run-hook.cmd`).
- **acceptance_criteria**:
  - [ ] Single source of truth for hook script path
  - [ ] All tests and docs reference the same path
  - [ ] Cross-platform compatibility maintained
  - [ ] No behavior changes in hook execution
- **test_plan**:
  - Level: integration
  - Location: `test/evals/run-evals.sh`, `hooks/run-hook.cmd`
  - Commands: `./test/evals/run-evals.sh` (Unix), verify Windows compatibility
- **targets_search_tokens**:
  - `RELENG.md`
  - `CLAUDE.md`
  - `run-evals.sh`
  - `hooks/`
  - `CLAUDE_PLUGIN_ROOT`
- **expected_improvements**:
  - Reduces brittle coupling between hooks and tests.
  - Easier to maintain and future-proof.

### REF-008 — Refactor into functional core + injected runner for testability

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `refactor`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-04`
- **experiment_category**: `creative`
- **small_experiment_(1–2h)**:
  - Extract a `run_claude_evaluator` function and make it injectable via env var (e.g., `CLAUDE_CMD=claude`), then update `test/evals` to swap in a mock claude for one scenario.
- **success_metric**:
  - One scenario can run deterministically without network/claude, while the default path remains unchanged.
- **rollback_plan**:
  - Revert env-injection and keep only internal function extraction (no test changes).
- **current_state_assessment**:
  - Hook is difficult to unit test because it hardcodes time (`date +%s`) and execution (`claude ...`) at call sites.
  - Most failures require full integration runs to diagnose.
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 3
  - risk: 2
  - novelty: 4
- **priority_score**: 2.00
- **scope**:
  - `hooks/claude-judge-continuation.sh` refactor into functions + injectable seams.
  - `test/evals/` minimal harness support for mock runner (optional).
- **implementation_steps**:
  1. Introduce "providers": `now_epoch_seconds`, `read_event`, `read_transcript_context`, `run_evaluator`, `map_evaluator_to_decision`.
  2. Default providers use existing commands; allow overriding with env vars for tests (`CLAUDE_BIN`, `NOW_BIN`, etc.).
  3. Keep output contract identical.
  4. Add 1–2 targeted tests that run in offline mode to validate the seam.
- **acceptance_criteria**:
  - [ ] Default behavior remains unchanged (same decisions for same transcripts)
  - [ ] No behavior changes verification: eval suite matches baseline in "real claude" mode
  - [ ] At least one deterministic test can run with a mocked evaluator
  - [ ] No new runtime dependencies introduced
- **test_plan**:
  - Level: regression/integration + deterministic harness
  - Location: `test/evals/` + potentially new minimal fixture(s)
  - Commands: `./test/evals/run-evals.sh` (real mode) and `./test/evals/run-evals.sh` (mock mode via env vars, if added)
- **targets_search_tokens**:
  - `date +%s`
  - `claude --print`
  - `CLAUDE_RESPONSE=`
  - `EVALUATION_RESULT=`
- **expected_improvements**:
  - Faster debugging and safer refactors due to testable seams.
  - Enables future changes (prompt tuning, perf) with less risk.

### REF-009 — Reduce external command dependencies (tr, cut)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `perf`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **current_state_assessment**:
  - Session id sanitization uses `tr '/' '_'` and throttle parsing uses `cut -d:`, each spawning a process.
  - These can be replaced with bash built-ins for minor performance gain.
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 2
- **priority_score**: 1.50
- **scope**:
  - Throttle and session ID handling in `hooks/claude-judge-continuation.sh`.
- **implementation_steps**:
  1. Replace `tr '/' '_'` with bash parameter expansion: `${SESSION_ID//\//_}`
  2. Replace `cut -d:` with bash `IFS=: read -r count timestamp` pattern.
  3. Verify output is identical to current behavior.
  4. Run regression tests.
- **acceptance_criteria**:
  - [ ] No external `tr` or `cut` commands remain in throttle/session logic
  - [ ] Output format and behavior unchanged
  - [ ] No behavior changes verification: eval suite matches baseline
- **test_plan**:
  - Level: regression/integration
  - Location: `test/evals/`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `tr '/' '_'`
  - `cut -d:`
  - bash parameter expansion
  - `IFS=: read -r`
- **expected_improvements**:
  - Fewer process spawns (minor perf gain).
  - More idiomatic bash code.

### REF-010 — Improve transcript extraction robustness

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `refactor`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **current_state_assessment**:
  - Transcript extraction uses `tail -n` followed by `jq -s`, which may not handle empty/invalid lines consistently.
  - No validation of NDJSON format before processing.
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 1
- **priority_score**: 1.50
- **scope**:
  - Transcript reading logic in `hooks/claude-judge-continuation.sh`.
- **implementation_steps**:
  1. Validate NDJSON lines before processing (skip empty/invalid).
  2. Use single `jq` operation where possible instead of `tail + jq`.
  3. Add error handling for missing or unreadable transcript files.
  4. Ensure default behavior matches current (graceful degradation).
- **acceptance_criteria**:
  - [ ] Empty/invalid NDJSON lines are handled gracefully
  - [ ] Missing transcript files don't crash the hook
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Transcript extraction is more robust
- **test_plan**:
  - Level: regression/integration + edge cases
  - Location: `test/evals/` (may need new scenarios for edge cases)
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `tail -n`
  - `jq -s`
  - NDJSON handling
  - empty/invalid lines
- **expected_improvements**:
  - More robust handling of edge cases.
  - Better error messages for debugging.

### REF-011 — Tighten input validation boundaries

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `refactor`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **current_state_assessment**:
  - Event JSON parsing doesn't validate required fields early.
  - Missing or invalid fields can cause cryptic failures later in execution.
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 1
- **priority_score**: 1.50
- **scope**:
  - Input validation in `hooks/claude-judge-continuation.sh`.
- **implementation_steps**:
  1. Validate event JSON shape early (required fields: `session_id`, `transcript_path`).
  2. Check transcript path exists and is readable before processing.
  3. Provide clear error messages for validation failures.
  4. Fail closed (approve stop) on validation errors with clear reason.
- **acceptance_criteria**:
  - [ ] Required fields are validated before processing
  - [ ] Clear error messages for invalid inputs
  - [ ] Validation failures result in safe defaults (approve stop)
  - [ ] No behavior changes verification: eval suite matches baseline
- **test_plan**:
  - Level: regression/integration + invalid input cases
  - Location: `test/evals/` (may need new scenarios)
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `jq -r '.transcript_path'`
  - `session_id`
  - validate event JSON shape
- **expected_improvements**:
  - Fail fast with clear errors.
  - Better debugging experience.

### REF-012 — Add scenario schema validation + normalization in eval runner

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `testing`
- **area**: `build`
- **owner_role**: `QA`
- **parent_epic_id**: `EPIC-01`
- **current_state_assessment**:
  - Scenario JSON files aren't validated before running tests.
  - Missing or malformed scenarios can cause cryptic test failures.
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 1.50
- **scope**:
  - `test/evals/run-evals.sh` scenario loading.
- **implementation_steps**:
  1. Validate scenario JSON schema (required: `name`, `description`, `expected_decision`, `transcript`).
  2. Normalize transcript format (ensure array of message objects).
  3. Fail fast with clear errors for invalid scenarios.
  4. Add preflight check before running any scenarios.
- **acceptance_criteria**:
  - [ ] All scenarios are validated before execution
  - [ ] Clear error messages for invalid scenarios
  - [ ] Test harness fails fast on schema violations
  - [ ] Existing scenarios continue to work
- **test_plan**:
  - Level: test infrastructure
  - Location: `test/evals/run-evals.sh`
  - Command: `./test/evals/run-evals.sh` (should validate all scenarios)
- **targets_search_tokens**:
  - `test/evals/run-evals.sh`
  - `test/evals/scenarios/*.json`
  - `expected_decision`
  - `transcript`
- **expected_improvements**:
  - Catch scenario errors early.
  - Better test reliability.

### REF-013 — Add snapshot tests for prompt + schema

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `testing`
- **area**: `build`
- **owner_role**: `QA`
- **parent_epic_id**: `EPIC-01`
- **current_state_assessment**:
  - Prompt and schema live inline in the main script; edits are high-risk and hard to review.
  - There is no guardrail ensuring accidental prompt edits are caught.
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 1.50
- **scope**:
  - Prompt/schema construction in `hooks/claude-judge-continuation.sh`.
  - A small snapshot check in `test/` (if feasible without new deps).
- **implementation_steps**:
  1. Extract prompt construction into a testable function.
  2. Create snapshot fixture for generated prompt (or schema) for one fixed transcript.
  3. Add snapshot comparison test.
  4. Document the safe workflow for prompt edits (update fixture + run eval suite).
- **acceptance_criteria**:
  - [ ] Snapshot test exists for prompt/schema generation
  - [ ] Snapshot check fails when prompt changes unexpectedly
  - [ ] No new runtime dependencies introduced
  - [ ] Prompt changes are reviewable via diff
- **test_plan**:
  - Level: regression + snapshot
  - Location: `test/` (snapshot fixture) + `test/evals/`
  - Commands: snapshot check (new script) and `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - prompt text
  - `JSON_SCHEMA=`
  - snapshot fixture
- **expected_improvements**:
  - Safer prompt iteration and clearer reviews.
  - Reduced accidental behavior drift during refactors.

### REF-014 — Introduce prompt templating (guarded, no behavior change)

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `DX`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **experiment_category**: `creative`
- **small_experiment_(1–2h)**:
  - Move prompt text into a file (or heredoc function) and add a snapshot test that asserts the rendered prompt matches an expected fixture for one scenario.
- **success_metric**:
  - Prompt changes become reviewable diffs without touching throttle/IO logic.
- **rollback_plan**:
  - Keep prompt in-script but refactor into a single heredoc function; drop snapshot testing.
- **current_state_assessment**:
  - Prompt and schema live inline in the main script; edits are high-risk and hard to review.
  - There is no guardrail ensuring accidental prompt edits are caught.
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 4
- **priority_score**: 1.50
- **scope**:
  - Prompt/schema construction in `hooks/claude-judge-continuation.sh`.
  - A small snapshot check in `test/` (if feasible without new deps).
- **implementation_steps**:
  1. Move prompt construction into `build_evaluation_prompt <recent_context_json>`.
  2. Keep prompt bytes identical initially (no wording changes).
  3. Add a snapshot fixture for the generated prompt (or schema) for one fixed transcript.
  4. Document the safe workflow for prompt edits (update fixture + run eval suite).
- **acceptance_criteria**:
  - [ ] Prompt content is byte-for-byte identical before/after refactor (initial cut)
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Snapshot check fails when prompt changes unexpectedly
  - [ ] No new runtime dependencies introduced
- **test_plan**:
  - Level: regression + snapshot
  - Location: `test/` (snapshot fixture) + `test/evals/`
  - Commands: snapshot check (new script) and `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `EVALUATION_PROMPT=`
  - `SYSTEM_PROMPT=`
  - `build_evaluation_prompt`
  - `hooks/prompts/`
- **expected_improvements**:
  - Safer prompt iteration and clearer reviews.
  - Reduced accidental behavior drift during refactors.

### REF-015 — Add performance timing instrumentation

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `perf`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **current_state_assessment**:
  - No metrics on hook latency impact.
  - Performance refactoring may have minimal real-world impact given infrequent hook invocation, but improves code quality.
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 1.50
- **scope**:
  - Optional timing instrumentation in `hooks/claude-judge-continuation.sh`.
- **implementation_steps**:
  1. Add timing at hook entry (`HOOK_START_TIME=$(date +%s)`).
  2. Calculate duration before exit.
  3. Output timing only if env var enabled (e.g., `REDBULL_DEBUG_TIMING=true`).
  4. Log to stderr to avoid interfering with JSON output.
- **acceptance_criteria**:
  - [ ] Timing is optional (guarded by env var)
  - [ ] No impact on default behavior (timing disabled by default)
  - [ ] Timing output doesn't interfere with JSON stdout
  - [ ] No behavior changes verification: eval suite matches baseline
- **test_plan**:
  - Level: regression/integration
  - Location: `test/evals/`
  - Commands: `./test/evals/run-evals.sh` (default) and with timing enabled
- **targets_search_tokens**:
  - `date +%s`
  - `HOOK_START_TIME`
  - `HOOK_DURATION`
  - optional metrics
- **expected_improvements**:
  - Visibility into hook performance for debugging.
  - Data to inform future optimizations.

### REF-016 — Add deterministic offline eval mode

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `testing`
- **area**: `build`
- **owner_role**: `QA`
- **parent_epic_id**: `EPIC-01`
- **current_state_assessment**:
  - All tests require network access and Claude API calls.
  - Non-deterministic LLM responses complicate regression testing.
- **scores**:
  - impact: 4
  - effort: 3
  - expertise: 3
  - risk: 2
  - novelty: 4
- **priority_score**: 1.33
- **scope**:
  - Mock `claude` runner for tests; keep true integration mode as opt-in.
- **implementation_steps**:
  1. Create mock `claude` script that returns deterministic responses.
  2. Allow swapping `claude` binary via `PATH` or env var for tests.
  3. Add test mode that uses mock runner.
  4. Keep integration mode as default (opt-in mock mode).
- **acceptance_criteria**:
  - [ ] At least one scenario can run deterministically without network/claude
  - [ ] Default path remains unchanged (real claude)
  - [ ] Mock mode is opt-in and clearly documented
  - [ ] No new runtime dependencies introduced
- **test_plan**:
  - Level: regression/integration + deterministic harness
  - Location: `test/evals/` + mock runner
  - Commands: `./test/evals/run-evals.sh` (real mode) and mock mode
- **targets_search_tokens**:
  - `PATH` mocking
  - `CLAUDE_HOOK_JUDGE_MODE`
  - `claude --print`
  - mock claude runner
- **expected_improvements**:
  - Faster test runs for development.
  - Deterministic regression testing.

### REF-017 — Introduce shared bash helper library for hooks/tests

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `refactor`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **current_state_assessment**:
  - Common utilities (JSON parsing, logging, temp handling) are duplicated or could be shared.
  - Test scripts and hook scripts could benefit from shared helpers.
- **scores**:
  - impact: 4
  - effort: 3
  - expertise: 3
  - risk: 2
  - novelty: 2
- **priority_score**: 1.33
- **scope**:
  - Create `hooks/lib/common.sh` with shared utilities.
- **implementation_steps**:
  1. Extract common functions (JSON helpers, cleanup, path resolution).
  2. Create `hooks/lib/common.sh` module.
  3. Source from hook script and test scripts.
  4. Ensure cross-platform compatibility.
- **acceptance_criteria**:
  - [ ] Shared library exists with common utilities
  - [ ] Hook and test scripts can source the library
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Cross-platform compatibility maintained
- **test_plan**:
  - Level: regression/integration
  - Location: `test/evals/` + `test/test-working-directory.sh`
  - Commands: `./test/test-working-directory.sh` and `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `hooks/lib/common.sh`
  - `SCRIPT_DIR=`
  - `cleanup()`
  - `trap cleanup`
  - JSON helpers
- **expected_improvements**:
  - Reduced duplication.
  - Easier maintenance of common utilities.

### REF-018 — Fix plugin name inconsistency

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `DX`
- **area**: `design`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **current_state_assessment**:
  - Plugin name mismatch: `double-shot-latte` in plugin.json vs `redbull` in repo name.
  - `CLAUDE_WORK_DIR` references `double-shot-latte`.
- **scores**:
  - impact: 2
  - effort: 1
  - expertise: 1
  - risk: 1
  - novelty: 1
- **priority_score**: 2.00
- **scope**:
  - `.claude-plugin/plugin.json`, `hooks/claude-judge-continuation.sh` (workdir reference).
- **implementation_steps**:
  1. Update `plugin.json` name field to `redbull`.
  2. Update `CLAUDE_WORK_DIR` reference from `double-shot-latte` to `redbull`.
  3. Verify plugin still installs and works correctly.
  4. Update any docs that reference the old name.
- **acceptance_criteria**:
  - [ ] Plugin name is consistent (`redbull` everywhere)
  - [ ] Plugin installs and works correctly
  - [ ] No behavior changes (only naming)
  - [ ] Docs updated if needed
- **test_plan**:
  - Level: manual verification
  - Location: `.claude-plugin/plugin.json`, `hooks/claude-judge-continuation.sh`
  - Commands: `/plugin install redbull@redbull-dev` (verify install works)
- **targets_search_tokens**:
  - `plugin.json`
  - `double-shot-latte`
  - `redbull`
  - `CLAUDE_WORK_DIR`
- **expected_improvements**:
  - Consistency across codebase.
  - Clearer plugin identity.

### REF-019 — Align docs naming + paths

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `DX`
- **area**: `design`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **current_state_assessment**:
  - `RELENG.md` and test harness reference `scripts/` while implementation lives under `hooks/`.
  - Inconsistent naming creates confusion.
- **scores**:
  - impact: 2
  - effort: 2
  - expertise: 1
  - risk: 1
  - novelty: 1
- **priority_score**: 1.00
- **scope**:
  - `RELENG.md`, `CLAUDE.md`, `README.md`, any other docs referencing `scripts/`.
- **implementation_steps**:
  1. Search all docs for `scripts/` references.
  2. Replace with `hooks/` where appropriate.
  3. Update any path examples or instructions.
  4. Ensure consistency across all documentation.
- **acceptance_criteria**:
  - [ ] All docs reference `hooks/` not `scripts/`
  - [ ] Path examples are correct
  - [ ] Documentation is consistent
- **test_plan**:
  - Level: documentation review
  - Location: `RELENG.md`, `CLAUDE.md`, `README.md`
  - Commands: Manual review, grep for `scripts/`
- **targets_search_tokens**:
  - `RELENG.md`
  - `scripts/`
  - plugin naming
  - remove `scripts/` references
- **expected_improvements**:
  - Clearer documentation.
  - Reduced confusion.

### REF-020 — Add optional structured debug logging

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `DX`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **current_state_assessment**:
  - No debug logging available for troubleshooting hook behavior.
  - Failures are hard to diagnose without visibility into decision flow.
- **scores**:
  - impact: 2
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 1.00
- **scope**:
  - Optional debug logging in `hooks/claude-judge-continuation.sh`.
- **implementation_steps**:
  1. Add `REDBULL_DEBUG=true` env var guard.
  2. Log structured debug info to stderr (timestamps, decision flow, throttle state).
  3. Ensure debug output doesn't interfere with JSON stdout.
  4. Document debug mode usage.
- **acceptance_criteria**:
  - [ ] Debug logging is optional (disabled by default)
  - [ ] Debug output goes to stderr (not stdout)
  - [ ] No impact on default behavior
  - [ ] No behavior changes verification: eval suite matches baseline
- **test_plan**:
  - Level: regression/integration
  - Location: `test/evals/`
  - Commands: `./test/evals/run-evals.sh` (default) and with debug enabled
- **targets_search_tokens**:
  - `DEBUG`
  - timestamps
  - stderr
  - structured fields
  - guarded by env var
- **expected_improvements**:
  - Better debugging experience.
  - Visibility into hook decision flow.

### REF-021 — Moonshot: modularize into `hooks/lib/*.sh` modules

- **kind**: `improvement`
- **category**: `Moonshot`
- **type**: `refactor`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-04`
- **experiment_category**: `moonshot`
- **small_experiment_(1–2h)**:
  - Extract only `emit_*` helpers and throttle helpers into `hooks/lib/` and `source` them, keeping the entrypoint unchanged.
- **success_metric**:
  - No diffs in emitted decisions across the full eval suite; script size and nesting reduced measurably (e.g., fewer top-level branches).
- **rollback_plan**:
  - Revert modularization and keep the best internal function refactors in a single file.
- **current_state_assessment**:
  - Single-file script couples unrelated concerns and discourages safe iteration.
  - Adding features like better logging/test seams increases complexity if everything stays inline.
- **scores**:
  - impact: 5
  - effort: 4
  - expertise: 4
  - risk: 3
  - novelty: 5
- **priority_score**: 1.25
- **scope**:
  - `hooks/claude-judge-continuation.sh` becomes an orchestrator.
  - New internal modules under `hooks/lib/` (e.g., `json.sh`, `throttle.sh`, `prompt.sh`, `emit.sh`, `claude-runner.sh`).
- **implementation_steps**:
  1. Design module boundaries (IO emitters, throttle, parsing, evaluator runner).
  2. Extract modules one at a time, validating after each extraction.
  3. Ensure `run-hook.cmd` still works (paths based on `${CLAUDE_PLUGIN_ROOT}`).
  4. Keep installation simple (no build, no extra deps); only source local files.
- **acceptance_criteria**:
  - [ ] Entrypoint behavior remains identical (stdin/stdout contract + decisions)
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Working directory recursion prevention remains intact
  - [ ] Modules are internal-only (no public API change)
- **test_plan**:
  - Level: full regression
  - Location: `test/evals/` + `test/test-working-directory.sh`
  - Commands: `./test/test-working-directory.sh` and `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `source `
  - `hooks/lib`
  - `emit_`
  - `throttle_`
  - `json.sh`, `prompt.sh`, `claude-runner.sh`
- **expected_improvements**:
  - Clear separation of concerns and maintainable internal architecture.
  - Easier future refactors without ballooning a single script.

---

## Rationale for Top 3

### REF-001: Repair eval harness hook script path (Priority 5.00)
**Highest impact-to-effort ratio.** The current eval suite is producing misleading results: it can "pass" STOP scenarios even when the hook script never ran. Fixing the harness restores confidence in every other refactor by making regressions observable immediately. This is a critical blocker for all other improvements.

### REF-002: Extract configuration constants (Priority 4.00)
**High impact, minimal effort.** Magic numbers like `300` (5-minute window), `3` (max continuations), and `10` (transcript lines) are scattered throughout the script, making it difficult to understand thresholds and tune behavior. Moving these to clearly-named constants at the script header improves readability, simplifies future tuning, and lays groundwork for optional config file pattern—all with trivial implementation.

### REF-003: Normalize decision + error output (Priority 3.00)
**Low risk, high consistency gain.** Some paths output JSON with `echo '{...}'` while others use `jq -n`, risking inconsistent escaping and format drift. Error paths don't have a consistent structure. A single emitter function (`emit_approve`, `emit_block`, `emit_error`) ensures all outputs are safely encoded and maintainable.

---

## Epics (Grouped by Theme)

### EPIC-01 — "Trustworthy Regression Harness"
**Goal**: Make tests reflect real hook behavior and fail loudly when the hook cannot be executed.

**Child tasks**: REF-001, REF-012, REF-013, REF-016

### EPIC-02 — "Simplify + Harden Hook Core"
**Goal**: Reduce complexity and standardize IO, without changing decisions.

**Child tasks**: REF-002, REF-003, REF-005, REF-006, REF-009, REF-010, REF-011

### EPIC-03 — "Developer Experience Improvements"
**Goal**: Improve maintainability, debuggability, and code quality.

**Child tasks**: REF-004, REF-007, REF-014, REF-015, REF-017, REF-018, REF-019, REF-020

### EPIC-04 — "Modular Architecture (Longer Horizon)"
**Goal**: Create clear internal seams for future maintenance while preserving a simple install story.

**Child tasks**: REF-008, REF-021

---

## Implementation Notes

### Prerequisites
- **REF-001 must be completed first** before any other refactoring can be safely validated
- All refactors must preserve hook I/O contract: `stdin JSON` → `stdout JSON`
- No new runtime dependencies (bash + jq + claude CLI only)
- Cross-platform compatibility via `run-hook.cmd` must be maintained

### Testing Strategy
- After REF-001: Full eval suite (`./test/evals/run-evals.sh`) should pass reliably
- Regression testing: All refactors must maintain 100% decision parity with baseline
- Working directory test: `./test/test-working-directory.sh` must continue to pass
- Performance: Hook latency should not increase measurably

### Risk Mitigation
- Small, incremental changes with validation after each step
- Preserve all existing behavior (no decision logic changes unless explicitly stated)
- Use feature flags or env vars for optional enhancements (debug logging, metrics)
- Document all changes in CHANGELOG.md

---

## Notes / Assumptions

- Existing eval suite (65 scenarios, 5 runs each) provides comprehensive regression coverage once REF-001 is fixed
- Performance refactoring (REF-005, REF-009, REF-015) may have minimal real-world impact given infrequent hook invocation, but improves code quality
- Moonshot REF-021 requires careful design to maintain single-file simplicity users expect from bash plugins
- No CI system is present in this repo; "DX/CI" ideas assume either local scripts or a future CI workflow (without changing runtime behavior)
- Plugin name fix (REF-018) has low risk since `double-shot-latte` is internal reference only, but improves consistency

