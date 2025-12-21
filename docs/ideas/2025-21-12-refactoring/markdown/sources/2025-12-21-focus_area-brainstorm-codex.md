# Refactoring Brainstorm (Codex): Redbull Plugin — Whole Project

Generated: 2025-12-21  
Focus area input: `focus_area` (appears to be a placeholder; treated as “project-wide”)

---

## 1) Focus Summary

### Purpose
Hook-based Claude Code plugin that intercepts **Stop** events and decides whether to **block** stopping (continue working) or **approve** stopping, using a secondary Claude instance for classification.

### Key Flows (main code paths)
1. **Stop hook entrypoint**: `hooks/claude-judge-continuation.sh` reads event JSON from stdin.
2. **Recursion prevention**: `CLAUDE_HOOK_JUDGE_MODE=true` short-circuits to allow stop.
3. **Throttle**: `/tmp/.claude-continue-throttle-<session>` limits continuations.
4. **Transcript context**: reads last N NDJSON lines from `transcript_path`, wraps into JSON array.
5. **Claude evaluation**: `claude --print --output-format json --json-schema ...` returns structured output.
6. **Decision mapping**: `should_continue=true` → `{decision:"block"}` else `{decision:"approve"}`.

### Current Technical Debt Indicators (evidence-based)
- **Regression harness is not trustworthy today**: `test/evals/run-evals.sh` points to a non-existent hook script path (`../../scripts/claude-judge-continuation.sh`), causing many scenarios to “pass” incorrectly when the hook returns `{"decision":"error"}`. (Observed: 29/65 failures when running the suite; failures align with `expected_decision=true` cases because “error” is treated as STOP.)
- **Monolithic bash script**: `hooks/claude-judge-continuation.sh` mixes parsing, throttling, prompt construction, command execution, and output formatting in one routine.
- **High external-process churn**: repeated `jq` invocations and multiple `cat/cut/tr/tail` spawns (minor, but in latency-sensitive hooks this adds up).
- **Magic numbers and hard-coded policy**: throttle window, max continuations, transcript line count, model name, and workdir are inline.
- **Inconsistent JSON output construction**: some paths `echo` raw JSON strings, others use `jq -n` (risk of escaping issues + harder to standardize).
- **Docs drift**: `RELENG.md` and test harness reference `scripts/` while implementation lives under `hooks/`.

### Constraints
- **No external behavior changes**: hook I/O contract must remain `stdin JSON` → `stdout JSON` with same decision semantics.
- **Keep bash + jq + claude CLI**: project is intentionally buildless; cross-platform wrapper must remain functional.
- **Deterministic + fast**: hook should remain quick; any additional work should be optional/guarded.

### Risks / Unknowns
- Small changes to prompt/evaluator integration can alter classification outcomes; refactors must be validated via eval suite (once fixed) and targeted regression tests.
- Throttle behavior relies on `/tmp` semantics; refactor must preserve file naming/sanitization and time window logic.

---

## 2) Candidate Brainstorm (Unfiltered, max 20)

1. **Repair eval harness hook script path** (test correctness; stop “error == pass” masking).
2. **Centralize and parameterize script paths** (single source of truth for hook location used by tests + docs).
3. **Extract configuration constants** (max continuations, window seconds, transcript lines, model, workdir).
4. **Consolidate event JSON parsing** (single `jq` parse → shell variables; reduce repeated subprocesses).
5. **Normalize output + error handling** (single `emit_decision` / `emit_error` helper; consistent escaping).
6. **Extract throttle logic into focused functions** (read/write/should_throttle/clear; reduce nesting).
7. **Reduce external command dependencies** (replace `tr` + `cut` parsing with bash parameter expansion; fewer processes).
8. **Refactor into “functional core / imperative shell”** (pure-ish functions for decision flow; IO at edges; better testability).
9. **Add deterministic offline eval mode** (mock `claude` runner for tests; keep true integration mode as opt-in).
10. **Introduce prompt templating** (prompt in file + renderer; easier to iterate without touching logic).
11. **Add snapshot tests for prompt + schema** (ensure prompt changes are intentional and reviewable).
12. **Improve transcript extraction robustness** (validate NDJSON lines; handle empty/invalid lines consistently).
13. **Tighten input validation boundaries** (validate event JSON shape; fail closed with clear reason).
14. **Add optional debug logging with structured fields** (guarded by env var; never on by default).
15. **Moonshot: split into `hooks/lib/*.sh` modules** (throttle/json/prompt/claude-runner modules; keep entrypoint thin).
16. **Add ShellCheck in CI (or local script)** (DX: catch quoting/nits; non-behavioral).
17. **Align docs naming + paths** (remove `scripts/` references; ensure README/CLAUDE/RELENG consistent).

