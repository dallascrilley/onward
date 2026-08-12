# Changelog

All notable changes to Onward will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-08-12

### Changed

- **Renamed to Onward.** The project was previously called "Redbull for Claude Code" (plugin name `redbull`), which borrowed a registered trademark it has nothing to do with. Everything user-facing moved with the name, and there are no compatibility shims:
  - Environment variables: `REDBULL_*` are now `ONWARD_*` (for example `REDBULL_DRY_RUN` is now `ONWARD_DRY_RUN`).
  - State directory: `~/.claude/redbull/` is now `~/.claude/onward/`. Move the directory to keep your decision history, or let it be recreated.
  - Per-project settings: `.claude/redbull.local.md` is now `.claude/onward.local.md`.
  - Ignore patterns: `.redbull/ignore.txt` and `.claude/redbull-ignore.txt` are now `.onward/ignore.txt` and `.claude/onward-ignore.txt`.
  - Project rules: `.redbull/rules.md` and `.claude/redbull-rules.md` are now `.onward/rules.md` and `.claude/onward-rules.md`.
- **Install is now direct from this repository.** The plugin previously installed from a separate private marketplace. The repository now carries its own `.claude-plugin/marketplace.json`, so `claude plugin marketplace add ./onward` followed by `claude plugin install onward@onward` is the whole install.

### Fixed

- **Handoff snapshots on prefiltered stops.** The permission and heuristic prefilters resolve most stops without calling the judge, and they were exiting before the handoff write. `.claude/handoff.md` was never produced for those decisions, which is most of them.
- **Dry-run on prefiltered decisions.** `ONWARD_DRY_RUN=true` promised never to block a stop, but a prefilter block ignored it and consumed a continuation from the throttle budget.
- **Decision persistence on early exits.** Every decision made without a judge evaluation (missing transcript, empty transcript, invalid input) failed to persist: the record builder referenced two jq variables it never passed, so the write silently failed and `explain.sh` kept showing an older decision.
- **`missing_information` heuristic on Linux.** The pattern used BSD-only word boundaries (`[[:<:]]`), which GNU grep does not match, so the signal never fired on Linux and those stops fell through to the judge.
- **`explain.sh` without `bc`.** A missing optional `bc` aborted the whole command instead of printing the raw confidence value.
- **Inherited `CDPATH`.** An exported `CDPATH` made `cd` echo its destination inside every path-resolving subshell, breaking hook startup and corrupting the judge's captured output.

### Added

- `scripts/test.sh` runs the hook tests and the eval suite in one command, in a throwaway `HOME` so a test run cannot touch real plugin state.
- CI on GitHub Actions: tests on Ubuntu and macOS, ShellCheck, and manifest validation.
- `LICENSE` (MIT), `SECURITY.md`, `CONTRIBUTING.md`, and `docs/ARCHITECTURE.md`.
- A test covering the judge-approved handoff path, so both the prefilter and judge paths are held by the suite.

### Removed

- Internal planning, ideation, and workplan directories (`.planning/`, `docs/plans/`, `docs/ideas/`, `prompts/`) and the agent configuration files that described how to work on the repo. None of it was useful outside the sessions that produced it.

## [1.2.0] - 2025-12-24

### Added

- **6 new heuristic patterns** for faster prefiltering (no LLM call needed):
  - STOP signals: `explicit_completion`, `uncertain_completion`, `handoff_to_user`
  - CONTINUE signals: `error_recovery`, `transition_phrase`, `verification_intent`
- **21 new test scenarios** (114-134) covering edge cases:
  - Error recovery workflows, workflow boundaries, verification steps
  - Transition phrases, code-heavy messages, external waits
  - Handoffs, uncertain completion, multi-file updates, dependency integration
- **Observability scripts**:
  - `scripts/compare-metrics.sh` - Compare eval metrics across branches/runs
  - `scripts/logs.sh` - View and analyze hook decision history
- **Metrics collection** in eval suite with JSON output

### Changed

- Prefilter efficiency improved from 53% → 63% (12 fewer Claude Haiku calls per run)
- Modularized judge logic into `hooks/lib/judge.sh`
- Total test scenarios: 130 (up from 103)

