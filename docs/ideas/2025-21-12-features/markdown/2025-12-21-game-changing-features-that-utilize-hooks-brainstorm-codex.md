# Brainstorm: Game Changing Features That Utilize Hooks

## 1) Focus Summary

**Purpose**
- Use Claude Code hooks (Stop, PreToolUse, PostToolUse, SessionStart/End, PreCompact, etc.) to remove friction, prevent mistakes, and keep work moving without extra user prompts.

**Key flows**
- Intercept “stop” moments and either (a) proceed automatically with safe, obvious next steps or (b) stop when a user decision is required.
- Intercept tool execution to (a) prevent dangerous actions, (b) turn failures into actionable next steps, and (c) enforce “done means verified”.
- Persist lightweight “project memory” artifacts (handoff notes, state packs) to reduce context loss across sessions/compactions.

**Constraints**
- Hooks must be deterministic, fast, and safe-by-default; avoid long-running work in a hook unless explicitly user-opted-in.
- The hook runtime is shell-script friendly; prefer `jq` + `claude` CLI patterns already used in this repo.
- No new dependencies, schema changes, or breaking contract changes without explicit approval.

**Risks / unknowns**
- Exact hook event coverage and payload schemas depend on Claude Code version; some events may be unavailable or have different fields.
- “Auto-run commands” features must respect user security posture and avoid surprising destructive behavior.
- LLM variance: anything that relies on model classification needs robust throttling, fallbacks, and eval scenarios.

---

## 2) Candidate Brainstorm (Unfiltered, max 20) + Scoring

Scales: `impact/effort/expertise/risk/novelty` are integers `1–5`. `priority_score = round(impact/effort, 2)`.

| ID | Candidate Title | Category | Type | Impact | Effort | Exp. | Risk | Novelty | Priority |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| FEAT-001 | Add per-project “autonomy controls” settings file | Conventional | feature | 3 | 1 | 2 | 1 | 2 | 3.00 |
| FEAT-002 | Write a handoff snapshot on Stop/SessionEnd | Conventional | feature | 5 | 2 | 2 | 1 | 2 | 2.50 |
| FEAT-003 | Block dangerous tool commands with safe alternatives | Conventional | feature | 5 | 2 | 3 | 2 | 3 | 2.50 |
| FEAT-004 | Auto-bootstrap context on SessionStart (read repo docs/plans) | Conventional | feature | 4 | 2 | 2 | 2 | 2 | 2.00 |
| FEAT-005 | PostToolUse failure triage → next-action plan + stop gating | Conventional | feature | 4 | 2 | 3 | 2 | 3 | 2.00 |
| FEAT-006 | Enforce “verified done”: run proving commands before Stop/commit | Conventional | feature | 5 | 3 | 3 | 3 | 2 | 1.67 |
| FEAT-007 | (Creative) PreCompact “state pack” generator (context budget autopilot) | Creative | feature | 5 | 3 | 3 | 3 | 4 | 1.67 |
| FEAT-008 | (Creative) Adaptive continuation dial (learns when to continue/stop) | Creative | feature | 4 | 3 | 4 | 3 | 4 | 1.33 |
| FEAT-009 | (Moonshot) Hook-orchestrated multi-agent pipeline for big tasks | Moonshot | feature | 5 | 4 | 5 | 4 | 5 | 1.25 |
| FEAT-010 | Redact secrets before sending transcript context to judge model | Conventional | feature | 4 | 3 | 4 | 2 | 3 | 1.33 |
| FEAT-011 | Maintain a worklog timeline + reversible “undo hints” stack | Conventional | feature | 4 | 4 | 3 | 3 | 3 | 1.00 |
| FEAT-012 | Notification-based “next best action” nudges during idle moments | Conventional | feature | 3 | 3 | 2 | 2 | 3 | 1.00 |
| FEAT-013 | Create a decision-tracker artifact when a user decision is detected | Conventional | feature | 3 | 3 | 2 | 1 | 2 | 1.00 |
| FEAT-014 | Smarter continuation throttling (loop detection + cooldowns) | Conventional | feature | 3 | 3 | 3 | 2 | 2 | 1.00 |
| FEAT-015 | Parse tool errors and surface targeted “fix commands” suggestions | Conventional | feature | 3 | 4 | 3 | 2 | 3 | 0.75 |
| FEAT-016 | Cross-session personalization of prompts and thresholds | Conventional | feature | 2 | 4 | 4 | 3 | 3 | 0.50 |

