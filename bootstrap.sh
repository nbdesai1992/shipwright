#!/bin/bash
# bootstrap.sh — one command from a fresh Mac to the onboarding wizard.
#
#   ~/software-factory/bootstrap.sh ~/code/my-app
#
# Installs the tools the factory needs (Render CLI, GitHub CLI, Node,
# dev-browser), logs you in to GitHub and Render if you are not already, then
# launches onboard.py with whatever arguments you passed. Safe to re-run:
# every step is skipped when already done. macOS only (Homebrew).

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

say() { printf '  %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1; }

echo
echo "== software-factory bootstrap =="
echo

if ! need brew; then
  say "Homebrew is not installed. Install it (one paste) from https://brew.sh, then run this again."
  exit 1
fi

for pkg in render gh node; do
  if brew list --formula "$pkg" >/dev/null 2>&1 || need "$pkg"; then
    say "[ok ] $pkg"
  else
    say "[...] installing $pkg"
    brew install "$pkg" || { say "brew install $pkg failed"; exit 1; }
  fi
done

if need dev-browser; then
  say "[ok ] dev-browser"
else
  say "[...] installing dev-browser (screenshots for the frontend worker)"
  npm install -g dev-browser || { say "npm install -g dev-browser failed"; exit 1; }
fi

if need python3; then say "[ok ] python3 $(python3 --version 2>&1 | awk '{print $2}')"; else say "python3 missing (install Xcode Command Line Tools: xcode-select --install)"; exit 1; fi
if need git;     then say "[ok ] $(git --version)"; else say "git missing (xcode-select --install)"; exit 1; fi

echo
if gh auth status >/dev/null 2>&1; then
  say "[ok ] GitHub: logged in"
else
  say "[...] GitHub login — your browser will open"
  gh auth login || { say "GitHub login did not complete"; exit 1; }
fi

# Render: an API key (no browser, never expires). Stored machine-wide in
# ~/.claude/settings.json; the wizard, every project, and every Claude Code
# session read it from there. `render login` is not needed.
have_key() {
  [ -n "${RENDER_API_KEY:-}" ] && return 0
  python3 - <<'PY' 2>/dev/null
import json, os, sys
p = os.path.expanduser("~/.claude/settings.json")
try:
    sys.exit(0 if (json.load(open(p)).get("env") or {}).get("RENDER_API_KEY") else 1)
except Exception:
    sys.exit(1)
PY
}
if have_key; then
  say "[ok ] Render API key found"
else
  say "[...] Render API key — create one at Render Dashboard → your avatar → Account Settings → API Keys"
  python3 "$HERE/onboard.py" --set-render-key || { say "No Render key stored. Re-run when you have one."; exit 1; }
fi

echo
say "Tools ready. Starting the wizard…"
echo
exec python3 "$HERE/onboard.py" "$@"