---

## 3) Score All Candidates

Scales: impact/effort/expertise/risk/novelty = 1–5 (integers).  
`priority_score = round(impact/effort, 2)`

| Cand. | Title | Category | Type | Area | Impact | Effort | Exp. | Risk | Novelty | Priority | Targets / Search |
|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---|
| CAND-01 | Repair eval harness hook script path | Conventional | testing | build | 5 | 1 | 2 | 1 | 1 | 5.00 | `test/evals/run-evals.sh`, `HOOK_SCRIPT=`, `../../scripts/` |
| CAND-02 | Centralize and parameterize script paths | Conventional | DX | build | 4 | 2 | 2 | 1 | 2 | 2.00 | `RELENG.md`, `CLAUDE.md`, `run-evals.sh`, `hooks/` |
| CAND-03 | Extract configuration constants | Conventional | refactor | infra | 4 | 1 | 1 | 1 | 1 | 4.00 | `MAX`, `300`, `tail -n 10`, `--model haiku` |
| CAND-04 | Consolidate event JSON parsing | Conventional | perf | infra | 4 | 2 | 2 | 2 | 2 | 2.00 | `echo \"$EVENT\" | jq`, `STOP_HOOK_ACTIVE`, `TRANSCRIPT_PATH` |
| CAND-05 | Normalize output + error handling | Conventional | refactor | infra | 3 | 1 | 2 | 1 | 1 | 3.00 | `echo '{\"decision\"`, `jq -n --arg reason` |
| CAND-06 | Extract throttle logic into focused functions | Conventional | refactor | infra | 4 | 2 | 2 | 2 | 1 | 2.00 | `THROTTLE_FILE`, `CONTINUE_COUNT`, `TIME_SINCE_LAST` |
| CAND-07 | Reduce external command dependencies | Conventional | perf | infra | 3 | 2 | 2 | 2 | 2 | 1.50 | `tr '/' '_'`, `cut -d:` |
| CAND-08 | Refactor into functional core / imperative shell | Creative | refactor | infra | 4 | 2 | 3 | 2 | 4 | 2.00 | `EVENT=$(cat)`, `CLAUDE_RESPONSE=`, decision branching |
| CAND-09 | Add deterministic offline eval mode | Creative | testing | build | 4 | 3 | 3 | 2 | 4 | 1.33 | `PATH` mocking, `CLAUDE_HOOK_JUDGE_MODE`, `claude --print` |
| CAND-10 | Introduce prompt templating | Creative | DX | infra | 3 | 2 | 2 | 2 | 4 | 1.50 | `EVALUATION_PROMPT=`, `SYSTEM_PROMPT=` |
| CAND-11 | Add snapshot tests for prompt + schema | Conventional | testing | build | 3 | 2 | 2 | 1 | 2 | 1.50 | prompt text, `JSON_SCHEMA=` |
| CAND-12 | Improve transcript extraction robustness | Conventional | refactor | infra | 3 | 2 | 2 | 2 | 1 | 1.50 | `tail -n`, `jq -s`, NDJSON handling |
| CAND-13 | Tighten input validation boundaries | Conventional | refactor | infra | 3 | 2 | 2 | 2 | 1 | 1.50 | `jq -r '.transcript_path'`, `session_id` |
| CAND-14 | Add optional structured debug logging | Conventional | DX | infra | 2 | 2 | 2 | 1 | 2 | 1.00 | `DEBUG`, timestamps, stderr |
| CAND-15 | Moonshot: split into `hooks/lib/*.sh` modules | Moonshot | refactor | infra | 5 | 4 | 4 | 3 | 5 | 1.25 | `source`, `hooks/lib`, `emit_*`, `throttle_*` |
| CAND-16 | Add ShellCheck in CI (or local script) | Conventional | DX | CI | 3 | 3 | 2 | 1 | 1 | 1.00 | `shellcheck`, `hooks/*.sh`, `test/*.sh` |
| CAND-17 | Align docs naming + paths | Conventional | DX | design | 2 | 2 | 1 | 1 | 1 | 1.00 | `RELENG.md`, `scripts/`, plugin naming |