Candidate coverage checklist (explicit):
- Common pain point: FEAT-003 (dangerous commands), FEAT-006 (unverified “done”)
- New use case/workflow: FEAT-009 (pipeline orchestration), FEAT-007 (state pack)
- Productivity/efficiency: FEAT-005, FEAT-004
- UX/delight: FEAT-002, FEAT-012
- Competitive differentiation: FEAT-007, FEAT-008, FEAT-009

---

## 3) Top Features (Ranked)

| # | ID | Title | Cat. | Impact | Effort | Exp. | Risk | Novelty | Priority | Targets / Search |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | FEAT-001 | Add per-project “autonomy controls” settings file | Conventional | 3 | 1 | 2 | 1 | 2 | 3.00 | `hooks/` `settings` `.claude/*.local.md` `enabled` `aggressiveness` |
| 2 | FEAT-002 | Write a handoff snapshot on Stop/SessionEnd | Conventional | 5 | 2 | 2 | 1 | 2 | 2.50 | `Stop` `SessionEnd` `handoff` `summary` `.claude/` |
| 3 | FEAT-003 | Block dangerous tool commands with safe alternatives | Conventional | 5 | 2 | 3 | 2 | 3 | 2.50 | `PreToolUse` `rm -rf` `git reset --hard` `curl|sh` `guardrail` |
| 4 | FEAT-004 | Auto-bootstrap context on SessionStart (read repo docs/plans) | Conventional | 4 | 2 | 2 | 2 | 2 | 2.00 | `SessionStart` `AGENTS.md` `README.md` `PLAN.md` `docs/plans` |
| 5 | FEAT-005 | PostToolUse failure triage → next-action plan + stop gating | Conventional | 4 | 2 | 3 | 2 | 3 | 2.00 | `PostToolUse` `stderr` `triage` `next steps` `block stop` |
| 6 | FEAT-006 | Enforce “verified done”: run proving commands before Stop/commit | Conventional | 5 | 3 | 3 | 3 | 2 | 1.67 | `Stop` `git commit` `typecheck` `lint` `test` `build` |
| 7 | FEAT-007 | (Creative) PreCompact “state pack” generator (context budget autopilot) | Creative | 5 | 3 | 3 | 3 | 4 | 1.67 | `PreCompact` `state pack` `context budget` `pin` `summary` |
| 8 | FEAT-010 | Redact secrets before sending transcript context to judge model | Conventional | 4 | 3 | 4 | 2 | 3 | 1.33 | `redaction` `secrets` `transcript` `judge` `privacy` |
| 9 | FEAT-008 | (Creative) Adaptive continuation dial (learns when to continue/stop) | Creative | 4 | 3 | 4 | 3 | 4 | 1.33 | `adaptive` `autonomy` `threshold` `throttle` `per repo` |
| 10 | FEAT-009 | (Moonshot) Hook-orchestrated multi-agent pipeline for big tasks | Moonshot | 5 | 4 | 5 | 4 | 5 | 1.25 | `pipeline` `planner` `reviewer` `orchestration` `hooks` |

---

## 4) Rationale for #1

`FEAT-001` is the best impact/effort win because it makes every other hook feature safer and more user-friendly by letting users tune aggressiveness per repo without code changes. It reduces “surprise automation” risk while enabling power users to opt into stronger autonomy.

---

## 5) Epics

### EPIC-01 — Autonomy That Respects User Control
- **Goal:** Keep momentum high while ensuring the assistant stops for real decisions and respects per-project preferences.
- **Child features:** FEAT-001, FEAT-005, FEAT-008, FEAT-009, FEAT-012, FEAT-014, FEAT-015, FEAT-016

### EPIC-02 — Safety + Quality Guardrails
- **Goal:** Prevent irreversible mistakes and make “done” actually mean “verified”.
- **Child features:** FEAT-003, FEAT-006, FEAT-010

### EPIC-03 — Project Memory + Context Resilience
- **Goal:** Reduce context loss across sessions and compactions with durable, minimal artifacts.
- **Child features:** FEAT-002, FEAT-004, FEAT-007, FEAT-011, FEAT-013

---

## 6) Detailed Feature Tickets (Selected Top 10)

### FEAT-001 — Add per-project “autonomy controls” settings file
- kind: improvement
- category: Conventional
- type: feature
- area: design
- owner_role: Fullstack
- parent_epic: EPIC-01
- scores: impact=3 effort=1 expertise=2 risk=1 novelty=2 priority_score=3.00
- user value proposition: Lets users control how aggressive hooks are (continue behavior, auto-run commands, guardrails strictness) per repo, reducing surprise automation and making the plugin broadly adoptable.
- scope:
  - in: Read `.claude/double-shot-latte.local.md` (or repo-standard equivalent) with YAML frontmatter; support `enabled`, `aggressiveness`, and feature toggles for major hook behaviors.
  - out: Global user settings UI; syncing settings across machines.
