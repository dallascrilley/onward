# Refactoring Brainstorm: Redbull Plugin (Full Codebase)

Generated: 2025-12-21

## Focus Summary

### Purpose
The Redbull plugin prevents Claude Code from stopping prematurely by using a secondary Claude Haiku instance to evaluate whether continuation is appropriate. It intercepts Stop events, extracts recent transcript context, and returns structured decisions.

### Key Flows
1. **Stop Hook Interception**: `hooks/claude-judge-continuation.sh` receives Stop events via stdin JSON
2. **Recursion Prevention**: `CLAUDE_HOOK_JUDGE_MODE=true` env var prevents infinite loops
3. **Throttling**: `/tmp/.claude-continue-throttle-*` files limit to 3 continuations per 5 minutes
4. **Evaluation**: Claude Haiku evaluates transcript with structured JSON schema output
5. **Decision Return**: Returns `{"decision": "block"}` (continue) or `{"decision": "approve"}` (stop)

### Technical Debt Indicators
- **Monolithic Script**: 155-line bash script handling multiple responsibilities (input parsing, throttling, evaluation, output formatting)
- **Repeated jq Invocations**: 9+ separate jq calls, each spawning a new process
- **Hardcoded Values**: Magic numbers (3 continuations, 5 minutes, 10 transcript lines) scattered throughout
- **Tight Coupling**: Throttle logic, evaluation prompt, and decision logic all intertwined
- **Limited Testability**: No unit testing for individual functions; relies on full integration tests
- **Inconsistent Naming**: Plugin name mismatch (`redbull` in plugin.json vs `redbull` in repo name)
- **Missing Linter**: No shellcheck or bash linting configured despite AGENTS.md noting this gap

### Constraints
- Must remain a pure Bash plugin (no build step, no TypeScript)
- Claude CLI dependency for evaluation
- Hook system contract (stdin JSON, stdout JSON, exit codes)
- Cross-platform via `run-hook.cmd` wrapper

### Risks/Unknowns
- Refactoring evaluation prompt could change decision accuracy (need eval suite validation)
- Throttle state stored in /tmp may be ephemeral on some systems
- No metrics on hook latency impact

---

## Candidate Brainstorm (Unfiltered - 20 candidates)

1. **Extract Configuration Constants** - Move magic numbers to config variables at script top
2. **Consolidate jq Invocations** - Batch JSON parsing into single jq call with multiple outputs
3. **Extract Throttle Logic** - Separate throttle.sh module with read/write/check functions
4. **Extract Evaluation Prompt** - Move prompt text to separate file for easier iteration
5. **Add Shellcheck Linting** - Configure shellcheck CI and fix violations
6. **Fix Plugin Name Inconsistency** - Rename plugin.json name from `redbull` to `redbull`
7. **Extract Decision Output Function** - Deduplicate JSON output formatting
8. **Add Function Documentation** - Add bash function docs for each logical section
9. **Introduce Dependency Injection for Testing** - Allow mocking claude CLI in tests
10. **Create Evaluation Prompt Template System** - Enable A/B testing different prompts
11. **Extract Input Validation** - Separate validation logic into reusable functions
12. **Add Structured Logging** - Consistent debug logging with timestamps
13. **Optimize Transcript Extraction** - Use single jq operation instead of tail + jq
14. **Create Hook Library Module** - Shared utilities for hook scripts (JSON helpers, validation)
15. **Add Performance Metrics** - Track and log hook execution time
16. **Implement Config File Support** - Optional `.redbull.json` for per-project overrides
17. **Reduce eval Script Duplication** - Extract shared test utilities
18. **Add Pre-commit Hook for Shellcheck** - Prevent regressions
19. **Document Hook Input/Output Contract** - Formal specification for hook interface
20. **Create Plugin Settings Integration** - Use `.claude/redbull.local.md` pattern

---

## Top Refactoring Tasks (Ranked)

| # | ID | Title | Cat. | Impact | Effort | Exp. | Risk | Novelty | Priority | Targets / Search |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | REF-001 | Extract Configuration Constants to Script Header | Conventional | 4 | 1 | 1 | 1 | 1 | 4.00 | `hooks/claude-judge-continuation.sh`, `300`, `3`, `10` |
| 2 | REF-002 | Consolidate jq Invocations into Single Parse Call | Conventional | 4 | 2 | 2 | 2 | 2 | 2.00 | `jq -r`, `echo "$EVENT" \| jq`, `TRANSCRIPT_PATH` |
| 3 | REF-003 | Extract Throttle Logic to Separate Module | Creative | 4 | 2 | 2 | 2 | 3 | 2.00 | `THROTTLE_FILE`, `CONTINUE_COUNT`, `TIME_SINCE_LAST` |
| 4 | REF-004 | Add Shellcheck Linting with CI Integration | Conventional | 3 | 1 | 1 | 1 | 1 | 3.00 | `*.sh`, `.shellcheckrc`, `lint:` |
| 5 | REF-005 | Fix Plugin Name Inconsistency | Conventional | 2 | 1 | 1 | 1 | 1 | 2.00 | `plugin.json`, `redbull`, `CLAUDE_WORK_DIR` |
| 6 | REF-006 | Extract Decision Output Formatting Function | Conventional | 3 | 1 | 1 | 1 | 1 | 3.00 | `jq -n --arg reason`, `"decision"`, `echo '{"decision"` |
| 7 | REF-007 | Create Evaluation Prompt Template System | Creative | 4 | 3 | 3 | 3 | 4 | 1.33 | `EVALUATION_PROMPT=`, `prompts/`, `--system-prompt` |
| 8 | REF-008 | Implement Architectural Separation (Hook Library) | Moonshot | 5 | 4 | 3 | 3 | 5 | 1.25 | `lib/`, `source`, `hook-utils.sh` |
| 9 | REF-009 | Add Performance Timing Instrumentation | Conventional | 3 | 2 | 2 | 1 | 2 | 1.50 | `date +%s`, `HOOK_START_TIME`, `HOOK_DURATION` |
| 10 | REF-010 | Extract Input Validation Functions | Conventional | 3 | 2 | 2 | 2 | 2 | 1.50 | `[ -z "$TRANSCRIPT_PATH" ]`, `validate_input` |

---

## Rationale for #1 Pick

**REF-001: Extract Configuration Constants** delivers the highest impact-to-effort ratio (4.00) with minimal risk. Currently, magic numbers like `300` (5-minute window), `3` (max continuations), and `10` (transcript lines) are scattered throughout the script, making it difficult to understand thresholds and tune behavior. Moving these to clearly-named constants at the script header (`MAX_CONTINUATIONS=3`, `THROTTLE_WINDOW_SECONDS=300`, `TRANSCRIPT_CONTEXT_LINES=10`) improves readability, simplifies future tuning, and lays groundwork for the optional config file pattern—all with a trivial 15-minute implementation.

---

## Notes / Assumptions

- Existing eval suite (65 scenarios, 5 runs each) provides comprehensive regression coverage for refactoring safety
- Performance refactoring (REF-002, REF-009) may have minimal real-world impact given infrequent hook invocation
- Plugin name fix (REF-005) has low risk since `redbull` is internal reference only
- Moonshot REF-008 requires careful design to maintain single-file simplicity users expect from bash plugins