---

## 4) Select Top 5–10 (by Priority + Tie-breakers)

Tie-breakers applied: lower risk → lower expertise → higher impact.

### Top Refactoring Tasks (Ranked)

| # | ID | Title | Cat. | Impact | Effort | Exp. | Risk | Novelty | Priority | Targets / Search |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | REF-001 | Repair eval harness to call the real hook script | Conventional | 5 | 1 | 2 | 1 | 1 | 5.00 | `test/evals/run-evals.sh`, `HOOK_SCRIPT=`, `../../scripts/` |
| 2 | REF-002 | Extract policy constants into named configuration variables | Conventional | 4 | 1 | 1 | 1 | 1 | 4.00 | `hooks/claude-judge-continuation.sh`, `300`, `3`, `tail -n 10`, `--model` |
| 3 | REF-003 | Normalize decision + error output via a single emitter | Conventional | 3 | 1 | 2 | 1 | 1 | 3.00 | `echo '{\"decision\"`, `jq -n --arg reason`, `decision` |
| 4 | REF-004 | Consolidate event parsing to reduce repeated `jq` subprocesses | Conventional | 4 | 2 | 2 | 2 | 2 | 2.00 | `echo \"$EVENT\" | jq`, `STOP_HOOK_ACTIVE`, `TRANSCRIPT_PATH` |
| 5 | REF-005 | Extract throttle policy into focused functions and flatten control flow | Conventional | 4 | 2 | 2 | 2 | 1 | 2.00 | `THROTTLE_FILE`, `CONTINUE_COUNT`, `TIME_SINCE_LAST`, `rm -f` |
| 6 | REF-006 | Refactor hook into functional core + injected runner for testability | Creative | 4 | 2 | 3 | 2 | 4 | 2.00 | `CLAUDE_RESPONSE=`, `CURRENT_TIME=`, decision branching |
| 7 | REF-007 | Introduce prompt templating + snapshot checks (guarded, no behavior change) | Creative | 3 | 2 | 2 | 2 | 4 | 1.50 | `EVALUATION_PROMPT=`, `SYSTEM_PROMPT=`, `JSON_SCHEMA=` |
| 8 | REF-008 | Moonshot: modularize into `hooks/lib/*.sh` while preserving entrypoint behavior | Moonshot | 5 | 4 | 4 | 3 | 5 | 1.25 | `source`, `hooks/lib`, `emit_*`, `throttle_*` |

---

## 5) Create Epics (2–5)

### EPIC-01 — “Trustworthy Regression Harness”
- Goal: Make tests reflect real hook behavior and fail loudly when the hook cannot be executed.
- Child tasks: `REF-001`, `REF-006`, `REF-007`

### EPIC-02 — “Simplify + Harden Hook Core”
- Goal: Reduce complexity and standardize IO, without changing decisions.
- Child tasks: `REF-002`, `REF-003`, `REF-004`, `REF-005`

### EPIC-03 — “Modular Architecture (Longer Horizon)”
- Goal: Create clear internal seams for future maintenance while preserving a simple install story.
- Child tasks: `REF-008`

---

## Rationale for #1

`REF-001` has the best impact/effort ratio because the current eval suite is producing misleading results: it can “pass” STOP scenarios even when the hook script never ran. Fixing the harness restores confidence in every other refactor by making regressions observable immediately.

---

## Detailed Refactoring Tasks (Ticket-Ready)

### REF-001 — Repair eval harness to call the real hook script

