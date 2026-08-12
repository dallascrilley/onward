# Architecture

Onward is four Bash hook entrypoints over a shared library. No build step, no dependencies beyond Bash and `jq`.

```
hooks/
  claude-judge-continuation.sh    Stop         the continuation decision
  claude-guardrail-pretooluse.sh  PreToolUse   blocks destructive commands (opt-in)
  claude-sessionstart-brief.sh    SessionStart writes a repo brief (opt-in)
  claude-posttooluse-triage.sh    PostToolUse  writes an error triage (opt-in)
  hooks.json                      hook registration for Claude Code
  lib/
    config.sh      defaults and env var overrides
    settings.sh    per-project settings from .claude/onward.local.md
    transcript.sh  transcript validation and context extraction
    ignore.sh      user-defined ignore patterns
    prompt.sh      evaluation prompt assembly, including definition-of-done rules
    judge.sh       judge invocation, JSON schema, heuristic signal detection
    throttle.sh    per-session continuation counting
    handoff.sh     handoff snapshot writing
    emit.sh        the single stdout writer, plus decision persistence
    debug.sh       structured stderr tracing
scripts/           explain, logs, bench, compare-metrics, test
test/              hook tests, snapshots, and 130 eval scenarios
```

## The Stop decision path

`claude-judge-continuation.sh` runs top to bottom and exits at the first resolution:

1. **Recursion guard.** `CLAUDE_HOOK_JUDGE_MODE=true` means this process is the judge. Approve immediately.
2. **Per-project settings.** `settings_load` reads `.claude/onward.local.md`. `enabled: false` approves immediately. `aggressiveness` scales how many transcript entries the judge sees.
3. **Input validation.** Unparsable event JSON approves the stop.
4. **Throttle check.** During an active stop-hook cycle, exceeding the continuation limit inside the window forces a stop and clears the throttle file.
5. **Transcript validation.** Missing, unreadable, or empty transcript approves the stop.
6. **Context extraction.** The last N valid NDJSON entries become a JSON array. No valid entries approves the stop.
7. **Ignore patterns.** A literal substring match from `.onward/ignore.txt` approves the stop.
8. **Permission prefilter.** Permission-seeking language ("should I continue?") blocks the stop; decision-seeking language ("which do you prefer?") approves it.
9. **Heuristic prefilter.** Signal detection over the last assistant message: stated next steps and open TODOs block, explicit completion and questions to the user approve.
10. **Stall detection.** Hashes the current context and compares it against recent decision records to compute a stall risk score.
11. **The judge.** A `claude --print --model haiku --output-format json --json-schema ... --disallowedTools '*'` call returns `should_continue`, `reasoning`, `confidence`, `decision_category`, and detected `signals`. Stall risk then raises the confidence bar: above 70 forces a stop below 0.75 confidence, above 40 below 0.65.

Steps 7 through 9 are the prefilters. They resolve about 63% of the eval suite without a model call, which is what keeps the hook fast.

Every decision leaves through `emit_decision`, which is the only function that writes to stdout. That single writer is what makes the contract testable: everything else, including all debug output, goes to stderr.

Prefilter decisions go through `emit_prefilter_decision`, which applies the same two contracts the judge path applies: dry-run never blocks, and an approved stop with context writes a handoff.

## Failure posture

Every error path approves the stop. A missing transcript, a failed judge call, an unparsable result, invalid settings: all of them end the session normally. The worst failure mode of a broken Onward is that it does nothing.

## State

`~/.claude/onward/` (override with `ONWARD_STATE_DIR`) holds:

- `last_decision.json`, the most recent decision record, read by `scripts/explain.sh`
- `decision_log.jsonl`, an append-only log rotated at `ONWARD_LOG_MAX_LINES` (default 500), read by `scripts/logs.sh`

A decision record looks like this:

```json
{
  "timestamp": "2026-08-12T07:09:30Z",
  "session_id": "demo",
  "decision": "approve",
  "reason": "Heuristic detected 'asking_for_decision': user input needed, stopping without judge",
  "evaluation": {
    "should_continue": false,
    "reasoning": "Assistant is asking the user to choose between two designs",
    "confidence": 0.9,
    "decision_category": "waiting_for_user",
    "signals": ["asking_for_decision"]
  }
}
```

Throttle state lives in per-session files under the same directory. Definition-of-done metadata, stall risk, and context hash are added to the record when present.

## Testing

`test/evals/run-evals.sh` replays each scenario through the real hook with `test/evals/bin/claude` on `PATH` as a stubbed judge. Each scenario asserts both the decision and the path that produced it, so a change that gets the right answer through the wrong rung still fails. `test/snapshots/` pins the judge prompt and JSON schema, so prompt edits have to be deliberate.
