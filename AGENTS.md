# Repository Guidelines

## Project Structure & Plugin Layout
- `.claude-plugin/plugin.json` is the Claude Code manifest (name, version, metadata).
- `hooks/hooks.json` is the plugin hook config (wrapper format: `{ "hooks": { ... } }`).
- `hooks/` contains executable hook scripts (core behavior lives here).
- `test/evals/` holds the eval harness and `scenarios/` JSON fixtures.
- Root docs: `README.md`, `CLAUDE.md`, `RELENG.md`, `CHANGELOG.md`.

## Build, Test, and Development Commands
```bash
./test/evals/run-evals.sh

echo '{"session_id":"test","transcript_path":"/path/to/transcript.json","stop_hook_active":false}' | \
  ./hooks/claude-judge-continuation.sh

echo '{"session_id":"test"}' | \
  CLAUDE_HOOK_JUDGE_MODE=true ./hooks/claude-judge-continuation.sh

/plugin marketplace add /path/to/redbull
/plugin install redbull@redbull-dev
```

## Hook Development Notes
- Use `${CLAUDE_PLUGIN_ROOT}` for all hook command paths (portable installs).
- Changes to `hooks/hooks.json` or scripts require a Claude Code restart to load.
- Keep hook scripts deterministic, fast, and with quoted variables.

## Plugin Settings (Optional)
- Per‑project config belongs in `.claude/redbull.local.md` with YAML frontmatter + markdown body.
- Do not commit local settings; add `.claude/*.local.md` to `.gitignore` if you introduce settings.
- Hooks can quick‑exit if the settings file is missing or `enabled: false`.

## Coding Style & Naming Conventions
- Bash scripts under `hooks/` use `#!/bin/bash` and stay executable.
- Use kebab‑case for files/directories; follow existing quoting/formatting patterns.

## Testing Guidelines
- Primary verification: `./test/evals/run-evals.sh` (scenarios should pass 5/5 runs).
- Add new fixtures in `test/evals/scenarios/` and keep them minimal and deterministic.

## Commit & Pull Request Guidelines
- No strict convention yet; for releases follow `RELENG.md` (e.g., `chore: Bump version to X.Y.Z`).
- PRs should summarize behavior changes, include the test command run, and note version bumps.

## Security & Configuration Tips
- Requires `jq` and the `claude` CLI in PATH.
- `CLAUDE_HOOK_JUDGE_MODE=true` prevents recursion — do not remove.
- Throttle files live in `/tmp/.claude-continue-throttle-*` and can be deleted to reset state.

## Repository Settings (Bootstrap Contract)
This repo is a hook-based Bash plugin; items not applicable are marked as such.

| Setting | Value |
|---------|-------|
| Language | Bash (hook scripts) |
| Package Manager | None |
| Backend Framework | None |
| Frontend Framework | None |
| Database/ORM | None |
| Test Runner | Custom bash harness (`./test/evals/run-evals.sh`) |
| Linter/Formatter | None |

```bash
typecheck: : # n/a (bash-only repo)
lint:      : # n/a (no linter configured)
test:      ./test/evals/run-evals.sh
build:     : # n/a (no build step)
```