- kind: `improvement`
- category: `Conventional`
- type: `testing`
- area: `build`
- owner_role: `QA`
- parent_epic_id: `EPIC-01`
- current_state_assessment:
  - `test/evals/run-evals.sh` references `../../scripts/claude-judge-continuation.sh` but the real hook script is `hooks/claude-judge-continuation.sh`.
  - The harness converts execution failures into `{"decision":"error"}`, which incorrectly “passes” scenarios expecting STOP and obscures real regressions.
- scores:
  - impact: 5
  - effort: 1
  - expertise: 2
  - risk: 1
  - novelty: 1
- priority_score: 5.00
- scope:
  - Update `test/evals/run-evals.sh` to point at the correct hook entrypoint.
  - Adjust harness failure handling so “hook execution failed” fails the scenario (rather than mapping to STOP silently).
- implementation_steps:
  1. Replace `HOOK_SCRIPT=.../../../scripts/...` with `.../../../hooks/claude-judge-continuation.sh`.
  2. If hook execution fails (non-zero or invalid JSON), mark the run as failed with a clear error message.
  3. Add a preflight check that `HOOK_SCRIPT` exists + is executable; fail fast otherwise.
  4. Update `RELENG.md` and any docs that reference the old `scripts/` path (if needed to keep docs consistent).
- acceptance_criteria:
  - [ ] `./test/evals/run-evals.sh` fails fast if the hook script path is wrong
  - [ ] Hook execution failures fail scenarios (no silent “error == stop” masking)
  - [ ] Existing scenario expectations remain unchanged
  - [ ] No behavior changes in the hook itself (verification: the hook script is not modified by this ticket)
- test_plan:
  - Level: integration (test harness)
  - Location: `test/evals/run-evals.sh`
  - Command: `./test/evals/run-evals.sh`
- targets_search_tokens:
  - `HOOK_SCRIPT=`
  - `../../scripts/claude-judge-continuation.sh`
  - `hook_output=`
  - `{"decision": "error"}`
- expected_improvements:
  - Restore confidence in refactors by making regressions observable.
  - Reduce time wasted debugging false positives/negatives.

### REF-002 — Extract policy constants into named configuration variables

- kind: `improvement`
- category: `Conventional`
- type: `refactor`
- area: `infra`
- owner_role: `Fullstack`
- parent_epic_id: `EPIC-02`
- current_state_assessment:
  - Magic numbers and policy knobs are embedded throughout the script (`3`, `300`, `tail -n 10`, model name).
  - Threshold semantics are harder to review and tune without risking accidental drift.
- scores:
  - impact: 4
  - effort: 1
  - expertise: 1
  - risk: 1
  - novelty: 1
- priority_score: 4.00
- scope:
  - `hooks/claude-judge-continuation.sh` only.
- implementation_steps:
  1. Add constants near the top (e.g., `MAX_CONTINUATIONS`, `THROTTLE_WINDOW_SECONDS`, `TRANSCRIPT_CONTEXT_LINES`, `CLAUDE_MODEL`, `CLAUDE_WORK_DIR`).
  2. Replace inline literals with those constants.
  3. Ensure prompt text references remain unchanged (only variable substitution for counts where safe).
  4. Run regression tests after `REF-001` is complete.
- acceptance_criteria:
  - [ ] All policy values exist as clearly-named variables in one place
  - [ ] No logic changes (only replacing literals with variables)
  - [ ] No behavior changes verification: `./test/evals/run-evals.sh` results unchanged vs baseline
  - [ ] Working directory test still passes: `./test/test-working-directory.sh`
- test_plan:
  - Level: regression/integration
  - Location: `test/evals/` + `test/test-working-directory.sh`
  - Commands: `./test/test-working-directory.sh` and `./test/evals/run-evals.sh`
- targets_search_tokens:
  - `300`
  - `-ge 3`
  - `tail -n 10`
  - `--model haiku`
  - `~/.claude/double-shot-latte`
- expected_improvements:
  - Easier reviews and safer future tuning.
  - Clearer policy intent; fewer accidental inconsistencies.

