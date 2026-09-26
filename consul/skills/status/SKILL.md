---
name: status
description: Read-only diagnostic of the brief board. Shows board state, active brief completion, task breakdown progress, open blockers, and next steps. Use at any time to understand where things stand.
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep
argument-hint: "[board|detail|blockers|requirements]"
---

# Brief Board Status

You are a read-only diagnostic tool. You MUST NOT modify any files. Read board state and present a clear picture.

## Modes

Determine mode from `$ARGUMENTS`:
- "board" or empty → BOARD mode (default)
- "detail" → DETAIL mode
- "blockers" → BLOCKERS mode
- "requirements" → REQUIREMENTS mode

## Prerequisites

`ls briefs/*/` — if `briefs/` doesn't exist or every folder is empty:
```
Empty board. Run /spec create to write the first brief.
```

---

## BOARD Mode

```
== BRIEF BOARD ==
1-backlog:  {n}   {for each: "{id} — {title}"}
2-active:   {n}   {id} — {title}   {completion} ({percentage}%)
3-blocked:  {n}   {for each: "{id} — {title} ({k} open questions)"}   ← NEEDS HUMAN
4-done:     {n}   {for each: "{id} — {title}"}

{If a brief is active, from its Task Breakdown and Progress Log:}
Active: {id} — phase {current}: {completed}/{total} subtasks done, {blocked count} blocked
Last activity: {timestamp of last Progress Log entry} — {its first line}
Next up: {next runnable subtask, or "route the brief" if none}
```

If any brief sits in `3-blocked/`, ALWAYS append:
```
⚠ HUMAN INPUT NEEDED: {id} — answer the Resolution: lines in the brief,
  then run /orchestrate to resume.
```
If an active brief has `pending_replan: true`: "Brief updated since last run — /orchestrate will re-plan."

---

## DETAIL Mode

BOARD output plus the active brief's full Task Breakdown table verbatim, the last 5 Progress Log entries, and any decisions recorded in them. If no active brief, show the most recently updated brief instead and say which folder it's in.

---

## BLOCKERS Mode

For the active brief AND every brief in `3-blocked/`, print each `## Blockers` entry in full — title, type, raised, subtask, description, context, options, and whether `Resolution:` is filled. Unanswered questions first. If none anywhere: "No open blockers."

---

## REQUIREMENTS Mode

For the active brief (or a brief named in `$ARGUMENTS`), map every requirement to its subtasks:

```
== REQUIREMENT TRACKING: {id} ==
  [x] FR-1: {description}
      Subtasks: p1-task-1 (completed), p1-task-2 (completed) — acceptance MET
  [ ] FR-2: {description}
      Subtasks: p2-task-1 (blocked: B-1) — NEEDS HUMAN
  [ ] FR-3: {description}
      Subtasks: not yet decomposed (phase 3 placeholder)

Coverage: {n}/{total} requirements have assigned subtasks
```

Flag prominently: coverage gaps (requirements with no subtask in any phase), and discrepancies (all subtasks completed but checkbox unchecked, or vice versa).

---

## Rules

- Read-only. Never write, edit, move, or create files.
- Folder location is the source of truth for brief status; flag any brief whose `outcome:` frontmatter contradicts its folder.
- Most actionable information first: human-input needs before completed work.
- Never describe a brief in `3-blocked/` as done — it is awaiting human intervention.

$ARGUMENTS
