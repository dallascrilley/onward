Issue 1: Structured Judge Output (JSON + Confidence)

Labels: enhancement, core
Description:
Replace binary judge decision with structured JSON output including confidence, reasons, next_action, and optional constraints.

Acceptance Criteria
	•	Judge returns valid JSON only
	•	Hook parses safely
	•	Fallback on parse failure

⸻

Issue 2: Permission-Language Detection

Labels: enhancement, heuristics
Description:
Detect common permission-seeking phrases and bias continuation decisions accordingly.

Acceptance Criteria
	•	Regex-based detection
	•	Signal passed to judge
	•	Bias reflected in confidence

⸻

Issue 3: Continuation Audit Trail

Labels: UX, enhancement
Description:
Print a short explanation when auto-continuing.

Acceptance Criteria
	•	Includes confidence
	•	Includes top 1–3 reasons
	•	Can be disabled via config

⸻

Issue 4: Soft-Continue Escalation

Labels: enhancement
Description:
Attempt a soft prompt before hard-continuing.

Acceptance Criteria
	•	Soft prompt injected once per stop event
	•	Hard continue only on repeat stop
	•	Still respects throttle

⸻

Issue 5: Ask-User vs Stop Classification

Labels: enhancement
Description:
Explicitly distinguish between “work done” and “needs one concrete user answer.”

Acceptance Criteria
	•	New ask_user decision
	•	Claude asks exactly one question
	•	No forced continuation afterward

⸻

Issue 6: Definition of Done Support

Labels: enhancement, config
Description:
Allow user-defined completion criteria to guide stopping decisions.

Acceptance Criteria
	•	YAML config supported
	•	DoD included in judge prompt
	•	Stop allowed only if DoD met or blocked

⸻

Issue 7: Task-Type Classification

Labels: enhancement
Description:
Classify task type and adjust stopping rules.

Acceptance Criteria
	•	Task type included in judge output
	•	Different heuristics per type
	•	Defaults remain safe

⸻

Issue 8: User Override Feedback Loop

Labels: enhancement, future
Description:
Learn from user manual stops/continues.

Acceptance Criteria
	•	Overrides logged
	•	Thresholds adjustable
	•	No background services required

⸻

Issue 9: Stall Detection

Labels: enhancement, future
Description:
Detect low-progress continuation loops.

Acceptance Criteria
	•	Detect repeated stop cycles
	•	Bias toward stopping when stalled
	•	No heavy diffing required