- implementation steps:
  1. Define a minimal YAML schema (fail-closed defaults) and parsing helper in bash (`yq`-free; parse frontmatter with `awk/sed` + `jq`-style validation via Claude schema or strict regex).
  2. Add a shared `hooks/lib/settings.sh` helper used by all hook scripts.
  3. Update existing Stop hook script to respect `enabled` and `aggressiveness`.
  4. Document supported keys in `README.md` (short section) and add `.claude/*.local.md` to `.gitignore` if needed.
- acceptance criteria:
  - [ ] Users can disable the plugin per repo without uninstalling it.
  - [ ] Default behavior is unchanged when the settings file is missing.
  - [ ] Invalid settings fail closed (safe defaults) and do not break the hook.
- test plan:
  - Level: eval scenarios + manual UAT.
  - Location: `test/evals/scenarios/` (add 2–3 scenarios: missing file, disabled, aggressive).
  - UAT: install locally and confirm toggles change continuation behavior in a real repo.
- targets + search tokens: `plugin settings`, `.claude/*.local.md`, `enabled: false`, `aggressiveness`, `hooks/lib/settings.sh`
- experiment category: none

### FEAT-002 — Write a handoff snapshot on Stop/SessionEnd
- kind: improvement
- category: Conventional
- type: feature
- area: backend
- owner_role: Fullstack
- parent_epic: EPIC-03
- scores: impact=5 effort=2 expertise=2 risk=1 novelty=2 priority_score=2.50
- user value proposition: When the assistant stops (legitimately), users get an instant, structured handoff with current status, what changed, and the next 3 actions—reducing “where was I?” friction and enabling fast resumes.
- scope:
  - in: On `Stop` (and/or `SessionEnd`), write a short markdown file under `.claude/` with summary, progress, next steps, commands to run, and files touched.
  - out: Long historical logging; storing sensitive content outside the repo.
- implementation steps:
  1. Extract last N transcript entries (existing pattern) and summarize with a strict JSON schema.
  2. Pull basic repo signals (git branch, `git diff --name-only`, last command run if available) when safe.
  3. Write `.claude/handoff.md` (or timestamped files) with deterministic formatting.
  4. Add throttle/size limits and skip writing if the session is in judge mode.
- acceptance criteria:
  - [ ] On an approved stop, a handoff file is produced with “Status”, “Next steps”, and “Files touched”.
  - [ ] The artifact excludes secrets by default (see FEAT-010) and never writes outside the repo.
  - [ ] The hook remains fast (no more than one model call).
- test plan:
  - Level: eval scenarios + manual UAT.
  - Location: `test/evals/scenarios/` (stop-approved cases assert handoff metadata fields present).
  - UAT: run a multi-step change, stop, and confirm the handoff is actionable.
- targets + search tokens: `handoff`, `.claude/`, `SessionEnd`, `Stop`, `files touched`, `next steps`
- experiment category: none

### FEAT-003 — Block dangerous tool commands with safe alternatives
- kind: improvement
- category: Conventional
- type: feature
- area: backend
- owner_role: Fullstack
- parent_epic: EPIC-02
- scores: impact=5 effort=2 expertise=3 risk=2 novelty=3 priority_score=2.50
- user value proposition: Prevents catastrophic mistakes (data loss, repo damage, credential leaks) by intercepting risky commands before they run and offering a safer, user-approved alternative.
- scope:
  - in: `PreToolUse` interception for shell commands and file writes; pattern-based “deny list” with contextual allow rules and suggested safer replacements.
  - out: Complex policy DSL; enterprise RBAC.
- implementation steps:
  1. Implement a `hooks/claude-guardrail-pretooluse.sh` that receives tool payload JSON and matches against a curated risk set (e.g., `rm -rf`, `git reset --hard`, `chmod -R 777`, `curl|sh`).
  2. Produce a structured decision: `block` with a reason and a “safe alternative” command.
  3. Add opt-out via FEAT-001 settings (e.g., `guardrails: strict|off`).
  4. Add “allowed paths” safeguards (e.g., block deletes outside workspace).
- acceptance criteria:
  - [ ] The hook blocks known-danger patterns and provides a safer suggested alternative.
  - [ ] Users can disable or relax guardrails per repo via settings.
  - [ ] The hook does not block read-only commands (e.g., `ls`, `rg`) and has low false positives.
