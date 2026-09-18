#!/bin/bash
# brief-progress-guard.sh — Stop hook (installed by shipwright onboarding)
#
# Deterministically enforces brief documentation: if a brief is active in
# briefs/2-active/ and its file was not modified during this turn, block the
# turn from ending until a Progress Log entry (or routing) happens.
#
# Mechanism: a UserPromptSubmit hook touches .claude/.turn-marker at turn
# start. On Stop, if the active brief's mtime is older than the marker, the
# brief was not touched this turn -> exit 2 (block, stderr fed back to Claude).
# On pass, the marker is re-touched so the next turn is measured freshly.

INPUT=$(cat)

# Never fight the harness: if a previous block already fired this turn, let go.
if printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

ACTIVE=$(ls briefs/2-active/*.md 2>/dev/null | head -1)
[ -z "$ACTIVE" ] && exit 0   # no active brief -> nothing to enforce

MARKER=".claude/.turn-marker"
if [ ! -f "$MARKER" ]; then
  touch "$MARKER"
  exit 0
fi

if [ "$ACTIVE" -nt "$MARKER" ]; then
  touch "$MARKER"
  exit 0
fi

echo "BLOCKED by brief-progress-guard: the active brief ($ACTIVE) was not updated this turn. Append a Progress Log entry (plus any checkbox/subtask status changes the work justifies), or route the brief if it reached a terminal state. Then end the turn." >&2
exit 2
