{
  "permissions": {
    "allow": [
      "Bash(dev-browser *)",
      "Bash(python3 .claude/scripts/preflight.py*)",
      "Bash(.claude/scripts/render-api-key.sh*)",
      "Bash(ls briefs/*)",
      "Bash(mv briefs/*)",
      "Bash(mkdir -p session/*)"
    ]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p \"$CLAUDE_PROJECT_DIR\"/.claude && touch \"$CLAUDE_PROJECT_DIR\"/.claude/.turn-marker"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/brief-progress-guard.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Task|Agent",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/trajectory-log.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/render-workspace-guard.sh"
          }
        ]
      }
    ]
  }
}