- test plan:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (add scenarios for each blocked pattern + allowed safe equivalents).
  - UAT: attempt a risky command in a test repo and confirm the hook blocks it.
- targets + search tokens: `PreToolUse`, `guardrail`, `deny list`, `safe alternative`, `rm -rf`, `git reset --hard`
- experiment category: none

### FEAT-004 — Auto-bootstrap context on SessionStart (read repo docs/plans)
- kind: improvement
- category: Conventional
- type: feature
- area: backend
- owner_role: Fullstack
- parent_epic: EPIC-03
- scores: impact=4 effort=2 expertise=2 risk=2 novelty=2 priority_score=2.00
- user value proposition: Reduces repeated “what is this repo?” overhead by automatically surfacing the repo’s working agreements (AGENTS/README/plans) at the start of a session, improving correctness and reducing back-and-forth.
- scope:
  - in: On `SessionStart`, detect and summarize key repo guidance files into a compact “session brief”.
  - out: Full codebase indexing; heavy scanning.
- implementation steps:
  1. Locate “guidance files” (`AGENTS.md`, `README.md`, `CLAUDE.md`, `PLAN.md`, `docs/plans/**`) with strict limits.
  2. Produce a small, structured brief (JSON → rendered markdown) with “commands”, “quality gates”, and “gotchas”.
  3. Inject the brief as a hook message or artifact file accessible to the assistant.
  4. Respect FEAT-001 settings for size/verbosity.
- acceptance criteria:
  - [ ] New sessions start with a brief that lists key commands and repo constraints.
  - [ ] Brief generation is bounded (time + file size) and never leaks secrets.
  - [ ] If files are missing, the hook degrades gracefully (no errors).
- test plan:
  - Level: manual UAT + lightweight scripted test.
  - Location: add a small harness under `test/` or scenario fixtures that simulate SessionStart payloads.
  - UAT: start a session in a repo with/without guidance files and compare outcomes.
- targets + search tokens: `SessionStart`, `session brief`, `AGENTS.md`, `CLAUDE.md`, `PLAN.md`, `docs/plans`
- experiment category: none

### FEAT-005 — PostToolUse failure triage → next-action plan + stop gating
- kind: improvement
- category: Conventional
- type: feature
- area: backend
- owner_role: Fullstack
- parent_epic: EPIC-01
- scores: impact=4 effort=2 expertise=3 risk=2 novelty=3 priority_score=2.00
- user value proposition: When a tool fails (tests, build, command), the plugin immediately converts the failure into a concrete repair plan and prevents premature stopping until at least one corrective action is attempted.
- scope:
  - in: `PostToolUse` detects non-zero exit, captures stderr/stdout, summarizes root cause and suggests next 1–3 commands; optionally blocks stop if unresolved and user hasn’t asked to stop.
  - out: Auto-fixing without user consent; running destructive remediation.
- implementation steps:
  1. Parse tool results (exit code + output) and classify error types (test failure, missing deps, permission, lint, typecheck).
  2. Generate a bounded “next action plan” with strict schema and no tool calls in judge mode.
  3. Feed “unresolved error state” into the Stop judge so it continues (blocks stop) until triage is acknowledged.
  4. Add throttling to avoid loops (link with FEAT-014 patterns later if needed).
- acceptance criteria:
  - [ ] After a failing tool run, the user sees a short plan with 1–3 concrete next commands.
  - [ ] The assistant does not stop immediately after a failure unless the user explicitly requests stopping.
  - [ ] Behavior is opt-out via settings.
- test plan:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (add failure transcripts that previously stopped; assert “continue”).
  - UAT: run `./test/evals/run-evals.sh` and confirm scenario stability (5/5).
- targets + search tokens: `PostToolUse`, `exit code`, `triage`, `next action`, `unresolved`, `block stop`
- experiment category: none

### FEAT-006 — Enforce “verified done”: run proving commands before Stop/commit
- kind: improvement
- category: Conventional
- type: feature
- area: backend
- owner_role: Fullstack
- parent_epic: EPIC-02
- scores: impact=5 effort=3 expertise=3 risk=3 novelty=2 priority_score=1.67
- user value proposition: Prevents “looks done” outcomes by automatically running the repo’s proving commands (typecheck/lint/test/build) before allowing a final stop or permitting a commit, reducing regressions and review churn.
- scope:
  - in: Detect language/tooling and run configured quality gates (or infer defaults) when the assistant claims completion or attempts to stop.
  - out: Running commands in repos without explicit user opt-in; network installs or modifying lockfiles.
