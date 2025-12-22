# Consolidated Feature Ideas — Redbull Plugin

Generated: 2025-12-22  
Source: Synthesized from 3 brainstorming iterations

Sources:
- `docs/ideas/2025-21-12-features/markdown/overall-features-for-the-plugin-brainstorm.md`
- `docs/ideas/2025-21-12-features/markdown/2025-12-21-features-redbull-brainstorm-gemini.md`
- `docs/ideas/2025-21-12-features/markdown/2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md`

---

## Focus Summary

### Purpose
Hook-based Claude Code plugin that intercepts “stop” moments and decides whether to **block** stopping (continue working) or **approve** stopping, using a secondary Claude instance as a classifier/judge.

### Key Flows
1. **Stop hook** receives event JSON → extracts bounded transcript context → asks judge model → emits `{decision:"block"|"approve"}`.
2. **Anti-recursion**: judge runs in a “no hooks / no tools” mode to avoid self-triggering.
3. **Throttle**: caps continuation loops (e.g., 3 per 5 minutes) and/or introduces cooldowns.
4. **Optional extended hooks**: `PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`, `PreCompact`, and `Notification` can improve safety, quality, and continuity.

### Current Technical Debt Indicators (Feature-Level)
- **Hard-coded policy**: throttle limits, context window size, and model selection are effectively “baked in”.
- **Low transparency**: users don’t always know *why* the plugin blocked stopping or what it was “thinking”.
- **Resilience gaps**: judge model failures/cost/latency can degrade UX; offline fallbacks are limited.
- **Safety expansion risk**: moving beyond Stop into PreToolUse/PostToolUse introduces higher stakes and requires strict safe defaults + opt-in.

### Constraints
- **Deterministic, fast, safe-by-default** hook behavior.
- **No new dependencies** (prefer bash + `jq` + `claude` CLI patterns already used).
- **No breaking contract changes** without explicit approval (stdin JSON → stdout JSON decision semantics).
- **Opt-in for anything that auto-runs commands**; avoid surprises or destructive behavior.

### Risks / Unknowns
- Hook event payload shape/availability can vary by Claude Code version.
- LLM variability: classification prompts require guardrails, throttling, and eval scenarios.
- Secret/sensitive data exposure risk when sending transcript context to models (must redact/limit).

---

## Consolidated Feature Ideas (Ranked by Priority Score)

### Scoring Criteria
- `impact`, `effort`, `expertise`, `risk`, `novelty` are integers 1–5
- `priority_score` = `round(impact/effort, 2)`
- **Tie-breakers**: lower risk → lower expertise → higher impact

| # | ID | Title | Category | Type | Area | Impact | Effort | Expertise | Risk | Novelty | Priority Score | Targets / Search |
|---:|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | FTR-005 | Explain last decision (persist + CLI) + structured decision logs | Conventional | feature | observability | 4 | 1 | 2 | 1 | 2 | **4.00** | `redbull explain`, `last_decision.json`, `log`, `reasoning` |
| 2 | FTR-001 | Per-project autonomy controls settings file | Conventional | feature | design | 3 | 1 | 2 | 1 | 2 | **3.00** | `.claude/*.local.md`, `enabled`, `aggressiveness`, `hooks/lib/settings.sh` |
| 3 | FTR-023 | Throttle config + CLI (status/reset/configure) | Conventional | feature | backend | 3 | 1 | 2 | 1 | 1 | **3.00** | `throttle`, `redbull status`, `redbull reset`, `REDBULL_THROTTLE_LIMIT` |
| 4 | FTR-020 | Global “never continue” ignore patterns (bypass LLM) | Conventional | feature | backend | 3 | 1 | 2 | 2 | 1 | **3.00** | `never continue`, `regex`, `bypass` |
| 5 | FTR-006 | Confidence scoring in judge output | Conventional | feature | backend | 5 | 2 | 2 | 1 | 3 | **2.50** | `confidence`, `json-schema`, `reason` |
| 6 | FTR-009 | Handoff snapshot on Stop/SessionEnd | Conventional | feature | backend | 5 | 2 | 2 | 1 | 2 | **2.50** | `.claude/`, `handoff.md`, `Stop`, `SessionEnd` |
| 7 | FTR-002 | Project-specific rules file (prompt injection) | Conventional | feature | backend | 5 | 2 | 3 | 2 | 3 | **2.50** | `.redbull/rules.md`, `.claude/redbull-rules.md`, `SYSTEM_PROMPT` |
| 8 | FTR-014 | PreToolUse guardrails: block dangerous commands + safe alternatives | Conventional | feature | security | 5 | 2 | 3 | 2 | 3 | **2.50** | `PreToolUse`, `rm -rf`, `git reset --hard`, `curl|sh` |
| 9 | FTR-007 | Dry-run mode (would block/approve, but don’t act) | Conventional | DX | backend | 4 | 2 | 1 | 1 | 2 | **2.00** | `dry-run`, `debug`, `would_block` |
| 10 | FTR-004 | Configurable judge model + multi-model strategy | Conventional | feature | backend | 4 | 2 | 2 | 1 | 2 | **2.00** | `REDBULL_JUDGE_MODEL`, `haiku`, `sonnet`, `flash` |
| 11 | FTR-003 | Manual override controls (force continue/stop + “one more shot”) | Conventional | feature | UX | 4 | 2 | 2 | 2 | 2 | **2.00** | `override`, `continue`, `stop`, `/redbull one-more-shot` |
| 12 | FTR-010 | SessionStart auto-brief (read repo docs/plans) | Conventional | feature | backend | 4 | 2 | 2 | 2 | 2 | **2.00** | `SessionStart`, `AGENTS.md`, `README.md`, `docs/plans` |
| 13 | FTR-016 | PostToolUse failure triage → next-action plan + stop gating | Conventional | feature | backend | 4 | 2 | 3 | 2 | 3 | **2.00** | `PostToolUse`, `exit code`, `triage`, `next steps` |
| 14 | FTR-029 | TodoWrite integration for continuation decisions | Conventional | feature | backend | 5 | 3 | 2 | 2 | 3 | **1.67** | `TodoWrite`, `todo`, `pending items` |
| 15 | FTR-011 | PreCompact state pack generator | Creative | feature | design | 5 | 3 | 3 | 3 | 4 | **1.67** | `PreCompact`, `state pack`, `.claude/state-pack.md` |
| 16 | FTR-015 | Verified-done enforcement (run repo quality gates before Stop/commit) | Conventional | feature | backend | 5 | 3 | 3 | 3 | 2 | **1.67** | `typecheck`, `lint`, `test`, `build`, `git commit` |
| 17 | FTR-026 | Local LLM adapter for judging (Ollama) | Creative | feature | backend | 5 | 3 | 4 | 3 | 5 | **1.67** | `ollama`, `localhost:11434`, `curl`, `privacy` |
| 18 | FTR-008 | User notifications + “next best action” nudges | Creative | feature | design | 3 | 2 | 2 | 1 | 3 | **1.50** | `notify`, `toast`, `osascript`, `notify-send` |
| 19 | FTR-018 | Git-aware continuation safety checks | Conventional | feature | safety | 3 | 2 | 2 | 2 | 2 | **1.50** | `git status`, `clean`, `dirty`, `continue` |
| 20 | FTR-027 | Offline heuristic fallback when API unavailable | Conventional | feature | backend | 4 | 3 | 2 | 2 | 2 | **1.33** | `offline`, `fallback`, `heuristic`, `api unavailable` |
| 21 | FTR-022 | Adaptive throttling based on session complexity | Creative | feature | backend | 4 | 3 | 3 | 2 | 4 | **1.33** | `adaptive throttle`, `complexity` |
| 22 | FTR-019 | Redact secrets before any model call | Conventional | feature | security | 4 | 3 | 4 | 2 | 3 | **1.33** | `redact`, `secrets`, `Authorization: Bearer`, `.env` |
| 23 | FTR-024 | Adaptive learning loop (feedback + negative examples + tuning) | Creative | feature | data | 4 | 3 | 4 | 3 | 4 | **1.33** | `learning`, `negative_examples.json`, `aggressiveness` |
| 24 | FTR-032 | Natural-language config + personality modes | Moonshot | feature | UX | 5 | 4 | 4 | 3 | 5 | **1.25** | `continue aggressively`, `modes`, `intent parsing` |
| 25 | FTR-037 | Hook-orchestrated multi-agent pipeline | Moonshot | feature | infra | 5 | 4 | 5 | 4 | 5 | **1.25** | `pipeline`, `planner`, `reviewer`, `UserPromptSubmit` |
| 26 | FTR-013 | Decision-tracker artifact (capture open questions/options) | Conventional | feature | design | 3 | 3 | 2 | 1 | 2 | **1.00** | `.claude/decisions.md`, `decision needed`, `options` |
| 27 | FTR-031 | Metrics & analytics (cost, streaks, health, dashboard) | Conventional | feature | observability | 3 | 3 | 2 | 1 | 2 | **1.00** | `metrics`, `cost`, `latency`, `dashboard` |
| 28 | FTR-028 | Context window management (slider + smart selection + token reduction) | Creative | feature | backend | 4 | 4 | 3 | 2 | 4 | **1.00** | `context window`, `tail -n`, `smart selection` |
| 29 | FTR-021 | Smarter throttling: loop detection + cooldowns | Conventional | feature | backend | 3 | 3 | 3 | 2 | 2 | **1.00** | `throttle`, `loop detection`, `cooldown` |
| 30 | FTR-012 | Worklog timeline + undo hints | Conventional | feature | data | 4 | 4 | 3 | 3 | 3 | **1.00** | `.claude/worklog.md`, `undo hints` |
| 31 | FTR-030 | Pre-emptive continuation signals (detect next steps before Stop) | Creative | feature | backend | 4 | 4 | 4 | 3 | 4 | **1.00** | `signals`, `pre-emptive`, `next steps` |
| 32 | FTR-017 | Tool error signatures → targeted fix-command suggestions | Conventional | feature | backend | 3 | 4 | 3 | 2 | 3 | **0.75** | `stderr`, `regex`, `suggested commands` |
| 33 | FTR-034 | Status bar / prompt indicator when redbull is active | Creative | UX | design | 2 | 3 | 3 | 1 | 3 | **0.67** | `indicator`, `status` |
| 34 | FTR-033 | Self-maintenance utilities (dependency check + auto-update) | Conventional | DX | infra | 2 | 3 | 2 | 3 | 2 | **0.67** | `auto-update`, `dependency check`, `jq` |
| 35 | FTR-035 | Task progress bar (% complete estimation) | Creative | UX | design | 2 | 4 | 3 | 2 | 4 | **0.50** | `% complete`, `progress` |
| 36 | FTR-025 | Cross-session explicit preferences (opt-in) | Conventional | feature | data | 2 | 4 | 4 | 3 | 3 | **0.50** | `preferences`, `~/.claude/redbull`, `opt-in` |
| 37 | FTR-036 | Multi-turn debate / second judge verification | Creative | feature | backend | 2 | 4 | 4 | 3 | 4 | **0.50** | `second judge`, `verify`, `debate` |

