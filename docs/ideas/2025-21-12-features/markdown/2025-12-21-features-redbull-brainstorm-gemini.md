# Brainstorm: Features for Redbull (Redbull for Claude Code)

## Focus Summary

**Purpose:** Redbull (Redbull for Claude Code) is a Claude Code plugin that prevents premature stops by using a secondary "Judge" Claude instance to evaluate if work should continue.
**Key Flows:** Intercept stop event -> Extract transcript -> Judge (LLM) evaluates -> Block or Allow stop -> Throttle checks.
**Constraints:** Bash-based, relies on `claude` CLI, stateless (except temp files), time-based throttling (3/5min).
**Risks/Unknowns:** "Haiku" model costs/latency, false positives (forcing continuation when user *wants* to stop), user lack of visibility into *why* it acted.

---

## Candidate Brainstorm (Unfiltered)

1.  **Explain Last Decision:** A CLI command to show the judge's reasoning for the last intervention.
2.  **Smart Throttle Config:** CLI tools to view current throttle status and custom configure limits (e.g., 5/10min).
3.  **Project-Specific Rules:** Load `.doubleshot.rules` or `.redbull.md` from the repo to inject custom prompt instructions (e.g., "Always continue builds").
4.  **Configurable Judge Model:** Support switching to `claude-3-5-sonnet` (smarter) or `claude-3-haiku` (faster) via env var.
5.  **Desktop Notifications:** System notification (Toast) when auto-continuation triggers, so the user knows why it didn't stop.
6.  **Local LLM Adapter:** Support Ollama/Llama 3 locally for free/private judging.
7.  **Adaptive Learning Loop:** Detect if user kills the process immediately after continuation, and add that context to a "negative examples" exclusion list.
8.  **Dry Run Mode:** Log what the judge *would* have done without actually blocking the stop.
9.  **Cost Tracker:** Estimate and display the cost incurred by the extra judge calls.
10. **Global specific ignore:** "Never continue" regex list to bypass LLM for certain file patterns or output strings.
11. **"One More Shot":** A slash command to manually invoke the judge if Claude stopped and you didn't want it to.
12. **Status Bar Indicator:** (Hard in pure CLI) but maybe a modified prompt symbol if `redbull` is active.
13. **JSON Output Log:** Structured logging of all decisions for analytics.
14. **Personality settings:** "Aggressive" vs "Passive" modes that adjust the system prompt temperature/instructions.
15. **Git-aware safety:** Only continue if the git working tree is clean (or dirty, depending on pref).
16. **Task progress bar:** LLM guesses % completion and continues if < 100%.
17. **Dependency check:** Auto-install `jq` or `ollama` if missing.
18. **Auto-update:** Self-updating script.
19. **Context Window slider:** Configurable number of lines (10-50) to send to judge.
20. **Multi-turn debate:** Judge asks a 2nd judge to verify (too slow/costly).

---

## Top Features (Ranked)

| # | ID | Title | Cat. | Impact | Effort | Exp. | Risk | Novelty | Priority | Targets / Search |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|---|
| 1 | FEAT-001 | Explain Last Decision | Conventional | 4 | 1 | 2 | 1 | 2 | 4.00 | `redbull explain`, `log`, `reasoning` |
| 2 | FEAT-002 | Smart Throttle Config | Conventional | 3 | 1 | 2 | 1 | 1 | 3.00 | `throttle`, `limit`, `reset` |
| 3 | FEAT-003 | Project-Specific Rules | Conventional | 5 | 2 | 3 | 2 | 3 | 2.50 | `.redbull.md`, `custom prompt`, `rules` |
| 4 | FEAT-004 | Configurable Judge Model | Conventional | 4 | 2 | 2 | 1 | 2 | 2.00 | `env var`, `sonnet`, `haiku`, `flash` |
| 5 | FEAT-006 | Local LLM Adapter | Creative | 5 | 3 | 4 | 3 | 5 | 1.67 | `ollama`, `local`, `offline`, `privacy` |
| 6 | FEAT-005 | Desktop Notifications | Creative | 3 | 2 | 2 | 1 | 3 | 1.50 | `notify`, `toast`, `ux` |
| 7 | FEAT-007 | Adaptive Learning Loop | Moonshot | 5 | 5 | 5 | 4 | 5 | 1.00 | `self-healing`, `feedback`, `training` |

### Rationale for #1 (Explain Last Decision)
User trust is the biggest barrier to AI autonomy. When the plugin takes control, the user feels a loss of agency; providing an immediate, low-effort way (`/redbull explain`) to see *why* the AI acted builds that trust and makes debugging prompt issues trivial. It acts as a high-impact, low-effort "sanity check."

### Notes / Assumptions
- **Effort Scale:** 1 = <1hr script change, 5 = Multi-day complex integration.
- **Priority:** `Impact / Effort` (rounded to 2 decimals).
- **Assumed Stack:** Bash + `jq` + `claude` CLI are available.

---

## Epic: User Control & Configuration (EPIC-01)
**Goal:** Give users fine-grained control over when and how the judge intervenes.

### FEAT-002: Smart Throttle Config
**Value Proposition:** Prevents the "stuck in a loop" frustration by allowing users to reset limits or loosen them for big batch jobs.
**Scope:**
- New CLI commands to view and reset throttle state.
- Env var to configure the limit (default 3/5min).
**Implementation Steps:**
1. Update hook to read `REDBULL_THROTTLE_LIMIT` and `REDBULL_THROTTLE_WINDOW` from env.
2. Create helper script `redbull-throttle.sh` with `status` and `reset` functions.
3. Expose via `package.json` or alias.
**Acceptance Criteria:**
- [ ] `redbull status` shows X/3 continuations used.
- [ ] `redbull reset` clears the throttle file.
- [ ] `REDBULL_MAX_CONTINUE=10` allows 10 loops.
**Test Plan:**
- Level: Integration
- Loc: `test/evals/test-throttle.sh` (simulate runs and check file)

