# Security

## Reporting a vulnerability

Report privately through [GitHub Security Advisories](https://github.com/dallascrilley/onward/security/advisories/new). If that is not available to you, open an issue that says only that you have a security report and asks for a contact address, without any details of the issue itself.

Expect an acknowledgement within 7 days. If a fix is warranted, I will credit you in the release notes unless you ask me not to.

## What Onward can reach

Onward runs as Bash inside Claude Code hooks, with whatever privileges your Claude Code session has. That is worth understanding before you install it:

- **It reads your transcript.** The Stop hook reads the last N entries of the session transcript file that Claude Code hands it, and sends them to a separate `claude --print` call for judging. Those entries can contain anything that was in the session, including secrets that were pasted into it.
- **It writes to two places.** `~/.claude/onward/` (or `ONWARD_STATE_DIR`) holds decision records and the decision log. The working directory gets `.claude/handoff.md` on approved stops, plus `.claude/session-brief.md` and `.claude/triage.md` when those opt-in hooks are on. Decision records contain the judge's reasoning, which quotes transcript content.
- **It shells out to `claude`.** The judge call runs the `claude` binary found on `PATH`.
- **It sends nothing anywhere else.** There is no telemetry, no network call of its own, and no third-party endpoint.

Add `.claude/handoff.md`, `.claude/session-brief.md`, and `.claude/triage.md` to your `.gitignore` so session content is not committed by accident.

## Design choices that limit blast radius

- **Fail open, toward stopping.** Any error (bad JSON, missing transcript, failed judge call, unparsable result) approves the stop. A broken Onward cannot trap a session in a loop.
- **Recursion guard.** The judge runs with `CLAUDE_HOOK_JUDGE_MODE=true`, and the hook approves immediately when it sees that variable, so the judge cannot trigger itself.
- **Throttling.** Continuations are capped per session and time window.
- **Judge sandboxing.** The judge call runs with `--disallowedTools '*'`, so it cannot execute tools.
- **No transcript content in debug logs.** `ONWARD_DEBUG=true` logs event types, counts, and decisions. File paths are logged as basenames only.
- **Guardrails are opt-in and advisory.** The PreToolUse guardrail blocks six destructive command shapes when enabled. It is a seatbelt against obvious accidents, not a security boundary, and it is trivially bypassed by an adversarial command.

## Scope

Onward has no authentication, no server, and no persistent daemon. Reports about the security of Claude Code itself belong to Anthropic, not here.
