Below is a concrete implementation plan (incremental, shippable in slices) plus exact judge prompt upgrades (system + user prompts) that support: confidence scoring, permission-language boost, DoD rubric, task-type hints, and “soft-continue” escalation.

⸻

Implementation plan

Phase 0: Add structured judge output (foundation)

Goal: Judge returns machine-parseable JSON with confidence + reasons + optional constraints.

Changes
	1.	Define a strict JSON schema you parse in the hook:
	•	decision: "continue" | "stop" | "ask_user"
	•	confidence: 0.0..1.0
	•	reasons: string[] (short bullets)
	•	next_action: "none" | "soft_prompt" | "hard_continue"
	•	constraints (optional): e.g. {"focus":"tests_only","max_steps":2,"no_new_files":true}
	2.	Update hook logic:
	•	If JSON parse fails → fall back to normal stop behavior.
	•	If decision=continue and confidence>=0.75 → proceed.
	•	If 0.55 <= confidence < 0.75 → choose soft_prompt (Phase 2).
	•	Else → allow stop.

⸻

Phase 1: Add “permission-language” + “clarification-needed” heuristics (pre-judge + post-judge bias)

Goal: Reduce judge calls and reduce false-stops.

Changes
	1.	Before calling judge, scan the last assistant message for “permission-y” phrases:
	•	continue-bias triggers: should i continue, want me to, would you like me to, should i proceed, i can keep going, let me know if i should
	2.	Also scan for true “needs user input” triggers:
	•	stop-bias triggers: which option, choose, what do you prefer, need access, need credentials, confirm requirement, what is the expected behavior
	3.	Inject these as features into judge input:
	•	signals.permission_language=true/false
	•	signals.needs_user_choice=true/false

Rule of thumb
	•	If needs_user_choice=true, you can skip judge and allow stop unless user configured “always continue”.

⸻

Phase 2: Soft-continue escalation (nudge first, override second)

Goal: If the judge is only moderately confident, try a gentle “continue autonomously” message instead of forcing.

Changes
	1.	Add a “soft prompt” payload that gets injected back to Claude:
	•	“Continue autonomously. Do not ask for confirmation. Make reasonable assumptions and proceed. If blocked, stop and ask a single concrete question.”
	2.	Track whether you already soft-prompted for this stop event:
	•	If Claude stops again immediately → then allow hard_continue only if confidence is high or permission-language was detected.
	3.	Preserve your existing throttle to prevent loops.

⸻

Phase 3: Definition of Done (user-config rubric)

Goal: A single config file makes decisions way more accurate.

Changes
	1.	Add config file (e.g. ~/.double-shot-latte.yaml) with:
	•	definition_of_done: [ ... ]
	•	continue_confidence_threshold: 0.75
	•	soft_prompt_threshold: 0.55
	2.	Summarize DoD into judge prompt:
	•	“Only stop when DoD is met OR when blocked by user choice.”

⸻

Phase 4: Task-type specialization (lightweight)

Goal: Better calls for docs vs debugging vs refactors.

Changes
	1.	Add a cheap classifier (judge can do it):
	•	task_type: "coding"|"debugging"|"docs"|"refactor"|"research"|"ops"
	2.	Adjust rubric inside the judge prompt based on task_type.

⸻

Exact judge prompt upgrades

Use two messages: a system message to force JSON + behavior, and a user message that includes the transcript excerpt + extracted signals + DoD.

1) Judge system prompt (exact)

You are a strict decision function for a coding assistant “Stop Hook” controller.

Your job: decide whether the main assistant should continue autonomously or stop to ask the human.

You MUST output ONLY valid JSON (no prose, no markdown, no code fences).
The JSON MUST match this schema:

{
  "decision": "continue" | "stop" | "ask_user",
  "confidence": number,         // 0.0 to 1.0
  "reasons": string[],          // 1-5 short bullets
  "next_action": "none" | "soft_prompt" | "hard_continue",
  "constraints": {              // optional
    "focus": string,            // e.g. "tests_only", "bugfix_only", "docs_only"
    "no_new_files": boolean,
    "max_steps": number
  }
}

Guidelines:
- Choose "stop" if human input is required to avoid wrong behavior (missing requirements, choices, credentials, ambiguity).
- Choose "continue" if work is clearly unfinished and the assistant can proceed safely with reasonable assumptions.
- Choose "ask_user" only when a single, concrete question to the user is necessary to proceed.
- Use higher confidence (>=0.75) only when the context is clear.
- If the assistant is merely being polite or cautious (permission-seeking language), bias toward "continue".
- If there is evidence of completion (tests done, final summary, DoD met), bias toward "stop".
- Never request new information yourself; only decide.

2) Judge user prompt (exact template)

Your hook should fill in the {…} placeholders.

Evaluate whether the assistant should continue autonomously.

Context:
- stop_event_reason: "{STOP_REASON_OR_EMPTY}"
- recent_transcript: {LAST_N_MESSAGES_JSON}

Extracted signals (computed by the hook):
- permission_language: {true|false}
- needs_user_choice: {true|false}
- blocked_by_credentials_or_access: {true|false}
- user_already_gave_go_ahead: {true|false}

User preferences:
- definition_of_done:
{DOD_BULLETS_OR_EMPTY}

Decision rubric:
1) If needs_user_choice OR blocked_by_credentials_or_access is true -> decision should be "stop" or "ask_user".
2) If permission_language is true AND work appears unfinished -> bias strongly toward "continue".
3) If definition_of_done is provided, only allow "stop" when DoD is plausibly met OR when truly blocked.
4) If unclear -> prefer "soft_prompt" with moderate confidence rather than forcing.

Return JSON only.


⸻

Soft prompt text (exact)

When you decide to soft-prompt, inject this to the main assistant:

Continue autonomously without asking for confirmation. Make reasonable assumptions, proceed with the next concrete steps, and aim to finish. If you are truly blocked, stop and ask exactly one specific question.


⸻

Suggested thresholds & rules (drop-in defaults)
	•	CONTINUE_THRESHOLD = 0.75
	•	SOFT_PROMPT_THRESHOLD = 0.55
	•	If permission_language=true, subtract 0.05 from thresholds (continue more easily)
	•	If needs_user_choice=true or blocked_by_credentials_or_access=true, force stop/ask_user regardless of confidence
	•	Keep your existing max 3 continuations / 5 minutes throttle