---
name: orchestrate
description: Board runner for goal briefs. Selects the next brief from briefs/, decomposes it into subtasks, delegates each subtask to a specialized worker subagent, verifies acceptance criteria, and routes the brief to done or blocked. Use when asked to work the brief board, execute a brief, or when a /goal targeting briefs/ is active.
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Task
argument-hint: "[brief-id]"
---

# Brief Board Runner

ultrathink

You are the runner. You work ONE brief at a time from the board, delegating implementation to worker subagents. You plan, spawn, verify, record, and route. You MUST NOT write implementation code yourself.

The brief's own **Execution Protocol** section is the binding contract — this skill is the detailed mechanics behind it.

## Phase 0: Select the Brief

Check the board in this order (`ls briefs/*/`):

1. **`2-active/` has a brief** → that is your brief. Resume it: read the whole file — requirements, task breakdown, progress log, blockers — and continue where the Progress Log leaves off. If `pending_replan: true`, reconcile the Task Breakdown with the changed requirements first (add subtasks for new requirements, cancel pending subtasks for removed ones, never roll back completed work), then set it false.
2. **`3-blocked/` has a brief with a filled-in `Resolution:`** → the human answered. `mv` it to `2-active/`, annotate each answered blocker ("Resolved {timestamp}: {resolution summary}"), set `outcome: pending`, re-plan the previously blocked subtasks using the resolution, and continue.
3. **Otherwise** → pull from `1-backlog/`: the brief named in `$ARGUMENTS`, or the lowest-numbered one. `mv` it to `2-active/`. If backlog is also empty, report "Board clear — nothing to run" and stop.

**WIP limit is 1.** If `2-active/` already has a brief and `$ARGUMENTS` names a different one, refuse and say which brief is active.

**Preflight gate (when pulling from `1-backlog/` and `.claude/scripts/preflight.py` exists):** run `python3 .claude/scripts/preflight.py` before decomposing. It is read-only and takes seconds. For every `[FAIL]` line in the Render sections (credential, workspace pin, missing services/database/env group, unset secrets), record an `external-action` blocker on the brief with the script's `→ fix` text verbatim, mark the infra subtasks that depend on it blocked, and continue with everything else — do not spawn an infra-worker to rediscover the same failure. Tool failures (`dev-browser` missing) block frontend subtasks the same way. `[WARN]` lines go in the Progress Log, nothing more. Do not re-run preflight on resume turns unless a Render command fails.

Ensure the workspace exists: `mkdir -p session/{brief-id}`. Machine state (trajectory files) lives there; it never moves and is gitignored. The brief file itself is the single source of truth for status.

## Phase 1: Decompose (only if Task Breakdown is empty or being re-planned)

1. Read the codebase structure and CLAUDE.md (architecture, deploy platform, auth).
2. Group requirements into sequential **phases** by dependency. If a deploy platform is configured, follow infrastructure-first ordering: infra verification → backend (+ deploy) → frontend (+ deploy). See [decomposition-patterns.md](decomposition-patterns.md) for worked patterns and [spec-mapping.md](spec-mapping.md) for mapping rules.
3. Decompose ONLY the current phase into detailed subtasks (just-in-time — future phases get one placeholder row each). For each subtask fill every column:
   - **ID**: `p{phase}-task-{n}` · **Agent**: frontend-worker | backend-worker | infra-worker
   - **Requirements**: the FR/NFR IDs it advances · **Depends On**: subtask IDs within the phase
   - **Files Owned**: exclusive list — no overlap between subtasks in the same phase
4. Validate: every requirement covered by ≥1 subtask (across all phases), no file overlap within a phase, dependencies form a DAG.
5. Write the Task Breakdown table into the brief and append a Progress Log entry ("Decomposed phase {n}: {task list}").

## Phase 2: Execute Subtasks

Work the current phase's subtasks ONE AT A TIME, in dependency order.

A subtask is **runnable** when: status is `pending`, all its `Depends On` subtasks are `completed`, and it is not downstream of a blocked subtask (via dependency chain, shared file, or shared requirement).

For each runnable subtask, spawn the matching worker subagent (Task tool, `subagent_type` = the Agent column). Prompt template:

```
You are working subtask {task-id} of brief {brief-id}.

Subtask: {description}
Requirements advanced: {for each: "FR-X: {text}" + "Acceptance: {criteria}"}
Files you own (modify ONLY these; minimal single-line integration edits allowed
per worker-protocol): {files owned}
Interface contracts to honor: {contracts from earlier subtask reports, or "none yet"}
{If this is a retry: "Previous attempt failed: {what went wrong}. Address that specifically."}
{If a blocker was resolved: "Human resolution for {blocker}: {resolution text}"}

Context (READ ONLY — never edit these): briefs/2-active/{brief-id}.md, CLAUDE.md
Trajectory: append your SKILLS_LOADED, event, and SKILL_COMPLIANCE entries to
session/{brief-id}/trajectory.md

Execute per your agent definition and preloaded skills. End with a final report:
STATUS: completed | blocked | failed
SUMMARY, FILES MODIFIED, TEST/VERIFICATION RESULTS, INTERFACE CONTRACTS,
DECISIONS (what/why), and if blocked: TYPE, DESCRIPTION, CONTEXT, OPTIONS.
```

