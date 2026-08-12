# Contributing

Thanks for looking. Onward is a small Bash project, so the setup is short.

## Getting set up

You need Bash, [`jq`](https://jqlang.github.io/jq/), and Git. You do not need an API key or network access to develop or test: the eval suite stubs the `claude` binary.

```bash
git clone https://github.com/dallascrilley/onward.git
cd onward
./scripts/test.sh
```

A full run takes about three minutes, most of it in the eval scenarios. `./scripts/test.sh --fast` runs the 13 hook tests only.

## Running a hook by hand

Every hook reads a JSON event on stdin and writes a JSON decision on stdout:

```bash
echo '{"session_id":"dev","transcript_path":"/path/to/transcript.ndjson","stop_hook_active":false}' \
  | ONWARD_DEBUG=true ./hooks/claude-judge-continuation.sh
```

`ONWARD_DEBUG=true` writes a structured trace to stderr, including which prefilter rung resolved the decision. `ONWARD_DRY_RUN=true` runs the full decision path and then always approves the stop.

## Testing changes

- Hook tests live in `test/test-*.sh`. Each is standalone: run `bash test/test-handoff.sh` to see its output.
- Eval scenarios live in `test/evals/scenarios/*.json`. Each names an expected decision and an expected path (`permission`, `heuristic`, or `judge`). Adding a scenario is the cheapest way to pin down a decision you care about.
- `test/snapshots/` holds the judge prompt and schema snapshot. If you change the prompt, run `bash test/test-snapshot-update.sh` to refresh it, and include the updated snapshot in your change.

New behavior needs a test. A bug fix needs a test that fails before the fix.

## Style

- Bash with `#!/bin/bash`, quoted variables, and `local` inside functions.
- Scripts stay executable (`chmod +x`) and use kebab-case filenames.
- Hooks must stay fast and must never write to stdout except the final decision JSON. Everything else goes to stderr through `debug_log`.
- Hooks must fail toward approving the stop. A hook that errors should never trap a session.
- Use `${CLAUDE_PLUGIN_ROOT}` for paths in `hooks/hooks.json` so the plugin works wherever it is installed.

## Pull requests

Describe the behavior change, name the command you ran to verify it, and note anything you could not test. Keep the change scoped to one thing. Changes to `hooks/hooks.json` or the hook scripts need a Claude Code restart before they take effect in a live session.

## Releasing

1. Update `version` in `.claude-plugin/plugin.json`.
2. Add the release section to `CHANGELOG.md`.
3. Verify both manifests: `claude plugin validate . --strict`.
4. Run `./scripts/test.sh`.
5. Commit, then tag: `claude plugin tag .` creates the `onward--v<version>` tag and checks that the manifests agree.
