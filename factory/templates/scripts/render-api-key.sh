#!/bin/bash
# render-api-key.sh — resolve the Render API key (installed by software-factory
# onboarding into .claude/scripts/). Prints the key on stdout, nothing else.
#
# Resolution order (first hit wins):
#   1. $RENDER_API_KEY already in the environment (shell profile, CI, or an
#      "env" block Claude Code injects into every Bash call)
#   2. .claude/settings.local.json → env.RENDER_API_KEY   (this project; gitignored)
#   3. ./.env → RENDER_API_KEY=...                         (this project; gitignored)
#   4. ~/.claude/settings.json → env.RENDER_API_KEY       (this machine, every project —
#      the recommended home; bootstrap.sh / onboard.py --set-render-key write it)
#   5. ~/.render/cli.yaml → api.key — the `render login` browser token. Works,
#      but it EXPIRES (see api.expires_at). Fallback only.
#
# Usage:
#   export RENDER_API_KEY=$(.claude/scripts/render-api-key.sh)   # curl + CLI both use it
#   .claude/scripts/render-api-key.sh --source                    # print where it came from
#
# Exit 1 (and print nothing) when no key can be found.

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null

want_source=0
[ "$1" = "--source" ] && want_source=1

emit() {  # $1 = key, $2 = source label
  if [ "$want_source" = 1 ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi
  exit 0
}

# 1. environment
if [ -n "$RENDER_API_KEY" ]; then
  emit "$RENDER_API_KEY" "env"
fi

# 2. .claude/settings.local.json → env.RENDER_API_KEY
if [ -f .claude/settings.local.json ]; then
  k=$(python3 -c 'import json,sys
try:
    print((json.load(open(".claude/settings.local.json")).get("env") or {}).get("RENDER_API_KEY",""))
except Exception:
    print("")' 2>/dev/null)
  [ -n "$k" ] && emit "$k" "settings.local.json"
fi

# 3. ./.env
if [ -f .env ]; then
  k=$(grep -E '^[[:space:]]*RENDER_API_KEY=' .env | tail -1 | sed -E 's/^[[:space:]]*RENDER_API_KEY=//; s/^["'"'"']//; s/["'"'"']$//')
  [ -n "$k" ] && emit "$k" ".env"
fi

# 4. ~/.claude/settings.json → env.RENDER_API_KEY (machine-wide)
if [ -f "$HOME/.claude/settings.json" ]; then
  k=$(python3 -c 'import json,os
try:
    print((json.load(open(os.path.expanduser("~/.claude/settings.json"))).get("env") or {}).get("RENDER_API_KEY",""))
except Exception:
    print("")' 2>/dev/null)
  [ -n "$k" ] && emit "$k" "user-settings"
fi

# 5. render login token
CLI_CFG="$HOME/.render/cli.yaml"
if [ -f "$CLI_CFG" ]; then
  k=$(python3 -c 'import re,sys,time
key=exp=""
for line in open(sys.argv[1]):
    m=re.match(r"^\s+key:\s*(\S+)", line)
    if m and not key: key=m.group(1).strip("\"'"'"'")
    m=re.match(r"^\s+expires_at:\s*(\d+)", line)
    if m: exp=m.group(1)
state="cli-token"
if exp and int(exp) < time.time(): state="cli-token-EXPIRED"
print(key+"\t"+state)' "$CLI_CFG" 2>/dev/null)
  key="${k%%	*}"; state="${k##*	}"
  [ -n "$key" ] && emit "$key" "$state"
fi

exit 1