- implementation steps:
  1. Detect proving commands from repo conventions (`package.json`, `Makefile`, `README`, or an explicit config).
  2. If user has opted in (FEAT-001), run gates in order with clear logging and stop-on-failure.
  3. Feed results into the Stop judge decision (block stop if gates failed or unrun).
  4. Cache results per session to avoid repeat runs.
- acceptance criteria:
  - [ ] When enabled, “final stop” triggers the configured gate sequence and blocks stop on failure.
  - [ ] When disabled or unknown, behavior remains unchanged (no surprise runs).
  - [ ] The hook never runs install steps or writes secrets.
- test plan:
  - Level: manual UAT + eval scenarios for “claims done without tests”.
  - Location: `test/evals/scenarios/` (simulate assistant claiming completion; assert continue until gates reported).
  - UAT: enable in a TypeScript repo and verify it runs `typecheck → lint → test → build`.
- targets + search tokens: `verified done`, `quality gates`, `typecheck`, `lint`, `test`, `build`, `git commit`
- experiment category: none

### FEAT-007 — (Creative) PreCompact “state pack” generator (context budget autopilot)
- kind: improvement
- category: Creative
- type: feature
- area: design
- owner_role: Fullstack
- parent_epic: EPIC-03
- scores: impact=5 effort=3 expertise=3 risk=3 novelty=4 priority_score=1.67
- user value proposition: After compaction, Claude often “forgets” key constraints and progress; a hook-generated state pack preserves the essentials so work continues smoothly with fewer regressions.
- scope:
  - in: On `PreCompact`, synthesize a compact state pack (goals, constraints, current progress, next steps, commands run, key file list) and store it as an artifact (and/or inject into prompt).
  - out: Large, verbose summaries; anything that increases token usage without bounds.
- implementation steps:
  1. Collect bounded inputs: last N transcript entries, changed file list, last known plan/TODOs.
  2. Ask the model for a “state pack” JSON object with strict size limits.
  3. Persist `.claude/state-pack.md` (and/or `.json`) and ensure next-session bootstrap surfaces it (FEAT-004 synergy).
  4. Add guardrails to avoid including secrets (FEAT-010).
- acceptance criteria:
  - [ ] After compaction, the assistant reliably retains the main constraints and next steps from the state pack.
  - [ ] State pack size is bounded and deterministic in structure.
  - [ ] Users can disable this behavior per repo.
- test plan:
  - Level: eval scenarios + UAT.
  - Location: `test/evals/scenarios/` (simulate compaction-caused forgetting; assert improved continuation decisions).
  - UAT: run a long task, compact, and confirm the assistant resumes with correct context.
- targets + search tokens: `PreCompact`, `state pack`, `context budget`, `resume`, `.claude/state-pack.md`
- experiment category: creative
- small experiment (1–2 hours): Implement a minimal PreCompact hook that writes a 10-bullet state pack from the last 10 transcript entries.
- success metric: In a 10-scenario eval set, post-compact “forgot constraints” failures drop by ≥50%.
- rollback plan: Feature-flag behind settings; default off; delete the hook entry and artifacts if noisy.

### FEAT-008 — (Creative) Adaptive continuation dial (learns when to continue/stop)
- kind: improvement
- category: Creative
- type: feature
- area: data
- owner_role: Fullstack
- parent_epic: EPIC-01
- scores: impact=4 effort=3 expertise=4 risk=3 novelty=4 priority_score=1.33
- user value proposition: Different users/repos prefer different autonomy levels; adaptive tuning reduces both “annoying stops” and “over-eager continuation” by learning from outcomes.
- scope:
  - in: Maintain a tiny per-repo “preference signal” (e.g., user typed `continue` after an approved stop, or user frequently asked it to stop) and adjust continuation thresholds.
  - out: Complex ML; sharing data across repos/users.
- implementation steps:
  1. Record a minimal “decision outcome” marker per session in `~/.claude/redbull/` or repo-local `.claude/` (opt-in).
  2. Adjust judge prompt thresholds (“be more/less aggressive”) based on the signal.
  3. Add hard caps and resets (never exceed safety limits).
  4. Expose the learned level in the handoff snapshot for transparency (FEAT-002).
- acceptance criteria:
  - [ ] Over time, the plugin adapts (within bounds) to reduce unwanted stopping in a repo.
  - [ ] Users can reset learned preferences and fully disable learning.
  - [ ] Adaptation never overrides explicit user requests to stop or ask questions.
