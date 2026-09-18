---
name: preflight
description: Readiness check before running the brief board. Verifies local tools, git remote, Render authentication (API key or login token), the workspace pin, and that every service, database, and env group declared in render.yaml actually exists on Render with its secrets set. Use before the first /goal run, after a long pause, or whenever Render commands start failing.
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read
argument-hint: "[--quiet]"
---

# Preflight

You are a read-only readiness check. You MUST NOT change any file, env var, or Render resource. You run the deterministic script, then explain the result and the exact fix for each failure.

## Run

```bash
python3 .claude/scripts/preflight.py
```

The script prints one line per check: `[PASS]`, `[WARN]` (Shipwright can work around it or it only matters later), or `[FAIL]` (the run will block on it) with a `→ fix` line. Exit code 1 means at least one FAIL.

## Report

Present the result in this shape:

```
== PREFLIGHT: {{PROJECT_NAME}} ==
Ready / NOT READY — {n} FAIL, {n} WARN

FAIL
  1. {check} — {why it matters in one sentence}
     Fix: {exact command or Dashboard path}
WARN
  - {check} — {what it means}
```

Rules for the explanation:

- Every FAIL gets a fix the human can act on in under a minute of reading: a command, or a Dashboard path (Render Dashboard → Blueprints → New Blueprint Instance → select this repo).
- Distinguish the two Render credentials clearly. The `render login` token expires; a long-lived API key (Render Dashboard → Account Settings → API Keys) does not. The durable place for the key is the `env` block of `.claude/settings.local.json` (gitignored), which Claude Code injects into every Bash call. Never suggest putting it in `settings.json`, `render.yaml`, or any committed file.
- If services are missing, say plainly that the infra-worker will not create them — the human creates the Blueprint Instance, then re-runs `/preflight`.
- Do NOT attempt the fixes yourself, even the easy ones. Preflight is a report; the human acts.

## When invoked by the runner

If `/orchestrate` runs this before pulling a brief from the backlog and there are FAILs in the Render sections, the runner should park them as `external-action` blockers on the brief with the fix text verbatim, rather than spawning an infra-worker that will hit the same wall.

$ARGUMENTS