### Fixed

- `--latest` flag now validates argument presence in compare-metrics.sh
- jq filter quoting for expressions with double quotes in logs.sh
- Null coalescing for missing `.reason` field in jq test() calls
- Printf format errors when displaying placeholder "?" values
- Empty LOG_ENTRIES off-by-one error in line counting
- BSD/macOS compatibility for word boundary patterns (`[[:<:]]` vs `\<`)
- Semantic categories: `handoff_to_user` → task_completion, `error_recovery` → explicit_continuation

## [1.1.5] - 2025-12-03

### Fixed

- Updated polyglot hook wrapper to use POSIX-compliant syntax
  - Changed `${BASH_SOURCE[0]:-$0}` to `$0` in hooks/run-hook.cmd
  - Prevents "Bad substitution" errors on Ubuntu/Debian systems where /bin/sh is dash
  - Matches fix from superpowers v3.6.2

## [1.1.4] - 2025-11-25

### Fixed

- Task completion statements now correctly trigger STOP instead of CONTINUE
- Reframed evaluator from "question detection" to "work state detection"
- Offering optional actions (e.g., "Want me to run X?") now correctly triggers STOP

### Changed

- Evaluator now uses --system-prompt to establish classifier identity (not a coding agent)
- Disabled all tools for evaluator instance with --disallowedTools
- Simplified prompt to use pattern descriptions instead of exact quote matching

### Added

- 5 new test scenarios for task completion edge cases (61-65)

## [1.1.3] - 2025-11-24

### Fixed

- Simplified stop hook logic to prevent rationalization loopholes
- Previous complex rules allowed Haiku to classify decision questions as "clarification" based on context (e.g., "it's brainstorming, not plan presentation")
- New rule is absolute: any question to user = STOP, except "should I continue working?" = CONTINUE

## [1.1.2] - 2025-11-22

### Fixed

- Stop conditions now take precedence over continue conditions when both apply
- Hook correctly stops when presenting plans/designs for user approval
- Fixed issue where hook would push Claude to continue when asking questions like "Does this approach look good?"

### Added

- Comprehensive eval test suite with 60 scenarios (30 STOP, 30 CONTINUE)
- Test runner executing 5 runs per scenario for reliability validation
- Explicit plan presentation detection patterns in evaluation prompt

## [1.1.1] - 2025-11-22

### Fixed

- Removed redundant hooks reference from plugin manifest that caused duplicate hooks file error

## [1.1.0] - 2025-11-22

### Changed

- Improved continuation decision logic with clearer stop conditions
- Reframed evaluation prompt from "CONTINUE unless..." to "STOP only if..." for better clarity
- Simplified incomplete work detection language

### Added

- New stop reason: Detects when a design or plan is being presented to the user for the first time
- Better differentiation between presenting plans vs. implementing them

## [1.0.1] - 2024-11-20

### Fixed

- Fixed plugin manifest validation error requiring hooks paths to start with "./"
- Plugin now installs correctly from a marketplace

### Changed

- Simplified installation to a single command
- Cleaned up README using Strunk's writing principles for clarity and conciseness

## [1.0.0] - 2024-11-20

### Added

- Initial release of the plugin (see the 2.0.0 entry for the name it shipped under)
- Claude-judged Stop hook that automatically evaluates continuation decisions
- Aggressive continuation logic with time-based throttling (3 continuations per 5 minutes)
- Recursion prevention via CLAUDE_HOOK_JUDGE_MODE environment variable
- Smart decision making using separate Claude Haiku instance for fast evaluation
- Zero configuration setup - works automatically after installation

### Features

- Automatically continues when work is incomplete with obvious next steps
- Stops appropriately when Claude explicitly asks for user decisions or clarification
- Graceful fallback if evaluation fails
- Comprehensive logging and reasoning for debugging
- Support for complex multi-step workflows (API development, refactoring, component libraries)

### Technical Details

- Uses Claude Haiku model for cost-effective and fast evaluation
- Analyzes last 10 transcript entries for context
- JSON-based hook communication with proper error handling
- Throttle files for loop prevention with automatic cleanup
