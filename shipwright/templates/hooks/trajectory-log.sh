#!/bin/bash
# trajectory-log.sh — PostToolUse hook for subagent calls (installed by
# shipwright onboarding)
#
# Appends a deterministic JSONL event to session/{brief-id}/trajectory.jsonl
# for every worker subagent invocation. This complements the model-written
# session/{brief-id}/trajectory.md: the .jsonl is guaranteed and machine-
# parseable for evals; the .md carries curated reasoning. Always exits 0 —
# logging must never break the run.

INPUT=$(cat)

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

ACTIVE=$(ls briefs/2-active/*.md 2>/dev/null | head -1)
[ -z "$ACTIVE" ] && exit 0

BRIEF_ID=$(basename "$ACTIVE" .md)
DIR="session/$BRIEF_ID"
mkdir -p "$DIR" 2>/dev/null || exit 0

export HOOK_INPUT="$INPUT"
python3 - "$DIR/trajectory.jsonl" <<'PY' 2>/dev/null
import json, os, sys, datetime

try:
    data = json.loads(os.environ.get("HOOK_INPUT", "{}"))
except Exception:
    sys.exit(0)

tool_input = data.get("tool_input") or {}
event = {
    "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "event": "subagent_call",
    "tool": data.get("tool_name"),
    "agent_type": tool_input.get("subagent_type"),
    "description": tool_input.get("description"),
    "prompt_chars": len(str(tool_input.get("prompt") or "")),
    "response_chars": len(str(data.get("tool_response") or "")),
}
try:
    with open(sys.argv[1], "a") as f:
        f.write(json.dumps(event) + "\n")
except Exception:
    pass
PY
exit 0