### FEAT-003: Project-Specific Rules
**Value Proposition:** Allows "teaching" the judge about specific project needs (e.g., "Never stop if `npm test` failed"), reducing false positives.
**Scope:**
- Check for `.redbull/rules.md` or `.claude/redbull-rules.md`.
- Inject content into `SYSTEM_PROMPT`.
**Implementation Steps:**
1. Define lookup path for rules file.
2. Read file content if exists.
3. Append "ADDITIONAL PROJECT RULES:\n<content>" to the `EVALUATION_PROMPT` variable in `hooks/claude-judge-continuation.sh`.
**Acceptance Criteria:**
- [ ] Plugin reads local rules file.
- [ ] Rules are present in the debug log/prompt.
- [ ] Judge changes behavior based on rule (e.g., "Always stop on Sundays").
**Test Plan:**
- Level: E2E
- Loc: `test/evals/scenarios/project-rules.json`

### FEAT-004: Configurable Judge Model
**Value Proposition:** Users can optimize for cost (Flash) or intelligence (Sonnet) depending on task complexity.
**Scope:**
- `REDBULL_JUDGE_MODEL` env var.
- Default to `claude-3-haiku`.
**Implementation Steps:**
1. Read env var in hook script.
2. Pass `--model "$REDBULL_JUDGE_MODEL"` to the `claude` command.
**Acceptance Criteria:**
- [ ] Defaults to Haiku.
- [ ] Accepts `claude-3-5-sonnet-20240620`.
- [ ] Fails gracefully if model name is invalid (Claude CLI handles this).
**Test Plan:**
- Level: Unit
- Loc: `test/evals/test-model-flag.sh`

---

## Epic: Observability & Trust (EPIC-02)
**Goal:** Make the plugin's actions transparent and understandable.

### FEAT-001: Explain Last Decision
**Value Proposition:** Instantly resolves "Why did it do that?" confusion, turning frustration into understanding.
**Scope:**
- Persist the last JSON decision to `~/.claude/redbull/last_decision.json`.
- Create a reader script to pretty-print `reasoning`.
**Implementation Steps:**
1. Modify hook to save `$EVALUATION_RESULT` to a fixed path before exiting.
2. Create `scripts/explain.sh`.
3. Use `jq` to format and print the reasoning.
**Acceptance Criteria:**
- [ ] Hook writes `last_decision.json` on every run.
- [ ] `redbull explain` prints the text clearly.
**Test Plan:**
- Level: Integration
- Loc: `test/evals/test-explain.sh`

### FEAT-005: Desktop Notifications (Creative)
**Value Proposition:** Provides a "pulse" that the agent is working for you, reducing the urge to tab-switch or check terminals.
**Scope:**
- Cross-platform notification trigger (AppleScript for macOS, `notify-send` for Linux).
- "Experiment: Creative" - Success = Users report feeling more "in the loop".
- Rollback: Env var to disable.
**Implementation Steps:**
1. Detect OS.
2. Define `notify()` function.
3. Call `notify "Redbull: Auto-continuing work..."` when blocking a stop.
4. Experiment (1-2hr): Implement basic `osascript` call and run a mock loop.
**Acceptance Criteria:**
- [ ] Toast appears on macOS when continuation occurs.
- [ ] No error output on systems without notification support.
**Test Plan:**
- Level: Manual / UAT
- Loc: Run on dev machine and verify visual toast.

---

## Epic: Intelligence Evolution (EPIC-03)
**Goal:** Move beyond static prompts to adaptive and flexible intelligence.

### FEAT-006: Local LLM Adapter (Creative)
**Value Proposition:** Zero marginal cost for infinite loops; privacy for sensitive transcripts.
**Scope:**
- Check for `ollama` or standard OpenAI-compatible local endpoint.
- Alternate code path in hook to use `curl` instead of `claude`.
- Experiment (1-2hr): Curl `localhost:11434` with the prompt and verify JSON parsing.
**Implementation Steps:**
1. Add `REDBULL_USE_LOCAL_LLM=true` flag.
2. Implement `call_ollama()` function using `curl`.
3. Map Ollama JSON response to expected schema.
**Acceptance Criteria:**
- [ ] Works with `llama3` or `mistral`.
- [ ] Fallback to Claude if local LLM fails/unreachable.
**Test Plan:**
- Level: Integration
- Loc: `test/evals/test-local-llm.sh` (requires mock server)

### FEAT-007: Adaptive Learning Loop (Moonshot)
**Value Proposition:** The plugin gets smarter the more you use (and correct) it, creating a personalized "work rhythm."
**Scope:**
- Watcher process or post-hook to detect user aborts (SIGINT) shortly after continuation.
- "Experiment: Moonshot" - Success = Reduction in false positive rate over 1 week.
- Rollback: Delete the `negative_examples.json` file.
**Implementation Steps:**
1. Hook logs "Continuation Triggered at T" to a state file.
2. A separate "start" hook (if available) or wrapper detects if the *next* command was a user abort or "stop".
3. If confirmed negative signal, append the *previous* transcript snippet to `~/.claude/redbull/negative_examples.json`.
4. Inject these examples as "Anti-patterns" in the `SYSTEM_PROMPT`.
**Acceptance Criteria:**
- [ ] User interrupt (<10s after continue) triggers learning.
- [ ] Negative example file grows.
- [ ] Prompt includes the new negative example.
**Test Plan:**
- Level: E2E
- Loc: `test/evals/scenarios/adaptive-feedback.json`