### REF-003 — Normalize decision + error output via a single emitter

- kind: `improvement`
- category: `Conventional`
- type: `refactor`
- area: `infra`
- owner_role: `Fullstack`
- parent_epic_id: `EPIC-02`
- current_state_assessment:
  - Some paths output JSON with `echo '{...}'` while others use `jq -n`, risking inconsistent escaping and format drift.
  - Error paths don’t have a consistent structure (harder to grep and reason about).
- scores:
  - impact: 3
  - effort: 1
  - expertise: 2
  - risk: 1
  - novelty: 1
- priority_score: 3.00
- scope:
  - `hooks/claude-judge-continuation.sh` only.
- implementation_steps:
  1. Create helper functions: `emit_approve <reason>`, `emit_block <reason>`, `emit_error <reason>` (or a single `emit_decision <decision> <reason>`).
  2. Replace all `echo '{...}'` JSON paths with the helper(s) using `jq -n --arg`.
  3. Ensure reasons remain semantically identical (same strings, just safely encoded).
  4. Keep stdout-only behavior; avoid extra noise unless explicitly requested by env flag.
- acceptance_criteria:
  - [ ] All outputs are produced via one helper path (no raw JSON `echo` remains)
  - [ ] Output JSON shape remains compatible with current hook contract
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Failure reasons remain readable and stable for logging/debugging
- test_plan:
  - Level: regression/integration
  - Location: `test/evals/` + manual pipe test
  - Commands: `./test/evals/run-evals.sh` and `echo '{...}' | ./hooks/claude-judge-continuation.sh`
- targets_search_tokens:
  - `echo '{\"decision\"`
  - `jq -n --arg reason`
  - `"decision": "approve"`
  - `"decision": "block"`
- expected_improvements:
  - Lower risk of malformed JSON.
  - Easier future changes to output format without missing branches.

### REF-004 — Consolidate event parsing to reduce repeated `jq` subprocesses

- kind: `improvement`
- category: `Conventional`
- type: `perf`
- area: `infra`
- owner_role: `Fullstack`
- parent_epic_id: `EPIC-02`
- current_state_assessment:
  - Event fields are extracted via multiple `jq -r` calls, each spawning a new process.
  - This increases latency and adds cognitive overhead (values can diverge if parsing changes).
- scores:
  - impact: 4
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 2
- priority_score: 2.00
- scope:
  - `hooks/claude-judge-continuation.sh` parsing section.
- implementation_steps:
  1. Parse all needed fields from `$EVENT` with a single `jq` invocation (e.g., output TSV/JSON and read into vars).
  2. Validate parsed values early (empty transcript path, missing session id).
  3. Keep default values identical to today (`// false`, `// ""`, etc.).
  4. Re-run evals and working-dir test to confirm no drift.
- acceptance_criteria:
  - [ ] Only one `jq` invocation is used to parse the incoming event JSON
  - [ ] Default values match current behavior
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Hook still handles missing fields gracefully
- test_plan:
  - Level: regression/integration
  - Location: `test/evals/` + manual smoke tests
  - Command: `./test/evals/run-evals.sh`
- targets_search_tokens:
  - `echo \"$EVENT\" | jq -r`
  - `.stop_hook_active`
  - `.transcript_path`
  - `.session_id`
- expected_improvements:
  - Fewer subprocesses → lower hook latency.
  - Clearer boundary for event parsing and validation.

### REF-005 — Extract throttle policy into focused functions and flatten control flow

- kind: `improvement`
- category: `Conventional`
- type: `refactor`
- area: `infra`
- owner_role: `Fullstack`
- parent_epic_id: `EPIC-02`
- current_state_assessment:
  - Throttle behavior is implemented inline with multiple nested conditionals and duplicated file parsing logic.
  - Session id sanitization and throttle file parsing use extra external commands (`tr`, `cut`).
- scores:
  - impact: 4
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 1
- priority_score: 2.00
- scope:
  - Throttle-related logic in `hooks/claude-judge-continuation.sh`.