---

## Rationale for Top Picks (Top 5)

1. **FTR-005 (Explain last decision)**: Highest leverage for trust and debugging with minimal implementation risk; directly addresses a common pain point (“why didn’t it stop?”).
2. **FTR-001 (Per-project settings)**: Safely unlocks many other features by making aggressive behaviors opt-in and per-repo controllable.
3. **FTR-023 (Throttle CLI + config)**: Simple, practical control plane for the existing throttle policy; reduces frustration without touching model logic.
4. **FTR-014 (Guardrails)**: High-impact safety improvement before expanding autonomy; provides safer alternatives instead of hard blocks.
5. **FTR-009 (Handoff snapshot)**: Improves continuity and reduces context loss; pairs well with Stop semantics and requires bounded work.

---

## Epics

### EPIC-01 — User Control & Configuration
- **Goal:** Make automation adoptable by keeping users in control (per repo), with clear “off” switches and bounded knobs.
- **Child ideas:** FTR-001, FTR-002, FTR-003, FTR-004, FTR-023, FTR-032

### EPIC-02 — Transparency & Observability
- **Goal:** Make the plugin’s actions explainable and measurable (trust-building, debugging, cost/latency awareness).
- **Child ideas:** FTR-005, FTR-006, FTR-007, FTR-008, FTR-031, FTR-034, FTR-036

### EPIC-03 — Safety & Quality Guardrails
- **Goal:** Prevent irreversible mistakes and ensure “done” is actually verified.
- **Child ideas:** FTR-014, FTR-015, FTR-018, FTR-019, FTR-020

### EPIC-04 — Context Resilience & Memory
- **Goal:** Reduce “where were we?” friction across stops, sessions, and compactions with durable, bounded artifacts.
- **Child ideas:** FTR-009, FTR-010, FTR-011, FTR-012, FTR-013, FTR-025

### EPIC-05 — Judge Intelligence & Resilience
- **Goal:** Improve decision quality and availability (better context selection, fallbacks, learning) without increasing risk.
- **Child ideas:** FTR-016, FTR-017, FTR-021, FTR-022, FTR-024, FTR-026, FTR-027, FTR-028, FTR-029, FTR-030, FTR-035, FTR-037

---

## Detailed Feature Tickets

### FTR-005 — Explain last decision (persist + CLI) + structured decision logs

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `observability`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (FEAT-001, “Explain Last Decision”, “Verbose Debug Mode”, “JSON Output Log”)
- **scores**:
  - impact: 4
  - effort: 1
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 4.00
- **user_value_proposition**:
  - Instantly answers “Why did it do that?”, improving trust and making prompt/debugging issues easier to diagnose.
- **scope**:
  - in:
    - Persist last judge JSON result to `~/.claude/redbull/last_decision.json` (or repo-local when appropriate).
    - Add a `redbull explain` command that prints/pretty-prints the reasoning.
    - (Optional) append-only decision log for analytics.
  - out:
    - Telemetry uploads; cloud logging.
- **implementation_steps**:
  1. Modify Stop hook to save `$EVALUATION_RESULT` (or final output) to a fixed path before exiting.
  2. Add a small CLI script (e.g., `scripts/explain.sh`) that reads and formats `reasoning` via `jq`.
  3. (Optional) Add a bounded structured log of all decisions (size/rotation) if enabled.
- **acceptance_criteria**:
  - [ ] Hook writes `last_decision.json` on every run.
  - [ ] `redbull explain` prints the reasoning clearly.
  - [ ] Logging (if enabled) is bounded and can be disabled.
- **test_plan**:
  - Level: integration.
  - Location: `test/evals/` (add `test-explain.sh` or scenario fixture expectations).
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `last_decision.json`
  - `reasoning`
  - `redbull explain`

