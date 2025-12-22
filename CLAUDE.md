# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Claude Code Redbull** - Claude Code plugin that prevents premature stopping by using Claude to judge whether continuation is appropriate.

This is a **hook-based plugin** (not a TypeScript/build-based project). The core logic is in bash scripts that integrate with Claude Code's hook system.

## Key Commands

### Testing
```bash
# Run the full evaluation suite (60+ scenarios, 5 runs each)
./test/evals/run-evals.sh

# Test the hook script directly with mock data
echo '{"session_id":"test","transcript_path":"/path/to/transcript.json","stop_hook_active":false}' | \
  ./hooks/claude-judge-continuation.sh

# Test recursion prevention
echo '{"session_id":"test"}' | \
  CLAUDE_HOOK_JUDGE_MODE=true ./hooks/claude-judge-continuation.sh
```

### Local Development
```bash
# Install plugin locally for testing
/plugin marketplace add /path/to/redbull
/plugin install redbull@redbull-dev

# Check hook status
/plugin list
```

## Architecture

### Hook Entrypoints

**Canonical paths:**
- **Hook system entrypoint** (Claude Code): `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd`
  - Used by `hooks/hooks.json` for portable plugin installation
  - Wraps `claude-judge-continuation.sh` for cross-platform compatibility
- **Direct script path** (testing/manual): `hooks/claude-judge-continuation.sh`
  - Used by test suite (`test/evals/run-evals.sh`) and manual testing
  - Relative path from repo root: `hooks/claude-judge-continuation.sh`

### Hook Flow
1. **Stop event triggered** - Claude attempts to stop mid-task
2. **Hook intercepts** - `hooks/claude-judge-continuation.sh` receives event via stdin (JSON)
3. **Context extraction** - Last 10 transcript entries extracted from transcript file
4. **Claude evaluation** - Separate Claude Haiku instance judges continuation with structured output
5. **Decision** - Hook returns `{"decision": "block"}` to continue or `{"decision": "approve"}` to stop

### Critical Components

**hooks/claude-judge-continuation.sh**
- Main hook logic with throttling (3 continues per 5 minutes)
- Uses `claude --print --model haiku --output-format json --json-schema` for structured evaluation
- Sets `CLAUDE_HOOK_JUDGE_MODE=true` to prevent recursion
- Runs in dedicated working directory (`~/.claude/redbull`) to prevent hook triggering in judge session
- Falls back to "approve stop" if evaluation fails

**hooks/run-hook.cmd**
- Polyglot wrapper (bash + Windows cmd) for cross-platform compatibility
- Allows hook scripts to work on Windows via Git Bash and Unix systems
- Entrypoint used by Claude Code hook system via `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd`

**test/evals/scenarios/**
- 60+ JSON scenario files with conversation transcripts and expected decisions
- Each scenario includes: name, description, expected_decision (true=continue, false=stop), transcript (array of messages)
- Run 5 times each for reliability validation

### Hook Communication Contract

**Input** (JSON via stdin):
```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.json",
  "stop_hook_active": false
}
```

**Output** (JSON to stdout):
```json
{
  "decision": "block",  // or "approve"
  "reason": "Claude evaluator determined continuation is appropriate: <reasoning>"
}
```

**Transcript format** (NDJSON - one message per line):
```json
{"role": "user", "content": "Create auth system"}
{"role": "assistant", "content": "I'll create it..."}
```

### Evaluation Logic

The hook judges continuation by asking: **"Does the assistant have more autonomous work to do RIGHT NOW?"**

**CONTINUE (block stop)** if:
- Assistant explicitly states next steps ("Next I need to...", "Now I'll...", "Moving on to...")
- Todo list has pending items
- Stated follow-up tasks not yet performed

**STOP (approve stop)** if:
- Task completion indicated (done, complete, finished, ready, all set)
- Questions asked (approval, decisions, clarification, confirmation)
- Offering optional actions ("Want me to...?", "Should I also...?")
- Blockers exist (errors, missing info, unclear requirements)

### Recursion Prevention

When the judge Claude instance runs, it has:
- `CLAUDE_HOOK_JUDGE_MODE=true` environment variable
- Working directory: `~/.claude/redbull` (prevents hook triggering on file operations)
- `--disallowedTools '*'` (prevents tool use)
- `--system-prompt` establishing it as a classifier, not a coding agent

### Throttling Mechanism

Throttle files: `/tmp/.claude-continue-throttle-<session_id>`
- Format: `<count>:<timestamp>`
- Max 3 continuations per 5-minute window
- Prevents infinite loops
- Auto-resets after 5 minutes
- Cleared on legitimate stops

## Version Management

This plugin uses semantic versioning. Version must be updated in:
1. `.claude-plugin/plugin.json` - `"version"` field
2. `../superpowers-marketplace/.claude-plugin/marketplace.json` - plugin entry
3. `CHANGELOG.md` - new version section

See `RELENG.md` for full release process.

## Testing Philosophy

Scenarios test **edge cases** between continuation and stopping:
- Mid-implementation with TODOs vs. complete with confirmation
- Explicit next steps vs. asking for decisions
- Incomplete work vs. offering optional actions
- Clear intent to continue vs. waiting for user input

Each scenario runs 5 times because LLM evaluation can vary. Scenarios should pass 5/5 runs for reliability.