- implementation_steps:
  1. Extract throttle helpers: `throttle_file_for_session`, `throttle_read`, `throttle_write`, `throttle_should_force_stop`, `throttle_clear`.
  2. Replace `tr '/' '_'` with bash substitution (same output).
  3. Replace `cut -d:` parsing with safe bash parsing (`IFS=: read -r ...`).
  4. Flatten nested conditionals with early returns/guards.
- acceptance_criteria:
  - [ ] Throttle logic is isolated behind small functions with single responsibilities
  - [ ] Throttle file format and semantics are unchanged
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Throttle files are still cleared on legitimate stops
- test_plan:
  - Level: regression/integration + targeted throttle cases
  - Location: `test/evals/scenarios/` (add/adjust only if missing throttle coverage)
  - Command: `./test/evals/run-evals.sh`
- targets_search_tokens:
  - `THROTTLE_FILE=`
  - `/tmp/.claude-continue-throttle-`
  - `cut -d:`
  - `tr '/' '_'`
  - `TIME_SINCE_LAST`
- expected_improvements:
  - Lower complexity and safer future changes to throttle policy.
  - Fewer external processes (small perf gain).

### REF-006 — Refactor hook into functional core + injected runner for testability

- kind: `improvement`
- category: `Creative`
- type: `refactor`
- area: `infra`
- owner_role: `Fullstack`
- parent_epic_id: `EPIC-01`
- experiment category: `creative`
- small_experiment_(1–2h):
  - Extract a `run_claude_evaluator` function and make it injectable via env var (e.g., `CLAUDE_CMD=claude`), then update `test/evals` to swap in a mock claude for one scenario.
- success_metric:
  - One scenario can run deterministically without network/claude, while the default path remains unchanged.
- rollback_plan:
  - Revert env-injection and keep only internal function extraction (no test changes).
- current_state_assessment:
  - Hook is difficult to unit test because it hardcodes time (`date +%s`) and execution (`claude ...`) at call sites.
  - Most failures require full integration runs to diagnose.
- scores:
  - impact: 4
  - effort: 2
  - expertise: 3
  - risk: 2
  - novelty: 4
- priority_score: 2.00
- scope:
  - `hooks/claude-judge-continuation.sh` refactor into functions + injectable seams.
  - `test/evals/` minimal harness support for mock runner (optional).
- implementation_steps:
  1. Introduce “providers”: `now_epoch_seconds`, `read_event`, `read_transcript_context`, `run_evaluator`, `map_evaluator_to_decision`.
  2. Default providers use existing commands; allow overriding with env vars for tests (`CLAUDE_BIN`, `NOW_BIN`, etc.).
  3. Keep output contract identical.
  4. Add 1–2 targeted tests that run in offline mode to validate the seam.
- acceptance_criteria:
  - [ ] Default behavior remains unchanged (same decisions for same transcripts)
  - [ ] No behavior changes verification: eval suite matches baseline in “real claude” mode
  - [ ] At least one deterministic test can run with a mocked evaluator
  - [ ] No new runtime dependencies introduced
- test_plan:
  - Level: regression/integration + deterministic harness
  - Location: `test/evals/` + potentially new minimal fixture(s)
  - Commands: `./test/evals/run-evals.sh` (real mode) and `./test/evals/run-evals.sh` (mock mode via env vars, if added)
- targets_search_tokens:
  - `date +%s`
  - `claude --print`
  - `CLAUDE_RESPONSE=`
  - `EVALUATION_RESULT=`
- expected_improvements:
  - Faster debugging and safer refactors due to testable seams.
  - Enables future changes (prompt tuning, perf) with less risk.

### REF-007 — Introduce prompt templating + snapshot checks (guarded, no behavior change)

- kind: `improvement`
- category: `Creative`
- type: `DX`
- area: `infra`
- owner_role: `Fullstack`
- parent_epic_id: `EPIC-01`
- experiment category: `creative`
- small_experiment_(1–2h):
  - Move prompt text into a file (or heredoc function) and add a snapshot test that asserts the rendered prompt matches an expected fixture for one scenario.
- success_metric:
  - Prompt changes become reviewable diffs without touching throttle/IO logic.