### FTR-001 — Per-project autonomy controls settings file

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `design`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-01`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-001)
- **scores**:
  - impact: 3
  - effort: 1
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 3.00
- **user_value_proposition**:
  - Lets users control how aggressive hooks are (continue behavior, auto-run commands, guardrails strictness) per repo.
- **scope**:
  - in:
    - Read `.claude/redbull.local.md` (or repo-standard equivalent) with YAML frontmatter; support `enabled`, `aggressiveness`, and feature toggles for major hook behaviors.
  - out:
    - Global settings UI; cross-machine syncing.
- **implementation_steps**:
  1. Define a minimal settings schema with fail-closed defaults.
  2. Implement a bash parser for YAML frontmatter (no `yq` dependency), plus validation.
  3. Add shared helper `hooks/lib/settings.sh` used by hook scripts.
  4. Update Stop hook to respect `enabled` and `aggressiveness`.
  5. Document supported keys and ensure `.claude/*.local.md` stays uncommitted.
- **acceptance_criteria**:
  - [ ] Users can disable the plugin per repo without uninstalling it.
  - [ ] Default behavior is unchanged when settings file is missing.
  - [ ] Invalid settings fail closed (safe defaults) and do not break the hook.
- **test_plan**:
  - Level: eval scenarios + manual UAT.
  - Location: `test/evals/scenarios/` (missing file, disabled, aggressive).
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `.claude/*.local.md`
  - `enabled: false`
  - `aggressiveness`
  - `hooks/lib/settings.sh`

### FTR-023 — Throttle config + CLI (status/reset/configure)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-01`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (FEAT-002, “Smart Throttle Config”)
- **scores**:
  - impact: 3
  - effort: 1
  - expertise: 2
  - risk: 1
  - novelty: 1
- **priority_score**: 3.00
- **user_value_proposition**:
  - Prevents “stuck in a loop” frustration by allowing users to view/reset limits or loosen them for big batch jobs.
- **scope**:
  - in:
    - New CLI commands to view and reset throttle state.
    - Env vars to configure limits (default 3/5min).
  - out:
    - Complex policy DSL.
- **implementation_steps**:
  1. Update hook to read `REDBULL_THROTTLE_LIMIT` and `REDBULL_THROTTLE_WINDOW` from env.
  2. Create helper script `redbull-throttle.sh` with `status` and `reset` functions.
  3. Expose via command alias or documented invocation.
- **acceptance_criteria**:
  - [ ] `redbull status` shows X/3 continuations used.
  - [ ] `redbull reset` clears the throttle file.
  - [ ] Setting `REDBULL_MAX_CONTINUE=10` (or equivalent) allows 10 loops.
- **test_plan**:
  - Level: integration.
  - Location: `test/evals/` (scripted throttle simulation).
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `REDBULL_THROTTLE_LIMIT`
  - `REDBULL_THROTTLE_WINDOW`
  - `redbull status`
  - `redbull reset`

### FTR-020 — Global “never continue” ignore patterns (bypass LLM)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Global specific ignore”)
- **scores**:
  - impact: 3
  - effort: 1
  - expertise: 2
  - risk: 2
  - novelty: 1
- **priority_score**: 3.00
- **user_value_proposition**:
  - Lets users bypass the LLM for known “never continue” patterns (file paths, commands, output strings) to reduce false positives and cost.
- **scope**:
  - in:
    - Configurable regex list evaluated before invoking the judge.
  - out:
    - Trying to be perfect at classification; this is an escape hatch.
- **implementation_steps**:
  1. Define ignore list location (per-repo preferred, fall back to user-local).
  2. Before sending transcript context to the judge, check for ignore matches; if matched, approve stop with a clear reason (“ignored by pattern X”).
  3. Ensure patterns are bounded (size/number) and safe (no catastrophic regex).
- **acceptance_criteria**:
  - [ ] Ignore patterns can force “approve stop” without calling the model.
  - [ ] Reasons clearly indicate the ignore match triggered.
  - [ ] Patterns are bounded and do not introduce hook slowdowns.
- **test_plan**:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (fixtures containing ignored patterns).
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `never continue`
  - `ignore`
  - `regex`

### FTR-006 — Confidence scoring in judge output

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (IMP-001, “Confidence Scoring” rationale)
- **scores**:
  - impact: 5
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 3
- **priority_score**: 2.50
- **user_value_proposition**:
  - Adds transparency to every decision without changing core logic; helps debugging and trust.
- **scope**:
  - in:
    - Extend judge JSON schema to include confidence level(s).
    - Surface confidence in output (e.g., in `reason` or separate field).
  - out:
    - Changing the meaning of approve/block.
- **implementation_steps**:
  1. Update the judge JSON schema to include `confidence` (e.g., 1–5 or 0–100).
  2. Update prompt to require confidence values and brief justification.
  3. Update output formatting to include confidence in a stable, greppable way.
  4. Add/adjust eval scenarios to validate stable output structure.
- **acceptance_criteria**:
  - [ ] Output includes a confidence field for both block/approve paths.
  - [ ] Confidence is present in logs/decision artifacts for debugging.
  - [ ] No regression in decision correctness (verified via eval suite).
- **test_plan**:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `confidence`
  - `json-schema`
  - `reason`

### FTR-009 — Handoff snapshot on Stop/SessionEnd

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-04`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-002)
- **scores**:
  - impact: 5
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 2.50
- **user_value_proposition**:
  - On a legitimate stop, users get a structured handoff with status + next 3 actions + files touched, enabling fast resumes.
- **scope**:
  - in:
    - On `Stop` and/or `SessionEnd`, write `.claude/handoff.md` (or timestamped) with deterministic formatting.
  - out:
    - Long historical logging; writing sensitive content outside repo.
- **implementation_steps**:
  1. Extract last N transcript entries and summarize with a strict JSON schema.
  2. Pull safe repo signals (branch, `git diff --name-only`) when enabled.
  3. Write the artifact under `.claude/` with size limits; skip in judge mode.
  4. Ensure secrets are redacted/omitted (see FTR-019).
- **acceptance_criteria**:
  - [ ] On approved stop, a handoff file includes “Status”, “Next steps”, “Files touched”.
  - [ ] Artifact never writes outside the repo.
  - [ ] Hook remains fast (bounded work; ≤ one model call).
- **test_plan**:
  - Level: eval scenarios + manual UAT.
  - Location: `test/evals/scenarios/`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `handoff`
  - `.claude/`
  - `SessionEnd`
  - `files touched`

### FTR-002 — Project-specific rules file (prompt injection)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-01`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (FEAT-003, “Project-Specific Rules”)
- **scores**:
  - impact: 5
  - effort: 2
  - expertise: 3
  - risk: 2
  - novelty: 3
- **priority_score**: 2.50
- **user_value_proposition**:
  - Lets users “teach” the judge about repo-specific context (“Never stop if `npm test` failed”), reducing false positives.
- **scope**:
  - in:
    - Check for `.redbull/rules.md` or `.claude/redbull-rules.md`.
    - Inject content into `SYSTEM_PROMPT` / evaluation prompt.
  - out:
    - Executing arbitrary repo scripts; dynamic DSL.
- **implementation_steps**:
  1. Define lookup path(s) and maximum file size.
  2. Read rules file content if present.
  3. Append `ADDITIONAL PROJECT RULES:\n<content>` to the prompt.
  4. Ensure rules content is surfaced in debug logs when enabled.
- **acceptance_criteria**:
  - [ ] Plugin reads local rules file when present.
  - [ ] Rules appear in prompt/debug output (when enabled).
  - [ ] Judge behavior changes as expected for a scenario using explicit rules.
- **test_plan**:
  - Level: E2E / eval scenarios.
  - Location: `test/evals/scenarios/project-rules.json`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `.redbull/rules.md`
  - `.claude/redbull-rules.md`
  - `ADDITIONAL PROJECT RULES`

### FTR-014 — PreToolUse guardrails: block dangerous commands + safe alternatives

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `security`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-003)
- **scores**:
  - impact: 5
  - effort: 2
  - expertise: 3
  - risk: 2
  - novelty: 3
- **priority_score**: 2.50
- **user_value_proposition**:
  - Prevents catastrophic mistakes by intercepting risky commands and offering safer alternatives.
- **scope**:
  - in:
    - `PreToolUse` interception for shell commands and file writes.
    - Curated deny list with contextual allow rules and suggested replacements.
  - out:
    - Complex policy DSL; RBAC.
- **implementation_steps**:
  1. Implement `hooks/claude-guardrail-pretooluse.sh` that matches high-risk patterns (`rm -rf`, `git reset --hard`, `chmod -R 777`, `curl|sh`).
  2. Emit structured decision: `block` with reason + safe alternative command.
  3. Add opt-out/strictness via settings (FTR-001).
  4. Add “allowed paths” safeguards (e.g., block deletes outside workspace).
- **acceptance_criteria**:
  - [ ] Known-danger patterns are blocked with a safer alternative suggestion.
  - [ ] Read-only commands are not blocked; low false positives.
  - [ ] Behavior can be relaxed/disabled per repo.
- **test_plan**:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (blocked patterns + allowed safe equivalents).
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `PreToolUse`
  - `deny list`
  - `safe alternative`
  - `rm -rf`
  - `git reset --hard`

### FTR-007 — Dry-run mode (would block/approve, but don’t act)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `DX`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (IMP-003)
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Dry Run Mode”)
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 1
  - risk: 1
  - novelty: 2
- **priority_score**: 2.00
- **user_value_proposition**:
  - Lets users preview what the hook would do without affecting flow; safer debugging.
- **scope**:
  - in:
    - A mode that computes decision + reasoning but always outputs `approve` (or always allows stop) while logging the “would have” result.
  - out:
    - Changing judge behavior; this is only a debug wrapper.
- **implementation_steps**:
  1. Add env var / flag (e.g., `REDBULL_DRY_RUN=true`) respected by the Stop hook.
  2. When enabled, compute the judge result normally but override output to a safe default.
  3. Persist the “would have blocked” decision to the decision artifact/log (FTR-005).
- **acceptance_criteria**:
  - [ ] Dry-run mode never blocks stopping.
  - [ ] Dry-run still captures the would-have decision for inspection.
  - [ ] Default behavior unchanged when flag unset.
- **test_plan**:
  - Level: integration + eval scenarios.
  - Location: `test/evals/`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `DRY_RUN`
  - `would have`
  - `debug`

### FTR-004 — Configurable judge model + multi-model strategy

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-01`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (FEAT-004, “Configurable Judge Model”)
  - `overall-features-for-the-plugin-brainstorm.md` (“Multi-Model Support”)
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 2.00
- **user_value_proposition**:
  - Lets users optimize for cost/latency vs reasoning quality depending on task complexity.
- **scope**:
  - in:
    - Support `REDBULL_JUDGE_MODEL` env var, defaulting to a fast model.
  - out:
    - Complex auto-routing without settings/telemetry.
- **implementation_steps**:
  1. Read env var in hook script.
  2. Pass `--model \"$REDBULL_JUDGE_MODEL\"` to the `claude` command.
  3. Optionally expose model selection via per-repo settings (FTR-001).
- **acceptance_criteria**:
  - [ ] Defaults to Haiku (or existing default).
  - [ ] Accepts a smarter model (e.g., Sonnet) when specified.
  - [ ] Fails gracefully on invalid model names (Claude CLI handles this).
- **test_plan**:
  - Level: unit/integration.
  - Location: `test/evals/`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `REDBULL_JUDGE_MODEL`
  - `--model`

### FTR-003 — Manual override controls (force continue/stop + “one more shot”)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `UX`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-01`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (“User Override Mechanism”, “Configurable Continuation Criteria”)
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“One More Shot”)
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 2
- **priority_score**: 2.00
- **user_value_proposition**:
  - Restores agency: users can force a stop/continue override and manually invoke the judge when desired.
- **scope**:
  - in:
    - Simple override mechanism (settings/comment token) that forces approve/block.
    - A command (“one more shot”) to manually invoke judging when the assistant stopped and the user wants continuation.
  - out:
    - Complex UI; background daemons.
- **implementation_steps**:
  1. Define override input surface (per-repo settings key and/or “inline comment” tokens in transcript).
  2. Implement a “manual judge invocation” command that runs the same evaluator logic and prints recommended next step.
  3. Ensure overrides are explicit and short-lived (avoid infinite loops).
- **acceptance_criteria**:
  - [ ] User can force “approve stop” when they want to stop.
  - [ ] User can force a continuation once (bounded) when they want to proceed.
  - [ ] Overrides do not bypass safety guardrails (FTR-014) by default.
- **test_plan**:
  - Level: eval scenarios + manual UAT.
  - Location: `test/evals/scenarios/`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `override`
  - `one more shot`
  - `manual judge`

### FTR-010 — SessionStart auto-brief (read repo docs/plans)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-04`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-004)
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 2
- **priority_score**: 2.00
- **user_value_proposition**:
  - Reduces repeated “what is this repo?” overhead by surfacing AGENTS/README/plans early.
- **scope**:
  - in:
    - On `SessionStart`, detect and summarize key guidance files into a compact brief.
  - out:
    - Full indexing; heavy scanning.
- **implementation_steps**:
  1. Locate guidance files (`AGENTS.md`, `README.md`, `CLAUDE.md`, `PLAN.md`, `docs/plans/**`) with strict limits.
  2. Produce a small structured brief (JSON → rendered markdown) listing commands, quality gates, gotchas.
  3. Store as repo-local artifact (e.g., `.claude/session-brief.md`) and/or inject into context.
  4. Respect per-repo settings for size/verbosity (FTR-001).
- **acceptance_criteria**:
  - [ ] Brief generation is bounded (time + size) and never leaks secrets.
  - [ ] Missing files degrade gracefully.
  - [ ] Users can disable per repo.
- **test_plan**:
  - Level: manual UAT + lightweight scripted test.
  - Location: add small harness or scenario fixtures simulating `SessionStart`.
- **targets_search_tokens**:
  - `SessionStart`
  - `session brief`
  - `AGENTS.md`
  - `docs/plans`

### FTR-016 — PostToolUse failure triage → next-action plan + stop gating

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-005)
- **scores**:
  - impact: 4
  - effort: 2
  - expertise: 3
  - risk: 2
  - novelty: 3
- **priority_score**: 2.00
- **user_value_proposition**:
  - Converts tool failures into an actionable plan and prevents premature stopping until triage is acknowledged.
- **scope**:
  - in:
    - `PostToolUse` detects non-zero exit; captures output; generates 1–3 next commands; optionally blocks stop if unresolved.
  - out:
    - Auto-fixing without user consent; destructive remediation.
- **implementation_steps**:
  1. Parse tool results and classify common error types (tests, missing deps, permissions, lint/typecheck).
  2. Generate a bounded “next action plan” using a strict schema (no tool calls in judge mode).
  3. Feed unresolved error state into Stop judge decision.
  4. Add throttling to avoid loops.
- **acceptance_criteria**:
  - [ ] After a failing tool run, user sees a short plan with 1–3 concrete commands.
  - [ ] Assistant does not stop immediately after failure unless user explicitly requests.
  - [ ] Behavior is opt-out via settings.
- **test_plan**:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (failing tool transcripts assert continue).
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `PostToolUse`
  - `exit code`
  - `triage`
  - `next action`

### FTR-029 — TodoWrite integration for continuation decisions

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (IMP-002, “TodoWrite Integration”)
- **scores**:
  - impact: 5
  - effort: 3
  - expertise: 2
  - risk: 2
  - novelty: 3
- **priority_score**: 1.67
- **user_value_proposition**:
  - Improves decision accuracy by using pending TODO state as a strong signal that work remains.
- **scope**:
  - in:
    - Read a bounded representation of todo list state (when available) and inject into judge context.
  - out:
    - Editing todo files automatically without explicit user request.
- **implementation_steps**:
  1. Identify todo state location(s) in Claude Code transcripts/artifacts.
  2. Extract pending items and include as a compact section in the prompt.
  3. Update eval scenarios to include todo state and validate decisions.
- **acceptance_criteria**:
  - [ ] When TODOs exist, judge is more likely to block stopping mid-task.
  - [ ] Missing todo state does not change default behavior.
  - [ ] No secrets or large content is included.
- **test_plan**:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/`
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `TodoWrite`
  - `todo`
  - `pending`

### FTR-011 — PreCompact state pack generator

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `feature`
- **area**: `design`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-04`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-007)
- **scores**:
  - impact: 5
  - effort: 3
  - expertise: 3
  - risk: 3
  - novelty: 4
- **priority_score**: 1.67
- **user_value_proposition**:
  - Preserves key constraints/progress across compactions to reduce regressions from context loss.
- **scope**:
  - in:
    - On `PreCompact`, generate a bounded state pack (goals, constraints, progress, next steps, commands run, key files).
  - out:
    - Large verbose summaries; unbounded token usage.
- **implementation_steps**:
  1. Collect bounded inputs: last N transcript entries, changed file list, plan/TODOs.
  2. Ask model for a schema-bound “state pack” with strict size limits.
  3. Persist `.claude/state-pack.md` and surface it on next session start (pairs with FTR-010).
  4. Ensure redaction (FTR-019).
- **acceptance_criteria**:
  - [ ] State pack is bounded and deterministic in structure.
  - [ ] Users can disable per repo.
  - [ ] After compaction, assistant retains main constraints and next steps.
- **test_plan**:
  - Level: eval scenarios + UAT.
  - Location: `test/evals/scenarios/`
- **experiment_category**: `creative`
- **small_experiment_(1–2h)**:
  - Implement minimal PreCompact hook writing a 10-bullet state pack from last 10 transcript entries.
- **success_metric**:
  - Post-compact “forgot constraints” failures drop by ≥50% across a targeted eval subset.
- **rollback_plan**:
  - Feature-flag behind settings; default off; remove hook + artifacts if noisy.

### FTR-015 — Verified-done enforcement (run repo quality gates before Stop/commit)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-006)
- **scores**:
  - impact: 5
  - effort: 3
  - expertise: 3
  - risk: 3
  - novelty: 2
- **priority_score**: 1.67
- **user_value_proposition**:
  - Prevents “looks done” outcomes by enforcing the repo’s proving commands before stop/commit.
- **scope**:
  - in:
    - Detect proving commands from repo conventions or explicit config; when enabled, run in order and block stop on failure/unrun.
  - out:
    - Surprise installs; modifying lockfiles; auto-running without opt-in.
- **implementation_steps**:
  1. Detect proving commands (`package.json`, `Makefile`, `README`, explicit config).
  2. If user opted in (FTR-001), run gates in order with stop-on-failure.
  3. Feed results into Stop decision (block stop if gates failed or unrun).
  4. Cache results per session to avoid repeat runs.
- **acceptance_criteria**:
  - [ ] When enabled, final stop triggers `typecheck → lint → test → build` (or configured equivalents).
  - [ ] Blocks stop on failure.
  - [ ] No install steps are run automatically.
- **test_plan**:
  - Level: manual UAT + eval scenarios for “claims done without tests”.
  - Location: `test/evals/scenarios/`

### FTR-026 — Local LLM adapter for judging (Ollama)

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (FEAT-006, “Local LLM Adapter”)
- **scores**:
  - impact: 5
  - effort: 3
  - expertise: 4
  - risk: 3
  - novelty: 5
- **priority_score**: 1.67
- **user_value_proposition**:
  - Zero marginal cost for infinite loops; privacy for sensitive transcripts.
- **scope**:
  - in:
    - Optional path using `curl` to talk to local Ollama (or compatible endpoint).
    - Fallback to Claude CLI when local path unavailable.
  - out:
    - Auto-installing Ollama; mandatory local setup.
- **implementation_steps**:
  1. Add `REDBULL_USE_LOCAL_LLM=true` flag.
  2. Implement `call_ollama()` with `curl`.
  3. Map response into expected judge schema.
  4. Fail closed (approve stop) or fallback to Claude when local call fails/unreachable.
- **acceptance_criteria**:
  - [ ] Works with at least one local model (e.g., `llama3` or `mistral`).
  - [ ] Fallback to Claude when local LLM is unavailable.
- **test_plan**:
  - Level: integration (with mock server).
  - Location: `test/evals/`

### FTR-008 — User notifications + “next best action” nudges

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `feature`
- **area**: `design`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (FEAT-005, “Desktop Notifications”)
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-012)
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 1
  - novelty: 3
- **priority_score**: 1.50
- **user_value_proposition**:
  - Keeps users “in the loop” when auto-continuation triggers; reduces stalls by suggesting a next best action during idle moments.
- **scope**:
  - in:
    - Cross-platform notification trigger when blocking a stop.
    - Optional nudges (rate-limited) that suggest the next best action without forcing continuation.
  - out:
    - Spammy notifications; interrupting users mid-typing.
- **implementation_steps**:
  1. Detect OS; implement `notify()` (macOS `osascript`, Linux `notify-send`).
  2. Call `notify \"Redbull: Auto-continuing work...\"` when stop is blocked (feature-flagged).
  3. Implement bounded “next best action” nudges with strict schema and rate limits.
- **acceptance_criteria**:
  - [ ] Toast appears on macOS when continuation occurs.
  - [ ] No errors on systems without notification support.
  - [ ] Nudges are rate-limited and disable-able.
- **test_plan**:
  - Level: manual/UAT + limited eval assertions for “no nudge when user asked a question”.

### FTR-018 — Git-aware continuation safety checks

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `safety`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Git-aware safety”)
- **scores**:
  - impact: 3
  - effort: 2
  - expertise: 2
  - risk: 2
  - novelty: 2
- **priority_score**: 1.50
- **user_value_proposition**:
  - Prevents continuation in “unsafe” repo states depending on user preference (clean/dirty gating).
- **scope**:
  - in:
    - Optional check of working tree state before blocking stop (configurable).
  - out:
    - Blocking read-only actions; making git mandatory.
- **implementation_steps**:
  1. If `git` repo detected and feature enabled, compute status (`git status --porcelain`).
  2. Apply policy (“only continue if clean” or “only if dirty” depending on preference).
  3. Surface policy reason in output and allow per-repo override (FTR-001).
- **acceptance_criteria**:
  - [ ] Policy is opt-in and configurable per repo.
  - [ ] Clear reason emitted when policy blocks continuation.
- **test_plan**:
  - Level: manual UAT + small scripted tests in a temp repo.

### FTR-027 — Offline heuristic fallback when API unavailable

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (IMP-004, “Offline Fallback”)
- **scores**:
  - impact: 4
  - effort: 3
  - expertise: 2
  - risk: 2
  - novelty: 2
- **priority_score**: 1.33
- **user_value_proposition**:
  - Keeps the plugin useful during API outages by using bounded heuristics.
- **scope**:
  - in:
    - Simple heuristic rules that decide approve/block without model calls when the judge fails/unavailable.
  - out:
    - Attempting to “outsmart” the model; heuristics should be conservative.
- **implementation_steps**:
  1. Detect judge call failure (non-zero, invalid JSON, timeout).
  2. Apply conservative heuristic checks (e.g., if the assistant asked a question → approve stop; if explicit “next steps” markers → block once).
  3. Emit reason indicating fallback path used.
- **acceptance_criteria**:
  - [ ] When judge is unavailable, fallback behavior is predictable and safe.
  - [ ] Fallback does not introduce loops (still respects throttle).
- **test_plan**:
  - Level: eval scenarios (simulate judge failure).
  - Location: `test/evals/scenarios/`

### FTR-022 — Adaptive throttling based on session complexity

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (IMP-005, “Adaptive Throttling”)
- **scores**:
  - impact: 4
  - effort: 3
  - expertise: 3
  - risk: 2
  - novelty: 4
- **priority_score**: 1.33
- **user_value_proposition**:
  - Reduces the “too strict vs too loose” throttle trade-off by adapting limits to session/task complexity.
- **scope**:
  - in:
    - Compute a bounded complexity score and adjust throttle window/limit within caps.
  - out:
    - Unbounded learning; removing hard safety caps.
- **implementation_steps**:
  1. Define complexity signals (recent tool failures, number of files touched, todo count).
  2. Adjust throttle window/limit within safe caps and log the chosen values.
  3. Ensure per-repo settings override and explicit caps always win.
- **acceptance_criteria**:
  - [ ] Throttle never exceeds configured hard caps.
  - [ ] Complexity-driven adjustments are transparent in logs/decision reason.
- **test_plan**:
  - Level: eval scenarios (simulate high/low complexity sessions).

### FTR-019 — Redact secrets before any model call

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `security`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-03`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-010)
- **scores**:
  - impact: 4
  - effort: 3
  - expertise: 4
  - risk: 2
  - novelty: 3
- **priority_score**: 1.33
- **user_value_proposition**:
  - Reduces chance of leaking secrets or sensitive data to models by filtering common secret patterns before any model call.
- **scope**:
  - in:
    - Redact tokens/keys/password-like strings in transcript excerpts; optionally omit lines referencing `.env` or credential files.
  - out:
    - Perfect secret detection; replacing a real secrets scanner.
- **implementation_steps**:
  1. Add bounded redaction pass over extracted transcript content (regex patterns + allowlist).
  2. Ensure all model-bound payloads go through redaction (Stop judge, state pack, triage).
  3. Annotate output reason with “redactions applied” count(s).
  4. Allow opt-out only in explicit unsafe mode (via settings).
- **acceptance_criteria**:
  - [ ] Common secret patterns are redacted before any model call.
  - [ ] Redaction does not break JSON schemas or hook behavior.
  - [ ] Plugin does not log raw secrets to stdout/stderr.
- **test_plan**:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (fixtures containing fake keys).
  - Command: `./test/evals/run-evals.sh`
- **targets_search_tokens**:
  - `redact`
  - `Authorization: Bearer`
  - `.env`

### FTR-024 — Adaptive learning loop (feedback + negative examples + tuning)

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `feature`
- **area**: `data`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-008)
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (FEAT-007, “Adaptive Learning Loop”)
  - `overall-features-for-the-plugin-brainstorm.md` (“Session Memory”, “User Feedback Loop”, “Cross-Session Learning”)
- **scores**:
  - impact: 4
  - effort: 3
  - expertise: 4
  - risk: 3
  - novelty: 4
- **priority_score**: 1.33
- **user_value_proposition**:
  - Adapts within bounds to reduce unwanted stopping and over-eager continuation by learning from outcomes.
- **scope**:
  - in:
    - Opt-in preference signal tracking per repo/session.
    - Optional negative examples file to reduce repeated false positives.
  - out:
    - Cross-repo training; complex ML.
- **implementation_steps**:
  1. Record minimal “decision outcome” markers per session in `~/.claude/redbull/` or repo-local `.claude/` (opt-in).
  2. Adjust judge thresholds/prompts (“more/less aggressive”) based on signal; never override explicit user stop requests.
  3. Add caps and reset; expose current learned level in handoff snapshot (FTR-009).
  4. (Moonshot extension) detect user aborts shortly after continuation and append transcript snippet to `negative_examples.json`; inject as anti-patterns.
- **acceptance_criteria**:
  - [ ] Over time, behavior adapts predictably within caps.
  - [ ] Users can reset learned preferences; learning is disable-able.
  - [ ] Adaptation never overrides explicit user requests to stop or ask questions.
- **test_plan**:
  - Level: eval scenarios + UAT.
  - Location: `test/evals/scenarios/` (sequences where user says “continue”; abort-after-continue cases).
- **experiment_category**: `creative`
- **small_experiment_(1–2h)**:
  - Increase a single scalar `aggressiveness` when the user types `continue` within 60 seconds of an approved stop.
- **success_metric**:
  - ≥30% fewer “type continue” moments per hour in manual use (bounded test).
- **rollback_plan**:
  - Disable learning by default; delete stored preference/negative example files.

### FTR-032 — Natural-language config + personality modes

- **kind**: `improvement`
- **category**: `Moonshot`
- **type**: `feature`
- **area**: `UX`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-01`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (IMP-008, “Natural Language Config”)
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Personality settings”, “Natural Language Config” example)
- **scores**:
  - impact: 5
  - effort: 4
  - expertise: 4
  - risk: 3
  - novelty: 5
- **priority_score**: 1.25
- **user_value_proposition**:
  - Lets users configure aggressiveness and behavior via natural language cues (“continue aggressively”), potentially improving usability.
- **scope**:
  - in:
    - Parse explicit, prefixed “commands” embedded in comments/transcripts (bounded).
    - Provide personality modes (aggressive/passive) that map to prompt knobs.
  - out:
    - Freeform intent parsing of arbitrary text without explicit markers.
- **implementation_steps**:
  1. Define strict syntax for “NL config” tokens to avoid accidental triggers.
  2. Map tokens to known settings keys (ties into FTR-001).
  3. Add exhaustive tests for parsing and safe defaults.
- **acceptance_criteria**:
  - [ ] Only explicit tokens change behavior (no accidental triggers).
  - [ ] Defaults remain unchanged without tokens/settings file.
- **test_plan**:
  - Level: unit parsing tests + eval scenarios.

### FTR-037 — Hook-orchestrated multi-agent pipeline

- **kind**: `improvement`
- **category**: `Moonshot`
- **type**: `feature`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-009)
- **scores**:
  - impact: 5
  - effort: 4
  - expertise: 5
  - risk: 4
  - novelty: 5
- **priority_score**: 1.25
- **user_value_proposition**:
  - Turns Claude Code into a “mini team” for large requests (planner → implementer → reviewer) via hook-triggered structured guidance.
- **scope**:
  - in:
    - Hook-triggered stage prompts that produce structured guidance artifacts.
  - out:
    - Background daemons; external services; new dependencies.
- **implementation_steps**:
  1. Define pipeline stages and triggers (`UserPromptSubmit`, `PostToolUse`, `Stop`).
  2. Implement schema-bound prompts producing actionable JSON.
  3. Persist stage outputs under `.claude/pipeline/` and surface them at the right time.
  4. Add aggressive throttling and kill switches (FTR-001).
- **acceptance_criteria**:
  - [ ] For multi-step tasks, pipeline produces plan + verification checklist before stopping.
  - [ ] Pipeline never runs tools; produces guidance only.
  - [ ] Users can disable per repo.
- **test_plan**:
  - Level: eval scenarios + UAT.
  - Location: `test/evals/scenarios/`
- **experiment_category**: `moonshot`
- **small_experiment_(1–2h)**:
  - Add a Stop-stage “reviewer” that blocks stop if quality gates were not run.

### FTR-013 — Decision-tracker artifact (capture open questions/options)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `design`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-04`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-013)
- **scores**:
  - impact: 3
  - effort: 3
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 1.00
- **user_value_proposition**:
  - Captures “decision needed” stops into a durable artifact to reduce repeated clarification loops.
- **scope**:
  - in:
    - On stop approval due to decision-needed, write `.claude/decisions.md` with questions/options/recommendation.
  - out:
    - Automatically choosing decisions.
- **implementation_steps**:
  1. Extend Stop judge schema to output `decision_needed=true` plus questions/options.
  2. Render artifact deterministically under `.claude/`.
  3. Link artifact in Stop reason and handoff snapshot.
- **acceptance_criteria**:
  - [ ] Artifact created/updated when stopping for a decision.
  - [ ] Artifact contains at least one clear question and 2–3 options when applicable.
  - [ ] No artifact written when stopping for completion.
- **test_plan**:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/`

### FTR-031 — Metrics & analytics (cost, streaks, health, dashboard)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `observability`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (“Analytics Dashboard”, “Cost Tracking”, “Continuation Streak Metrics”, “Plugin Health Monitoring”, IMP-006)
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Cost Tracker”, “JSON Output Log”)
- **scores**:
  - impact: 3
  - effort: 3
  - expertise: 2
  - risk: 1
  - novelty: 2
- **priority_score**: 1.00
- **user_value_proposition**:
  - Helps users understand ROI (time saved), reliability (errors/latency), and cost (judge calls).
- **scope**:
  - in:
    - Structured logs, basic counters, and summary views.
  - out:
    - Web dashboards requiring new deps.
- **implementation_steps**:
  1. Add bounded structured logging for decisions and timings (opt-in).
  2. Compute simple rollups (counts, streaks, mean latency, estimated cost).
  3. Expose via a CLI summary command.
- **acceptance_criteria**:
  - [ ] Metrics are bounded and opt-in.
  - [ ] No secrets are logged (pair with FTR-019).
- **test_plan**:
  - Level: manual UAT + small fixture tests.

### FTR-028 — Context window management (slider + smart selection + token reduction)

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (“Context Window Optimization”, “Smart Context Selection”, IMP-007)
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Context Window slider”)
- **scores**:
  - impact: 4
  - effort: 4
  - expertise: 3
  - risk: 2
  - novelty: 4
- **priority_score**: 1.00
- **user_value_proposition**:
  - Reduces token cost and improves decision quality by selecting more relevant context and allowing configurable window sizes.
- **scope**:
  - in:
    - Configurable line/window count (10–50) to send to judge.
    - Smarter selection heuristics to prioritize relevant transcript entries.
  - out:
    - Unbounded context expansion.
- **implementation_steps**:
  1. Add settings/env var for context window size with safe caps.
  2. Implement “smart selection” rules (e.g., prefer tool failures, TODOs, explicit next-step markers).
  3. Ensure token budget is bounded and redaction applies (FTR-019).
- **acceptance_criteria**:
  - [ ] Context window is configurable within caps.
  - [ ] Smart selection is deterministic and doesn’t regress decisions (eval-validated).
- **test_plan**:
  - Level: eval scenarios (cases where relevant context is earlier than last N lines).

### FTR-021 — Smarter throttling: loop detection + cooldowns

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-014)
- **scores**:
  - impact: 3
  - effort: 3
  - expertise: 3
  - risk: 2
  - novelty: 2
- **priority_score**: 1.00
- **user_value_proposition**:
  - Prevents rare but frustrating “continue loops” by detecting repeated stop→continue cycles and backing off.
- **scope**:
  - in:
    - Loop heuristics + adaptive cooldowns; optional override via settings.
  - out:
    - Cross-repo analytics state.
- **implementation_steps**:
  1. Extend throttle file format to include a small rolling fingerprint history.
  2. Detect repeat patterns and temporarily downgrade aggressiveness.
  3. Surface clear explanation in reason when backing off.
- **acceptance_criteria**:
  - [ ] After repeated identical cycles, plugin backs off and approves stop.
  - [ ] Backoff is temporary and resets after cooldown.
  - [ ] Override exists via settings.
- **test_plan**:
  - Level: eval scenarios (loop transcript asserts eventual stop approval).

### FTR-012 — Worklog timeline + undo hints

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `data`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-04`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-011)
- **scores**:
  - impact: 4
  - effort: 4
  - expertise: 3
  - risk: 3
  - novelty: 3
- **priority_score**: 1.00
- **user_value_proposition**:
  - Provides a searchable “what happened” trail plus safe rollback hints to reduce fear and speed recovery.
- **scope**:
  - in:
    - Append-only worklog artifacts under `.claude/`; undo hints generated on demand.
  - out:
    - Automatic rollbacks.
- **implementation_steps**:
  1. Record minimal event log on `PostToolUse` (timestamp, tool, exit code, files).
  2. Add Stop-stage summarizer that condenses log into “Work done” + “Undo hints”.
  3. Add strict retention limits and opt-in via settings.
- **acceptance_criteria**:
  - [ ] `.claude/worklog.md` is understandable and bounded.
  - [ ] Undo hints are non-destructive suggestions (never auto-executed).
- **test_plan**:
  - Level: manual UAT + small fixture tests.

### FTR-030 — Pre-emptive continuation signals (detect next steps before Stop)

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `overall-features-for-the-plugin-brainstorm.md` (“Pre-emptive Continuation Signals”)
- **scores**:
  - impact: 4
  - effort: 4
  - expertise: 4
  - risk: 3
  - novelty: 4
- **priority_score**: 1.00
- **user_value_proposition**:
  - Improves continuation decisions by detecting “obvious next steps” earlier and more reliably than a final stop prompt.
- **scope**:
  - in:
    - Detect and store “next step cues” during the session; use them at Stop time.
  - out:
    - Auto-running tools without opt-in.
- **implementation_steps**:
  1. Define cue detectors (TODOs, “next I will”, failing tests, open loops).
  2. Persist a bounded “pending work” signal to a temporary file keyed by session.
  3. Feed that signal into Stop judge prompt and/or heuristics.
- **acceptance_criteria**:
  - [ ] When cues are present, stop is more likely to be blocked (bounded and throttle-respecting).
  - [ ] Signal is cleared on legitimate stops.
- **test_plan**:
  - Level: eval scenarios.

### FTR-017 — Tool error signatures → targeted fix-command suggestions

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-015)
- **scores**:
  - impact: 3
  - effort: 4
  - expertise: 3
  - risk: 2
  - novelty: 3
- **priority_score**: 0.75
- **user_value_proposition**:
  - Speeds recovery from common failures by suggesting likely next commands based on error signatures.
- **scope**:
  - in:
    - Lightweight signature matching with a fallback model summarizer (schema-bound).
  - out:
    - Full error knowledgebase; auto-running fixes.
- **implementation_steps**:
  1. Add small signature map (regex → suggested commands) with strict bounds.
  2. If no signature matches, call model for 1–2 suggestions (schema-bound).
  3. Integrate with failure triage (FTR-016).
- **acceptance_criteria**:
  - [ ] Recognized errors produce deterministic safe suggestions.
  - [ ] Suggestions never include destructive commands by default (respect guardrails).
- **test_plan**:
  - Level: fixture tests + eval scenarios.

### FTR-034 — Status bar / prompt indicator when redbull is active

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `UX`
- **area**: `design`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Status Bar Indicator”)
- **scores**:
  - impact: 2
  - effort: 3
  - expertise: 3
  - risk: 1
  - novelty: 3
- **priority_score**: 0.67
- **user_value_proposition**:
  - Gives a subtle signal that Redbull is active; reduces confusion when behavior changes.
- **scope**:
  - in:
    - Minimal indicator pattern supported by Claude Code (if any) or output hinting.
  - out:
    - UI changes requiring upstream changes.
- **implementation_steps**:
  1. Investigate whether Claude Code supports a status indicator hook or prompt decoration.
  2. If not available, fall back to a “first-run” message or optional notification (FTR-008).
- **acceptance_criteria**:
  - [ ] Indicator is non-intrusive and can be disabled.
- **test_plan**:
  - Level: manual/UAT.

### FTR-033 — Self-maintenance utilities (dependency check + auto-update)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `DX`
- **area**: `infra`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-01`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Dependency check”, “Auto-update”)
- **scores**:
  - impact: 2
  - effort: 3
  - expertise: 2
  - risk: 3
  - novelty: 2
- **priority_score**: 0.67
- **user_value_proposition**:
  - Reduces setup friction and keeps plugin current.
- **scope**:
  - in:
    - Dependency checks with safe messaging.
    - Auto-update only if explicitly invoked by the user.
  - out:
    - Silent self-updating; auto-installing packages without consent.
- **implementation_steps**:
  1. Add a `redbull doctor` command that checks for `jq`/`claude`/optional `ollama`.
  2. If an update mechanism is added, make it explicit (`redbull update`) and non-destructive.
- **acceptance_criteria**:
  - [ ] No installs happen without explicit user invocation.
  - [ ] Clear instructions when deps are missing.
- **test_plan**:
  - Level: manual/UAT.

### FTR-025 — Cross-session explicit preferences (opt-in)

- **kind**: `improvement`
- **category**: `Conventional`
- **type**: `feature`
- **area**: `data`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-04`
- **sources**:
  - `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md` (FEAT-016)
- **scores**:
  - impact: 2
  - effort: 4
  - expertise: 4
  - risk: 3
  - novelty: 3
- **priority_score**: 0.50
- **user_value_proposition**:
  - Remembers explicit user preferences (verbosity, strictness) across sessions while keeping everything local and opt-in.
- **scope**:
  - in:
    - Store a small local preferences file under `~/.claude/redbull/`.
  - out:
    - Cloud sync; telemetry.
- **implementation_steps**:
  1. Define minimal preferences schema; store only when enabled.
  2. Apply preferences to judge prompts and artifact verbosity.
  3. Provide reset path (file deletion or command).
- **acceptance_criteria**:
  - [ ] Preferences never stored unless explicitly enabled.
  - [ ] Easy reset.
  - [ ] Defaults unchanged for users who never opt in.
- **test_plan**:
  - Level: manual UAT + small scripted tests.

### FTR-035 — Task progress bar (% complete estimation)

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `UX`
- **area**: `design`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-05`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Task progress bar”)
- **scores**:
  - impact: 2
  - effort: 4
  - expertise: 3
  - risk: 2
  - novelty: 4
- **priority_score**: 0.50
- **user_value_proposition**:
  - Gives a rough “percent complete” signal and uses it as a continuation hint.
- **scope**:
  - in:
    - A schema-bound “progress estimate” field from the judge.
  - out:
    - Treating progress estimates as truth; they are hints only.
- **implementation_steps**:
  1. Extend judge schema to emit `progress_percent`.
  2. Use as a weak signal in stop decision (never override explicit decision-needed stops).
- **acceptance_criteria**:
  - [ ] Progress estimate does not create continuation loops.
- **test_plan**:
  - Level: eval scenarios.

### FTR-036 — Multi-turn debate / second judge verification

- **kind**: `improvement`
- **category**: `Creative`
- **type**: `feature`
- **area**: `backend`
- **owner_role**: `Fullstack`
- **parent_epic_id**: `EPIC-02`
- **sources**:
  - `2025-12-21-features-redbull-brainstorm-gemini.md` (“Multi-turn debate”)
- **scores**:
  - impact: 2
  - effort: 4
  - expertise: 4
  - risk: 3
  - novelty: 4
- **priority_score**: 0.50
- **user_value_proposition**:
  - Potentially increases decision correctness by having a second judge verify close calls.
- **scope**:
  - in:
    - Second judge pass only on low-confidence cases (uses FTR-006 confidence).
  - out:
    - Always-on doubling of cost/latency.
- **implementation_steps**:
  1. Gate second-pass invocation by low confidence and strict caps.
  2. Ensure throttle and time limits to keep hook fast.
- **acceptance_criteria**:
  - [ ] Second pass is rare and bounded.
- **test_plan**:
  - Level: eval scenarios (low-confidence fixtures).

---

## Implementation Notes

- Prefer **MVP + extensions**: many ideas combine naturally (settings unlocks guardrails, verified-done, notifications, etc.), but keep first cuts small and bounded.
- Default posture should be **safe + opt-in** for anything that: auto-runs commands, changes stopping behavior beyond today, stores durable artifacts, or uses new hook events.
- If hook events beyond `Stop` are unavailable in the installed Claude Code version, implement “soft” equivalents within Stop (reduced effectiveness, but safer).

---

## Notes / Assumptions

- Assumes hooks remain bash-friendly with `jq` available and the `claude` CLI in PATH.
- Assumes `.claude/` repo-local artifacts and `~/.claude/redbull/` user-local state are acceptable storage locations (opt-in for user-local).
- Any feature that writes artifacts should:
  - Stay bounded (size + frequency).
  - Avoid recursion/judge-mode paths.
  - Apply secret redaction when model calls are involved (FTR-019).

---

## Source Coverage Matrix (Completeness)

This section maps every raw idea from the source brainstorms to exactly one consolidated ticket ID.

### `overall-features-for-the-plugin-brainstorm.md`
- Adaptive Throttling → FTR-022
- User Override Mechanism → FTR-003
- Analytics Dashboard → FTR-031
- Configurable Continuation Criteria → FTR-003
- Multi-Model Support → FTR-004
- Session Memory → FTR-024
- Verbose Debug Mode → FTR-005
- Cost Tracking → FTR-031
- Context Window Optimization → FTR-028
- Offline Fallback → FTR-027
- TodoWrite Integration → FTR-029
- Pre-emptive Continuation Signals → FTR-030
- User Feedback Loop → FTR-024
- Confidence Scoring → FTR-006
- Plugin Health Monitoring → FTR-031
- Natural Language Config → FTR-032
- Dry-Run Mode → FTR-007
- Continuation Streak Metrics → FTR-031
- Smart Context Selection → FTR-028
- Cross-Session Learning → FTR-024
- IMP-001 “Add Confidence Scoring to Continuation Decisions” → FTR-006
- IMP-002 “Implement TodoWrite Integration for Context” → FTR-029
- IMP-003 “Add Dry-Run Debugging Mode” → FTR-007
- IMP-004 “Create Offline Heuristic Fallback” → FTR-027
- IMP-005 “Implement Adaptive Throttling” → FTR-022
- IMP-006 “Add Plugin Health Observability” → FTR-031
- IMP-007 “Smart Context Selection Algorithm” → FTR-028
- IMP-008 “Natural Language Configuration” → FTR-032

### `2025-12-21-features-redbull-brainstorm-gemini.md`
- Explain Last Decision → FTR-005
- Smart Throttle Config → FTR-023
- Project-Specific Rules → FTR-002
- Configurable Judge Model → FTR-004
- Desktop Notifications → FTR-008
- Local LLM Adapter → FTR-026
- Adaptive Learning Loop → FTR-024
- Dry Run Mode → FTR-007
- Cost Tracker → FTR-031
- Global specific ignore → FTR-020
- “One More Shot” → FTR-003
- Status Bar Indicator → FTR-034
- JSON Output Log → FTR-005
- Personality settings → FTR-032
- Git-aware safety → FTR-018
- Task progress bar → FTR-035
- Dependency check → FTR-033
- Auto-update → FTR-033
- Context Window slider → FTR-028
- Multi-turn debate → FTR-036
- FEAT-001 “Explain Last Decision” → FTR-005
- FEAT-002 “Smart Throttle Config” → FTR-023
- FEAT-003 “Project-Specific Rules” → FTR-002
- FEAT-004 “Configurable Judge Model” → FTR-004
- FEAT-005 “Desktop Notifications” → FTR-008
- FEAT-006 “Local LLM Adapter” → FTR-026
- FEAT-007 “Adaptive Learning Loop” → FTR-024

### `2025-12-21-game-changing-features-that-utilize-hooks-brainstorm-codex.md`
- FEAT-001 “Add per-project autonomy controls settings file” → FTR-001
- FEAT-002 “Write a handoff snapshot on Stop/SessionEnd” → FTR-009
- FEAT-003 “Block dangerous tool commands with safe alternatives” → FTR-014
- FEAT-004 “Auto-bootstrap context on SessionStart (read repo docs/plans)” → FTR-010
- FEAT-005 “PostToolUse failure triage → next-action plan + stop gating” → FTR-016
- FEAT-006 “Enforce verified done: run proving commands before Stop/commit” → FTR-015
- FEAT-007 “PreCompact state pack generator” → FTR-011
- FEAT-008 “Adaptive continuation dial (learns when to continue/stop)” → FTR-024
- FEAT-009 “Hook-orchestrated multi-agent pipeline for big tasks” → FTR-037
- FEAT-010 “Redact secrets before sending transcript context to judge model” → FTR-019
- FEAT-011 “Maintain a worklog timeline + undo hints” → FTR-012
- FEAT-012 “Notification-based next best action nudges during idle moments” → FTR-008
- FEAT-013 “Create a decision-tracker artifact when a user decision is detected” → FTR-013
- FEAT-014 “Smarter continuation throttling (loop detection + cooldowns)” → FTR-021
- FEAT-015 “Parse tool errors and surface targeted fix commands suggestions” → FTR-017
- FEAT-016 “Cross-session personalization of prompts and thresholds” → FTR-025