- test plan:
  - Level: eval scenarios + UAT.
  - Location: `test/evals/scenarios/` (simulate sequences where user says “continue”; assert more aggressive mode after threshold).
  - UAT: use the plugin in one repo for a day and verify behavior shifts predictably.
- targets + search tokens: `adaptive`, `learning`, `threshold`, `aggressiveness`, `continue`, `approve stop`
- experiment category: creative
- small experiment (1–2 hours): Add a single scalar “aggressiveness” that increases when the user types `continue` within 60 seconds of an approved stop.
- success metric: In manual use, ≥30% fewer “type continue” moments over 1 hour of work.
- rollback plan: Disable learning by default; delete stored preference files; fall back to static thresholds.

### FEAT-009 — (Moonshot) Hook-orchestrated multi-agent pipeline for big tasks
- kind: improvement
- category: Moonshot
- type: feature
- area: infra
- owner_role: Fullstack
- parent_epic: EPIC-01
- scores: impact=5 effort=4 expertise=5 risk=4 novelty=5 priority_score=1.25
- user value proposition: Turns Claude Code into a “mini team” for large requests—planner → implementer → reviewer—without the user needing to micromanage, dramatically improving throughput and reducing missed steps.
- scope:
  - in: Use hooks to trigger specialized evaluation phases at key moments (on large prompts, before Stop, after tests) and feed structured guidance back to the main session.
  - out: Background daemons; external services; anything requiring new dependencies.
- implementation steps:
  1. Define pipeline stages and triggers (e.g., `UserPromptSubmit` for plan extraction, `PostToolUse` for review, `Stop` for final QA).
  2. Implement stage prompts as strict classifiers producing actionable JSON outputs.
  3. Persist stage outputs as artifacts (`.claude/pipeline/`) and surface them to the user/assistant at the right time.
  4. Add aggressive throttling and kill switches (FEAT-001).
- acceptance criteria:
  - [ ] For a multi-step task, the pipeline produces a plan, verification checklist, and final PR-ready summary.
  - [ ] The pipeline never runs tools itself; it only produces structured guidance.
  - [ ] Users can disable the pipeline globally/per repo.
- test plan:
  - Level: eval scenarios + UAT.
  - Location: `test/evals/scenarios/` (add “big task” transcripts; assert plan + checklist artifacts referenced before stopping).
  - UAT: run an end-to-end “build feature X” task and confirm fewer missed steps.
- targets + search tokens: `pipeline`, `planner`, `reviewer`, `checklist`, `UserPromptSubmit`, `Stop`, `.claude/pipeline`
- experiment category: moonshot
- small experiment (1–2 hours): Add a Stop-stage “reviewer” that checks whether quality gates were run and whether there are TODOs, then blocks stop if missing.
- success metric: In evals, reduce “stopped without tests” failures by ≥70% across a targeted scenario subset.
- rollback plan: Keep it fully behind a feature flag; if noisy, remove the hook entry and delete `.claude/pipeline` artifacts.

### FEAT-010 — Redact secrets before sending transcript context to judge model
- kind: improvement
- category: Conventional
- type: feature
- area: security
- owner_role: Fullstack
- parent_epic: EPIC-02
- scores: impact=4 effort=3 expertise=4 risk=2 novelty=3 priority_score=1.33
- user value proposition: Reduces the chance of leaking secrets or sensitive data to the judge model by filtering common secret patterns and repo-local sensitive files before any model call.
- scope:
  - in: Redact tokens/keys/password-like strings in transcript excerpts; optionally omit lines referencing `.env` or credential files.
  - out: Perfect secret detection; replacing a real secrets scanner.
- implementation steps:
  1. Add a bounded redaction pass over extracted transcript content (regex patterns + allowlist for safe strings).
  2. Ensure all model-bound payloads go through the redactor (Stop judge, state pack, triage).
  3. Add transparency: annotate the output reason with “redactions applied” counts.
  4. Allow per-repo opt-out only in “unsafe” explicit mode via settings.
- acceptance criteria:
  - [ ] Common secret patterns are redacted before any model call.
  - [ ] Redaction does not break JSON schemas or hook behavior.
  - [ ] The plugin never logs raw secrets to stdout/stderr.
- test plan:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (add transcript fixtures containing fake keys; assert redacted output passed to model).
  - UAT: run a scenario with a fake token in chat; confirm logs show redaction.
- targets + search tokens: `redact`, `secrets`, `API_KEY`, `Authorization: Bearer`, `.env`, `transcript`
- experiment category: none

---

## 7) Backlog Candidate Tickets (Not Selected in Top 10)

