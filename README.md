# Onward

[![CI](https://github.com/dallascrilley/onward/actions/workflows/ci.yml/badge.svg)](https://github.com/dallascrilley/onward/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Onward keeps Claude Code working through multi-step tasks instead of stopping to ask.

Claude Code stops when it thinks a turn is finished. On a long task that often lands mid-way: the schema is written but the migration is not, the endpoint exists but nothing validates its input. Onward hooks the Stop event, looks at what just happened, and either lets the session end or sends it back to work.

## What it looks like

A Stop event after "I added the POST /users route. Next I'll add request validation and the integration test.":

```console
$ echo '{"role":"assistant","content":"I added the POST /users route. Next I'\''ll add request validation and the integration test."}' \
    > transcript.ndjson
$ echo '{"session_id":"demo","transcript_path":"./transcript.ndjson","stop_hook_active":false}' \
    | ./hooks/claude-judge-continuation.sh
{
  "decision": "block",
  "reason": "Heuristic detected 'explicit_next_steps': work continues without judge"
}
```

A Stop event after "I sketched two designs for the validation layer. Which approach do you prefer?":

```console
{
  "decision": "approve",
  "reason": "Heuristic detected 'asking_for_decision': user input needed, stopping without judge"
}
```

`decision: block` is what sends Claude back to work. `decision: approve` lets the session end.

## Install

Onward ships as a Claude Code plugin, and the repository is its own single-plugin marketplace, so it installs straight from the clone.

```bash
git clone https://github.com/dallascrilley/onward.git
claude plugin marketplace add ./onward
claude plugin install onward@onward
```

Restart Claude Code, then confirm the four hooks registered:

```bash
claude plugin details onward
```

```console
onward 2.0.0
  Keeps Claude Code working through multi-step tasks instead of stopping to ask
  Source: onward@onward

Component inventory
  Skills (0)
  Agents (0)
  Hooks (4)  Stop, PreToolUse, SessionStart, PostToolUse  (harness-only — no model context cost)
```

Requirements: Claude Code with the `claude` CLI on `PATH`, Bash, and [`jq`](https://jqlang.github.io/jq/). Nothing else is installed, and no packages are downloaded.

To remove it: `claude plugin uninstall onward` then `claude plugin marketplace remove onward`.

## How a decision gets made

Every Stop event walks the same ladder, and the first rung that matches wins:

1. **Ignore patterns.** Literal substrings you list in `.onward/ignore.txt` end the session immediately.
2. **Permission language.** "Should I continue?" means keep going. "Which approach do you prefer?" means stop and ask.
3. **Heuristic signals.** Stated next steps, open TODOs, and explicit completion phrases resolve without any model call. Roughly 63% of decisions in the eval suite land here.
4. **The judge.** Everything left goes to a separate Claude Haiku instance with a JSON schema, which returns a continue-or-stop verdict with a confidence score.

Two guards sit around that ladder. Throttling caps continuations at 3 per 5 minutes per session, so a disagreement cannot loop forever. Stall detection compares the current context against recent decisions and forces a stop when the same state keeps producing low-confidence continuations.

The judge runs with `CLAUDE_HOOK_JUDGE_MODE=true`, and the hook approves the stop immediately when it sees that variable. That is what keeps the judge from triggering its own hooks.

## Configuration

Everything has a working default. Per-project settings live in `.claude/onward.local.md` as YAML frontmatter:

```markdown
---
enabled: true
aggressiveness: high
dod_enforcement: advisory
definition_of_done:
  - Tests pass
  - No debug logging left behind
---
```

`aggressiveness` (`low`, `medium`, `high`) controls how much transcript context the judge sees. `definition_of_done` rules are added to the judge prompt; `dod_enforcement: strict` tells the judge to treat them as blocking.

Environment variables override the defaults for a single run:

| Variable | Default | Purpose |
|---|---|---|
| `ONWARD_ENABLED` | `true` | Set `false` to approve every stop |
| `ONWARD_DRY_RUN` | `false` | Decide as usual, then always approve the stop and report what it would have done |
| `ONWARD_JUDGE_MODEL` | `haiku` | `haiku`, `sonnet`, or `opus` |
| `ONWARD_THROTTLE_LIMIT` | `3` | Continuations allowed per window |
| `ONWARD_THROTTLE_WINDOW_SECONDS` | `300` | Length of the throttle window |
| `ONWARD_TRANSCRIPT_CONTEXT_LINES` | `10` | Transcript entries sent to the judge |
| `ONWARD_STATE_DIR` | `~/.claude/onward` | Where decisions and logs are written |
| `ONWARD_LOG_DECISIONS` | `true` | Append every decision to `decision_log.jsonl` |
| `ONWARD_DEBUG` | `false` | Structured JSON trace on stderr |

Start with `ONWARD_DRY_RUN=true` if you want to watch its decisions before it changes any of them.

## Inspecting decisions

```bash
./scripts/explain.sh              # why the last stop was allowed or blocked
./scripts/explain.sh --verbose    # include the judge's reasoning and confidence
./scripts/logs.sh --lines 20      # the last 20 decisions
./scripts/logs.sh --stats         # continue/stop counts across the log
```

```console
$ ./scripts/explain.sh
Last Decision: STOP (approved stop)
Timestamp:     2026-08-12T07:09:30Z
Session:       demo

Reasoning:
  Heuristic detected 'asking_for_decision': user input needed, stopping
  without judge
```

## The other three hooks

The Stop hook is the product. Three smaller hooks ship alongside it and are **off unless you turn them on**:

- `ONWARD_GUARDRAILS_ENABLED=true` blocks six destructive command shapes before they run (`rm -rf /`, `rm -rf ~`, bare `git reset --hard`, `git clean -fdx`, curl-piped-to-shell, `chmod 777`).
- `ONWARD_SESSION_BRIEF_ENABLED=true` writes `.claude/session-brief.md` with repository context at session start.
- `ONWARD_TRIAGE_ENABLED=true` writes `.claude/triage.md` with an error summary after a failed tool call.

On an approved stop, the Stop hook also writes `.claude/handoff.md`: session id, stop reason, recent context, and git status for whoever picks the work up next.

## Tests

```bash
./scripts/test.sh          # 14 hook tests, then 130 eval cases (about 3 minutes)
./scripts/test.sh --fast   # hook tests only
```

The eval suite replays 124 scenario transcripts (plus 6 transcript-validation
cases) through the real hook with a stubbed `claude` binary. Every case asserts
the decision; the path-sensitive scenarios also assert which rung produced it.
It needs no API access and no network. A test run uses a throwaway `HOME`, so
it never touches your own plugin state.

## Honest boundaries

- The judge is a Claude Haiku call. It is fast and cheap, and it is still a language model making a judgment call. It will be wrong sometimes, which is why throttling and stall detection exist.
- The eval scenarios are transcripts I wrote to cover decision categories. They are not sampled from real sessions, and passing them is not evidence of a hit rate in your repo.
- Bash and `jq` only, developed and tested on macOS. It should work on Linux; I have not run it there.
- Prefilter phrases are English. Non-English transcripts fall through to the judge, which is slower but still correct.
- No telemetry. Decisions are written to `~/.claude/onward` on your machine and nowhere else.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the hook flow, the library layout, and the decision record format.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports go through
[SECURITY.md](SECURITY.md). The project follows the
[Contributor Covenant](CODE_OF_CONDUCT.md).

## License

MIT. See [LICENSE](LICENSE).
