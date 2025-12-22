Redbull for Claude Code

Smarter continuation for Claude Code

Redbull for Claude Code prevents Claude Code from stopping prematurely by intercepting stop events and deciding—intelligently—whether Claude should continue autonomously or stop for human input.

This document describes:
	•	the current behavior
	•	the design goals
	•	the decision model
	•	the roadmap
	•	and the planned implementation details

⸻

1. Current Behavior

What it does today
	•	Hooks into Claude Code’s stop event
	•	Calls a secondary Claude model (“judge”) to decide:
	•	continue or stop
	•	Prevents infinite loops via throttling
	•	Falls back safely if the judge fails

What problem it solves

Claude frequently pauses due to:
	•	politeness (“Should I continue?”)
	•	caution
	•	incomplete internal confidence

Redbull for Claude Code keeps work flowing when continuation is clearly safe.

⸻

2. Limitations of the Current Approach
	•	Decisions are binary
	•	No confidence or explanation
	•	Hard override even when a soft nudge would work
	•	No explicit handling of:
	•	permission-seeking language
	•	user-defined completion criteria
	•	Same behavior for coding, debugging, docs, etc.
	•	No learning from user behavior

⸻

3. Design Goals
	1.	Correctness first
Only override stops when continuation is safe.
	2.	Explainability
Users should know why continuation happened.
	3.	Graduated control
Prefer nudges over force.
	4.	User-aligned completion
Stop when the user considers work done.
	5.	Minimal complexity
Shell-based, fast, and robust.

⸻

4. Proposed Decision Model

Instead of a binary result, the judge returns structured output:

{
  "decision": "continue | stop | ask_user",
  "confidence": 0.0,
  "reasons": [],
  "next_action": "none | soft_prompt | hard_continue",
  "constraints": {}
}

Confidence thresholds (defaults)
	•	>= 0.75 → continue
	•	0.55 – 0.74 → soft prompt
	•	< 0.55 → allow stop

⸻

5. Key Enhancements

5.1 Permission-Language Detection

Detect phrases like:
	•	“Should I continue?”
	•	“Would you like me to…”
	•	“Let me know if…”

Bias strongly toward continuation.

⸻

5.2 Soft-Continue Escalation

Before forcing continuation:
	1.	Inject a nudge:
Continue autonomously without asking for confirmation.
	2.	Only hard-override if Claude still stops.

⸻

5.3 Continuation Audit Trail

After auto-continuing, show:

☕ Redbull for Claude Code
Continued because:
• Work incomplete (TODOs present)
• Permission-seeking language detected
• Confidence: 0.83


⸻

5.4 Definition of Done (DoD)

User-defined completion criteria:

definition_of_done:
  - tests added
  - no TODOs
  - final summary written

Claude is only allowed to stop once DoD is met—or when truly blocked.

⸻

5.5 Task-Type Awareness

Classify task as:
	•	coding
	•	debugging
	•	docs
	•	refactor
	•	research

Stopping rules adapt per task.

⸻

6. Roadmap

Phase 1 — Decision Quality & Trust
	•	Structured judge output
	•	Confidence scoring
	•	Permission-language detection
	•	Audit trail

Phase 2 — Control & Escalation
	•	Soft-continue flow
	•	Ask-user vs stop distinction
	•	Continuation constraints

Phase 3 — User Intent Alignment
	•	Definition of Done
	•	Task-type specialization

Phase 4 — Learning & Robustness
	•	User override feedback
	•	Stall detection
	•	Progress signals

⸻

7. Safety & Guardrails
	•	Throttle continuations (existing)
	•	Prevent recursive judge calls
	•	Always allow manual user stop
	•	Fail-open (default to Claude’s normal behavior)

⸻

8. Non-Goals
	•	No full repo introspection (for now)
	•	No heavy diff analysis
	•	No background agents or daemons
	•	No model fine-tuning (initially)

⸻

9. Philosophy

Redbull for Claude Code should feel like:

“Claude just… keeps going when it obviously should.”

Not:

“Something is fighting me.”

⸻