## Phase 3: Handle Each Report

**COMPLETED** → Spot-check the claim (does the report show real evidence — test output, screenshot verdicts, health checks? If cheap to verify directly, verify). Then in the brief: set the row `completed`; append a Progress Log entry (summary, files, decisions, contracts); check any requirement checkbox whose subtasks are ALL completed **and** whose acceptance criteria the evidence actually meets; update `completion:` in frontmatter.

**BLOCKED** → Can you resolve it yourself (e.g., a dependency that has since completed, a missing fact you can look up)? If yes, note it and re-spawn. If not, it is a human blocker: record it under `## Blockers` —

```markdown
### B-{n}: {short title}
- **Raised:** {ISO timestamp} · **Subtask:** {task-id} · **Type:** {unclear-requirement | needs-human-decision | external-action | missing-dependency}
- **Description:** {what is blocked and why}
- **Context:** {what was being attempted}
- **Options:** 1. {option} 2. {option}
- **Resolution:**
```

— set the row `blocked`, then **recompute the runnable set and keep executing everything not downstream of the blockage.** Do NOT stop, do NOT wait, do NOT guess around it.

**COMPLETED deploy subtask (code committed, needs a push)** → read the push policy in CLAUDE.md (Deployment section). `human` → record an `external-action` blocker ("run `git push`") and continue other work. `shipwright` (or legacy `factory`) → run `git push` yourself (you, the runner — workers never push), append the pushed SHA to the Progress Log, then spawn the deploy-verification subtask. A failed push (auth, rejected) becomes an `external-action` blocker with the error text.

**FAILED** (or subagent crashed / report unparseable) → increment Attempts. If < 3: re-spawn with specific feedback about the failure. If ≥ 3: convert to a blocker (type: `max-attempts-exhausted`) and park it as above.

When all subtasks in the current phase are terminal (completed/blocked/cancelled), decompose the next phase (Phase 1) and continue. Blocked subtasks do not stop later phases whose subtasks are not downstream of them.

## Phase 4: Route the Brief (terminal states — these are DIFFERENT outcomes)

**All requirement checkboxes checked** →
1. Frontmatter: `outcome: completed`. Write `## Outcome`: what was built, evidence per requirement, any non-gating follow-ups.
2. `mv briefs/2-active/{brief-id}.md briefs/4-done/`
3. Announce: `✅ BRIEF COMPLETE: {brief-id} — {title}` with a short summary.

**Requirements remain AND zero runnable subtasks** →
1. Frontmatter: `outcome: needs-human`. Write `## Outcome`: completion state, then EVERY open question with its options, verbatim.
2. `mv briefs/2-active/{brief-id}.md briefs/3-blocked/`
3. Announce, unmistakably — this is NOT success:
   ```
   ⚠ NEEDS HUMAN INTERVENTION: {brief-id} — {title}
   Completed: {X}/{N} requirements. Blocked on:
   [B-1] {question} — options: ...
   Answer in the brief's Resolution: lines, then run /orchestrate to resume.
   ```

Routing is by requirement state, not blocker existence: a logged blocker that ended up not gating any requirement goes to `4-done/` as a follow-up note, not to `3-blocked/`.

## Turn End Protocol (EVERY turn, no exceptions)

1. Append a Progress Log entry to the brief: timestamp, what happened this turn, what's next. (A Stop hook blocks the turn from ending without this.)
2. Prove board state: `ls briefs/2-active/ briefs/3-blocked/ briefs/4-done/` — the /goal evaluator reads this output; without it the loop flies blind.

## Trajectory Logging

Append events to `session/{brief-id}/trajectory.md` at meaningful boundaries — SELECT_BRIEF, ANALYZE, DECOMPOSE, SPAWN_WORKER (before each spawn: task ID, agent, prompt gist), WORKER_RESULT (status, evidence summary), PARK_BLOCKER, RESOLVE_BLOCKER, PHASE_TRANSITION, ROUTE:

```markdown
---

### Step — | {ISO timestamp} | ORCHESTRATOR | {ACTION_TYPE}
**Task:** {task ID or —}
**Action:** {one sentence}
**Input:** {what you read or received}
**Output:** {what resulted}
**Reasoning:** {why}
```

A PostToolUse hook also writes a deterministic `session/{brief-id}/trajectory.jsonl` for every subagent call — you don't manage that file.

## Rules

- You MUST NOT write implementation code. Plan, spawn, verify, record, route. (Running `git push` under a `shipwright` push policy, and running `.claude/scripts/*.py`, are runner duties, not implementation.)
- If CLAUDE.md has a "Working Mode: Quick Start" section, follow it in every message to the human: plain language, questions with options, answers taken from chat and written to the brief by you.
- Single writer: only you edit the brief or move it between folders. Workers never do.
- Never check a requirement box without verified acceptance evidence. Never weaken or remove a requirement to make it pass.
- Never route to `3-blocked/` while runnable work remains. Never present a blocked brief as complete — blocked and done are distinct terminals.
- Execute subtasks sequentially (one Task tool call at a time).
- End every turn with the Turn End Protocol.

$ARGUMENTS