- rollback_plan:
  - Keep prompt in-script but refactor into a single heredoc function; drop snapshot testing.
- current_state_assessment:
  - Prompt and schema live inline in the main script; edits are high-risk and hard to review.
  - There is no guardrail ensuring accidental prompt edits are caught.
- scores:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 4
- priority_score: 1.50
- scope:
  - Prompt/schema construction in `hooks/claude-judge-continuation.sh`.
  - A small snapshot check in `test/` (if feasible without new deps).
- implementation_steps:
  1. Move prompt construction into `build_evaluation_prompt <recent_context_json>`.
  2. Keep prompt bytes identical initially (no wording changes).
  3. Add a snapshot fixture for the generated prompt (or schema) for one fixed transcript.
  4. Document the safe workflow for prompt edits (update fixture + run eval suite).
- acceptance_criteria:
  - [ ] Prompt content is byte-for-byte identical before/after refactor (initial cut)
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Snapshot check fails when prompt changes unexpectedly
  - [ ] No new runtime dependencies introduced
- test_plan:
  - Level: regression + snapshot
  - Location: `test/` (snapshot fixture) + `test/evals/`
  - Commands: snapshot check (new script) and `./test/evals/run-evals.sh`
- targets_search_tokens:
  - `EVALUATION_PROMPT=`
  - `SYSTEM_PROMPT=`
  - `JSON_SCHEMA=`
- expected_improvements:
  - Safer prompt iteration and clearer reviews.
  - Reduced accidental behavior drift during refactors.

### REF-008 — Moonshot: modularize into `hooks/lib/*.sh` while preserving entrypoint behavior

- kind: `improvement`
- category: `Moonshot`
- type: `refactor`
- area: `infra`
- owner_role: `Fullstack`
- parent_epic_id: `EPIC-03`
- experiment category: `moonshot`
- small_experiment_(1–2h):
  - Extract only `emit_*` helpers and throttle helpers into `hooks/lib/` and `source` them, keeping the entrypoint unchanged.
- success_metric:
  - No diffs in emitted decisions across the full eval suite; script size and nesting reduced measurably (e.g., fewer top-level branches).
- rollback_plan:
  - Revert modularization and keep the best internal function refactors in a single file.
- current_state_assessment:
  - Single-file script couples unrelated concerns and discourages safe iteration.
  - Adding features like better logging/test seams increases complexity if everything stays inline.
- scores:
  - impact: 5
  - effort: 4
  - expertise: 4
  - risk: 3
  - novelty: 5
- priority_score: 1.25
- scope:
  - `hooks/claude-judge-continuation.sh` becomes an orchestrator.
  - New internal modules under `hooks/lib/` (e.g., `json.sh`, `throttle.sh`, `prompt.sh`, `emit.sh`, `claude-runner.sh`).
- implementation_steps:
  1. Design module boundaries (IO emitters, throttle, parsing, evaluator runner).
  2. Extract modules one at a time, validating after each extraction.
  3. Ensure `run-hook.cmd` still works (paths based on `${CLAUDE_PLUGIN_ROOT}`).
  4. Keep installation simple (no build, no extra deps); only source local files.
- acceptance_criteria:
  - [ ] Entrypoint behavior remains identical (stdin/stdout contract + decisions)
  - [ ] No behavior changes verification: eval suite matches baseline
  - [ ] Working directory recursion prevention remains intact
  - [ ] Modules are internal-only (no public API change)
- test_plan:
  - Level: full regression
  - Location: `test/evals/` + `test/test-working-directory.sh`
  - Commands: `./test/test-working-directory.sh` and `./test/evals/run-evals.sh`
- targets_search_tokens:
  - `source `
  - `hooks/lib`
  - `emit_`
  - `throttle_`
- expected_improvements:
  - Clear separation of concerns and maintainable internal architecture.
  - Easier future refactors without ballooning a single script.

---

## Notes / Assumptions

- `./test/evals/run-evals.sh` is intended to be the primary regression proof, but it must be repaired first (see `REF-001`).
- No CI system is present in this repo; “DX/CI” ideas assume either local scripts or a future CI workflow (without changing runtime behavior).

