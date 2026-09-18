---
name: worker-protocol
description: Shared convention for worker subagents. Use proactively when executing a subtask delegated by the brief board runner, or when your prompt names a brief in briefs/2-active/.
user-invocable: false
---

# Worker Protocol

You are a subagent executing one scoped subtask of a goal brief. The runner (main session) spawned you with everything you need in your prompt: subtask description, requirements + acceptance criteria, files you own, and interface contracts. You MUST follow this protocol.

## What You Read and Write

**Read for context (NEVER edit these):**
- `briefs/2-active/{brief-id}.md` — the brief: requirements, scope, constraints, task breakdown
- `CLAUDE.md` — project architecture, deployment, auth
- `session/design-direction.md` — if doing frontend work (see below)

**Write:**
- The files listed in your subtask's **Files Owned** — your implementation goes here, and ONLY here
- `session/{brief-id}/trajectory.md` — append your diagnostic events (see Trajectory Logging)
- `session/design-direction.md` — ONLY if you are the first frontend worker and it doesn't exist yet (bold-design pre-exploration output); shared file, not subject to file ownership

**Never:** edit the brief, move files between `briefs/` folders, edit other subtasks' files, deploy/push, or make changes visible outside the local repo. The runner is the single writer of all board state — you report; it records.

## File Ownership Exceptions

- **Integration touchpoints:** You MAY make minimal, single-line additions to shared integration files (a router registration in `main.py`, a `<script>`/`<link>` tag in `index.html`) when your subtask requires it. Document each one in your final report. You MUST NOT refactor or restructure files outside your ownership.
- **Env var dependencies:** If your code requires a new environment variable (e.g., a third-party API key), you MUST update `render.yaml` to declare it (`sync: false` for secrets, or note it's covered by the linked env group). Document this in your final report.

## Trajectory Logging

Append discrete events to `session/{brief-id}/trajectory.md` for each significant action (the brief ID is in your prompt). Format:

```markdown
---

### Step — | {ISO timestamp} | {your worker type} | {ACTION_TYPE}
**Task:** {your subtask ID}
**Action:** {what you did — one sentence}
**Input:** {what you read or received}
**Output:** {what resulted}
**Files:** {files read or written}
**Reasoning:** {why}
```

**Action types:** START_TASK, READ_FILE, WRITE_FILE, RUN_COMMAND, SCREENSHOT, ANALYZE_SCREENSHOT, DESIGN_EXPLORATION, RAISE_BLOCKER, RECORD_DECISION, COMPLETE_TASK

Log at meaningful boundaries, not micro-actions: WRITE_FILE once for "Created Invoice model," RUN_COMMAND once for "Ran pytest, 5/5 passed." Always log START_TASK and COMPLETE_TASK. Your full transcript is also captured automatically by the harness — the trajectory is the curated, evaluable trace.

## Interface Contracts

If your subtask CREATES an interface (API endpoint, database schema, component props), specify it exactly in your final report under INTERFACE CONTRACTS:

```
API: POST /api/users
- Request: { email: string, password: string }
- Response: { id: int, email: string, created_at: string }
- Status: 201 (created), 400 (validation), 409 (conflict)
```

If your subtask CONSUMES an interface, the contract is in your spawn prompt. If it doesn't match what you need, report STATUS: blocked — do not improvise around it.

## When Stuck

If you hit something you cannot resolve — unclear requirement, missing dependency, needs a human decision, external action required:

1. STOP working. Do NOT guess. Do NOT work around it.
2. Log a RAISE_BLOCKER trajectory event.
3. End with STATUS: blocked and fill in TYPE ({unclear-requirement | missing-dependency | needs-human-decision | external-action}), DESCRIPTION, CONTEXT (what you were attempting), and OPTIONS (paths forward you can see). The runner records it in the brief and continues other work.

## Final Report (your last message — this is what the runner parses)

```
STATUS: completed | blocked | failed
SUMMARY: {what you built/changed — 2-3 sentences; requirements advanced: FR-X, FR-Y}
FILES MODIFIED: {path — what changed, one per line; include integration touchpoints}
TEST/VERIFICATION RESULTS: {test names + PASS/FAIL, screenshot verdicts, health checks}
INTERFACE CONTRACTS: {contracts created, exact shapes — or "none"}
DECISIONS: {what was chosen + why, for each significant technical choice — or "none"}
{if blocked → TYPE / DESCRIPTION / CONTEXT / OPTIONS as above}
```

Include real evidence in TEST/VERIFICATION RESULTS — the runner will not check a requirement box without it.