### FEAT-011 — Maintain a worklog timeline + reversible “undo hints” stack
- kind: improvement
- category: Conventional
- type: feature
- area: data
- owner_role: Fullstack
- parent_epic: EPIC-03
- scores: impact=4 effort=4 expertise=3 risk=3 novelty=3 priority_score=1.00
- user value proposition: Gives users a clear, searchable “what happened” trail (commands run, files touched, diffs) plus safe rollback hints, reducing fear and speeding recovery from mistakes.
- scope:
  - in: Append-only worklog artifacts under `.claude/` and “undo hints” generated on demand.
  - out: Automatic rollbacks; deep VCS integrations beyond `git`.
- implementation steps:
  1. Record a minimal event log on `PostToolUse` (timestamp, tool, exit code, touched files).
  2. Add a Stop-stage summarizer that condenses the log into “Work done” + “Undo hints”.
  3. Add strict retention limits (max entries/size) and opt-in via FEAT-001.
- acceptance criteria:
  - [ ] Users can open a `.claude/worklog.md` and understand key actions taken.
  - [ ] Undo hints are non-destructive and phrased as suggestions (never auto-executed).
  - [ ] Logging is bounded and disabled by default in sensitive repos (configurable).
- test plan:
  - Level: manual UAT + small fixture tests.
  - Location: add a small `test/evals/scenarios/` case asserting worklog metadata appears in Stop output.
  - UAT: run a short editing session and confirm worklog entries look correct.
- targets + search tokens: `worklog`, `undo hints`, `PostToolUse`, `.claude/worklog.md`
- experiment category: none

### FEAT-012 — Notification-based “next best action” nudges during idle moments
- kind: improvement
- category: Conventional
- type: feature
- area: design
- owner_role: Fullstack
- parent_epic: EPIC-01
- scores: impact=3 effort=3 expertise=2 risk=2 novelty=3 priority_score=1.00
- user value proposition: Reduces stalls by suggesting the next best action (run tests, open a file, check logs) when the session is drifting without forcing continuation.
- scope:
  - in: Lightweight nudges on supported hook events (e.g., idle/notification events) with opt-in.
  - out: Chatty spam; interrupting users mid-typing.
- implementation steps:
  1. Detect “idle-like” states from recent messages/tool events (bounded heuristic).
  2. Generate a single suggested next action (or none) using a strict schema.
  3. Rate-limit nudges and provide an off switch (FEAT-001).
- acceptance criteria:
  - [ ] Nudges occur at most once per configured window.
  - [ ] Nudges are actionable (a concrete command or file to open) and never destructive.
  - [ ] Users can disable nudges per repo.
- test plan:
  - Level: manual UAT.
  - Location: add one eval scenario verifying no nudges are produced when the user asks a question.
  - UAT: run a session, pause, and confirm a single helpful suggestion appears.
- targets + search tokens: `Notification`, `idle`, `next best action`, `nudge`, `rate limit`
- experiment category: none

### FEAT-013 — Create a decision-tracker artifact when a user decision is detected
- kind: improvement
- category: Conventional
- type: feature
- area: design
- owner_role: Fullstack
- parent_epic: EPIC-03
- scores: impact=3 effort=3 expertise=2 risk=1 novelty=2 priority_score=1.00
- user value proposition: When the assistant needs a user decision, it captures the open questions and options in a durable place, reducing repeated clarification loops.
- scope:
  - in: On Stop approval due to “decision needed”, write `.claude/decisions.md` with questions, options, and recommended default.
  - out: Enforcing decisions; automatically choosing on the user’s behalf.
- implementation steps:
  1. Extend the Stop judge schema to output `decision_needed=true` plus a list of questions/options.
  2. Render the artifact deterministically under `.claude/`.
  3. Link the artifact in the Stop reason and in the handoff snapshot (FEAT-002).
- acceptance criteria:
  - [ ] When the assistant stops for a decision, `.claude/decisions.md` is created/updated.
  - [ ] The artifact includes at least one clear question and 2–3 options when applicable.
  - [ ] No artifact is written when stopping for completion (non-decision).
- test plan:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (decision-required transcripts assert stop approved and artifact fields present).
  - UAT: trigger a design-choice stop and confirm the artifact is useful.
- targets + search tokens: `decisions`, `decision needed`, `.claude/decisions.md`, `options`, `recommendation`
- experiment category: none

### FEAT-014 — Smarter continuation throttling (loop detection + cooldowns)
- kind: improvement
- category: Conventional
- type: feature
- area: backend
- owner_role: Fullstack
- parent_epic: EPIC-01
- scores: impact=3 effort=3 expertise=3 risk=2 novelty=2 priority_score=1.00
- user value proposition: Prevents rare but frustrating “continue loops” by detecting repeated stop→continue cycles and automatically backing off or requiring user confirmation.
- scope:
  - in: Add loop heuristics (same last assistant message, repeated failures, unchanged files) and adaptive cooldowns.
  - out: Complex analytics; cross-repo shared state.
- implementation steps:
  1. Extend throttle file format to include a small rolling fingerprint history.
  2. Detect repeat patterns and downgrade aggressiveness temporarily.
  3. Surface a clear explanation in the Stop reason when backing off.
- acceptance criteria:
  - [ ] The plugin stops continuing after repeated identical cycles within a window.
  - [ ] Backoff is temporary and resets after a cooldown.
  - [ ] Users can override backoff via settings.
- test plan:
  - Level: eval scenarios.
  - Location: `test/evals/scenarios/` (create a loop transcript; assert stop eventually approved).
  - UAT: induce a loop and confirm the plugin backs off predictably.
- targets + search tokens: `throttle`, `loop detection`, `cooldown`, `/tmp/.claude-continue-throttle-*`
- experiment category: none

### FEAT-015 — Parse tool errors and surface targeted “fix commands” suggestions
- kind: improvement
- category: Conventional
- type: feature
- area: backend
- owner_role: Fullstack
- parent_epic: EPIC-01
- scores: impact=3 effort=4 expertise=3 risk=2 novelty=3 priority_score=0.75
- user value proposition: Speeds recovery from common failures by suggesting the most likely next command(s) based on error signatures, reducing time spent interpreting logs.
- scope:
  - in: Lightweight signature matching for common toolchains (Node, Python, Go) and a fallback model summarizer.
  - out: Building a full error knowledgebase; auto-running fixes.
- implementation steps:
  1. Add a small signature map (regex → suggested commands) with strict bounds.
  2. If no signature matches, call the model for a 1–2 command suggestion (schema-bound).
  3. Integrate with FEAT-005 triage so suggestions appear immediately after failures.
- acceptance criteria:
  - [ ] For recognized errors, the suggestion is deterministic and safe.
  - [ ] Suggestions never include destructive commands by default (respect FEAT-003).
  - [ ] The hook remains fast and bounded.
- test plan:
  - Level: fixture tests + eval scenarios.
  - Location: add scenario fixtures with known stderr snippets and assert suggestions.
  - UAT: run a failing command and verify suggestion quality.
- targets + search tokens: `error signatures`, `regex`, `suggested commands`, `stderr`, `triage`
- experiment category: none

### FEAT-016 — Cross-session personalization of prompts and thresholds
- kind: improvement
- category: Conventional
- type: feature
- area: data
- owner_role: Fullstack
- parent_epic: EPIC-01
- scores: impact=2 effort=4 expertise=4 risk=3 novelty=3 priority_score=0.50
- user value proposition: Reduces repeated configuration by remembering user preferences (verbosity, strictness) across sessions while keeping everything local and opt-in.
- scope:
  - in: Store a small local preferences file under `~/.claude/redbull/` with explicit opt-in.
  - out: Cloud sync; collecting telemetry.
- implementation steps:
  1. Define a minimal preferences schema and store locally when enabled.
  2. Apply preferences to judge prompts and artifact verbosity.
  3. Provide an explicit reset command or file deletion path.
- acceptance criteria:
  - [ ] Preferences are never stored unless explicitly enabled.
  - [ ] Users can reset preferences easily.
  - [ ] Defaults remain unchanged for users who never opt in.
- test plan:
  - Level: manual UAT.
  - Location: add a small scripted test verifying preferences file read/write behavior.
  - UAT: enable personalization and confirm behavior persists across sessions.
- targets + search tokens: `preferences`, `~/.claude/redbull`, `opt-in`, `reset`, `verbosity`, `strictness`
- experiment category: none

---

## Notes / Assumptions

- Assumes Claude Code supports additional hook events beyond `Stop` (e.g., `PreToolUse`, `PostToolUse`, `SessionStart`, `PreCompact`). If some are unavailable, the same concepts can be implemented as Stop-only “soft guardrails” with reduced effectiveness.
- Assumes hooks can safely write repo-local artifacts under `.claude/` and (when necessary) user-local state under `~/.claude/redbull` without triggering recursion (existing judge-mode pattern applies).
- Assumes users want opt-in for anything that auto-runs commands; all such behaviors are gated behind FEAT-001 settings by default.
