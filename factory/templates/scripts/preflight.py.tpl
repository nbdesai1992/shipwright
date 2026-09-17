#!/usr/bin/env python3
"""
preflight.py — deterministic readiness check for a software-factory project
(installed by onboarding into .claude/scripts/; rendered for {{PROJECT_NAME}}).

Run it any time:   python3 .claude/scripts/preflight.py
Or in Claude Code: /preflight

It never changes anything. It checks, in order, everything the runner and
workers will need on the first turn, and prints one line per check:

  [PASS] ...
  [WARN] ...   something the factory can work around or that only matters later
  [FAIL] ...   the run will block on this; a fix hint follows on the next line

Exit code 1 if any check FAILs, else 0. Standard library only.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DEPLOY_PLATFORM = "{{DEPLOY_PLATFORM}}"
FRONTEND = "{{FRONTEND_FRAMEWORK}}"
BACKEND = "{{BACKEND_FRAMEWORK}}"
ENV_GROUP = "{{ENV_GROUP_NAME}}"
API = "https://api.render.com/v1"

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[2])
os.chdir(ROOT)

RESULTS = []  # (level, message, fix)


def report(level, msg, fix=""):
    RESULTS.append((level, msg, fix))
    print(f"[{level}] {msg}")
    if fix and level != "PASS":
        print(f"       → {fix}")


def run(cmd, timeout=20):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return 127, str(e)


def api_get(path, key, timeout=15):
    """GET the Render API. Returns (status, parsed-json-or-text)."""
    req = urllib.request.Request(
        f"{API}{path}", headers={"Authorization": f"Bearer {key}", "Accept": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode("utf-8")
            try:
                return r.status, json.loads(body)
            except ValueError:
                return r.status, body
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # network down, DNS, timeout
        return 0, str(e)


def http_get(url, timeout=15):
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=timeout) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


# ── 1. Local tools ───────────────────────────────────────────────

def check_tools():
    print("\n== Local tools ==")
    report("PASS", f"python3 {sys.version.split()[0]}")
    code, out = run(["git", "--version"])
    report("PASS" if code == 0 else "FAIL", f"git: {out if code == 0 else 'not found'}",
           "Install git 2.28+")

    if DEPLOY_PLATFORM == "render":
        if shutil.which("render"):
            code, out = run(["render", "--version"])
            report("PASS", f"render CLI: {out.splitlines()[0] if out else 'present'}")
        else:
            report("FAIL", "render CLI not found",
                   "brew install render && render login   (docs.render.com/cli)")

    if shutil.which("gh"):
        code, _ = run(["gh", "auth", "status"])
        report("PASS" if code == 0 else "WARN", "gh CLI " + ("authenticated" if code == 0 else "installed but not logged in"),
               "gh auth login  (optional — only needed for repo creation)")
    else:
        report("WARN", "gh CLI not found (optional)", "brew install gh && gh auth login")

    if FRONTEND != "none":
        if shutil.which("dev-browser"):
            report("PASS", "dev-browser present (frontend screenshots)")
        else:
            report("FAIL", "dev-browser not found — the frontend-worker cannot verify UI without it",
                   "npm install -g dev-browser   (then `dev-browser install` if it cannot find Chrome)")
        if shutil.which("node"):
            code, out = run(["node", "--version"])
            major = int(re.sub(r"\D", "", out.split(".")[0]) or 0)
            report("PASS" if major >= 18 else "WARN", f"node {out}",
                   "Node 18+ recommended for the Next.js dev server")
        else:
            report("WARN", "node not found — local frontend dev server will not start",
                   "Install Node 18+ (nvm or brew install node)")


# ── 2. Git ───────────────────────────────────────────────────────

def check_git():
    print("\n== Git ==")
    if not (ROOT / ".git").is_dir():
        report("FAIL", "not a git repository", "git init -b main && gh repo create ... (see SETUP.md Step 1)")
        return
    code, remotes = run(["git", "remote", "-v"])
    if code != 0 or not remotes.strip():
        report("FAIL", "no git remote — Render deploys from GitHub",
               "gh repo create <slug> --private --source=. --remote=origin --push")
        return
    origin = remotes.splitlines()[0].split()[1]
    report("PASS", f"remote: {origin}")
    code, status = run(["git", "status", "-sb"])
    head = status.splitlines()[0] if status else ""
    if "..." not in head:
        report("WARN", "current branch has no upstream — has it been pushed?", "git push -u origin HEAD")
    elif "ahead" in head:
        report("WARN", f"unpushed commits ({head})", "git push")
    else:
        report("PASS", f"branch pushed ({head.lstrip('# ')})")


# ── 3. Render auth + workspace ───────────────────────────────────

def resolve_key():
    helper = ROOT / ".claude" / "scripts" / "render-api-key.sh"
    if not helper.exists():
        return "", "missing-helper"
    code, key = run(["bash", str(helper)])
    _, source = run(["bash", str(helper), "--source"])
    return (key.strip() if code == 0 else ""), source.strip()


def read_pins():
    pin = ROOT / ".claude" / "render-workspace"
    if not pin.exists():
        return []
    return [l.strip() for l in pin.read_text(encoding="utf-8").splitlines() if l.strip()]


def check_render_auth():
    """Returns (key, owner_id) or (None, None) if the run cannot reach Render."""
    print("\n== Render authentication ==")
    key, source = resolve_key()
    if not key:
        report("FAIL", "no Render API key found (env RENDER_API_KEY, .claude/settings.local.json, .env, or `render login` token)",
               "Create a long-lived key: Render Dashboard → Account Settings → API Keys, then put it in "
               ".claude/settings.local.json as {\"env\": {\"RENDER_API_KEY\": \"rnd_...\"}} (gitignored). "
               "Or run `render login` for a short-lived token.")
        return None, None
    if source == "cli-token-EXPIRED":
        report("FAIL", "only credential is the `render login` token and it has EXPIRED",
               "Run `render login` again, or (durable) add a long-lived API key — see SETUP.md 'Render API key'")
        return None, None
    if source == "cli-token":
        report("WARN", "using the `render login` token (expires periodically; a long run may outlive it)",
               "Durable option: long-lived API key in .claude/settings.local.json env block — see SETUP.md")
    else:
        report("PASS", f"Render API key source: {source}")

    status, owners = api_get("/owners?limit=100", key)
    if status == 401:
        report("FAIL", f"Render API rejected the key (401) — source: {source}",
               "Key revoked or token expired. Create a new key in the Dashboard or run `render login`.")
        return None, None
    if status != 200 or not isinstance(owners, list):
        report("FAIL", f"could not reach the Render API (HTTP {status}): {str(owners)[:120]}",
               "Check network access to api.render.com")
        return None, None
    owner_list = [o.get("owner", {}) for o in owners]
    report("PASS", f"API key valid — {len(owner_list)} workspace(s) visible")

    print("\n== Workspace pin ==")
    pins = read_pins()
    if not pins:
        report("WARN", "project is not pinned to a Render workspace (.claude/render-workspace missing)",
               "Re-run onboarding with --reconfigure, or write the workspace name and tea-... ID to .claude/render-workspace")
        owner = owner_list[0] if owner_list else {}
    else:
        matches = [o for o in owner_list if o.get("id") in pins or (o.get("name") or "").strip() in pins]
        if not matches:
            report("FAIL", f"pinned workspace {pins} is not visible to this API key",
                   "The key belongs to a user without access to the pinned workspace, or the pin is wrong. "
                   "Check `render workspace list -o json`.")
            return key, None
        owner = matches[0]
        report("PASS", f"pinned workspace accessible: '{owner.get('name','').strip()}' ({owner.get('id')})")

        code, current = run(["render", "workspace", "current", "-o", "json"])
        if code != 0 or not current:
            report("WARN", "render CLI cannot report its current workspace (not logged in, or token expired)",
                   "CLI commands (render services list, render logs) need `render login` OR RENDER_API_KEY exported "
                   "in the shell. The guard hook falls back to the API key when the CLI is unavailable.")
        elif not any(p in current for p in pins):
            report("FAIL", "render CLI is pointed at a DIFFERENT workspace than the pin — the guard hook will block every Render command",
                   f"render workspace set {owner.get('id')}")
        else:
            report("PASS", "render CLI current workspace matches the pin")
    return key, owner.get("id")


# ── 4. render.yaml vs live Render ────────────────────────────────

def parse_render_yaml():
    """Minimal parser for the generated blueprint: service names, database
    names, and per-service `sync: false` env var keys. Not a YAML parser —
    good enough for onboarding-generated files and simple hand edits."""
    path = ROOT / "render.yaml"
    if not path.exists():
        return None
    services, databases = [], []
    section = None
    current = None
    pending_key = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0 and stripped.endswith(":"):
            section = stripped[:-1]
            current = None
            continue
        if section == "services":
            if stripped.startswith("- type:"):
                current = {"type": stripped.split(":", 1)[1].strip(), "name": "", "sync_false": [], "healthCheckPath": ""}
                services.append(current)
            elif current is not None:
                if stripped.startswith("name:") and indent <= 4:
                    current["name"] = stripped.split(":", 1)[1].strip()
                elif stripped.startswith("healthCheckPath:"):
                    current["healthCheckPath"] = stripped.split(":", 1)[1].strip()
                elif stripped.startswith("- key:"):
                    pending_key = stripped.split(":", 1)[1].strip()
                elif stripped.startswith("sync:") and "false" in stripped and pending_key:
                    current["sync_false"].append(pending_key)
                    pending_key = None
                elif stripped.startswith("value:") or stripped.startswith("fromDatabase:") or stripped.startswith("- fromGroup:"):
                    pending_key = None
        elif section == "databases":
            if stripped.startswith("- name:"):
                databases.append(stripped.split(":", 1)[1].strip())
    return {"services": services, "databases": databases}


def check_render_state(key, owner_id):
    print("\n== render.yaml vs live Render ==")
    spec = parse_render_yaml()
    if spec is None:
        report("FAIL", "render.yaml not found at repo root", "Re-run onboarding, or write one (see deploy skill blueprint-reference.md)")
        return
    if not owner_id:
        report("WARN", "skipping live checks — no accessible workspace")
        return
    q = f"?ownerId={owner_id}&limit=100"

    # Env group
    status, groups = api_get(f"/env-groups{q}", key)
    names = [g.get("envGroup", {}).get("name") for g in groups] if status == 200 and isinstance(groups, list) else []
    if ENV_GROUP:
        if ENV_GROUP in names:
            report("PASS", f"env group '{ENV_GROUP}' exists")
        else:
            report("FAIL", f"env group '{ENV_GROUP}' not found in the workspace (render.yaml links it via fromGroup — the blueprint sync fails without it)",
                   f"Render Dashboard → Env Groups → New Environment Group → name it '{ENV_GROUP}' (SETUP.md Step 2a)")

    # Services
    status, live = api_get(f"/services{q}", key)
    live_services = {s.get("service", {}).get("name"): s.get("service", {}) for s in live} if status == 200 and isinstance(live, list) else {}
    missing = [s["name"] for s in spec["services"] if s["name"] not in live_services]
    for s in spec["services"]:
        if s["name"] in live_services:
            report("PASS", f"service '{s['name']}' exists ({live_services[s['name']].get('id')})")
    if missing:
        report("FAIL", f"service(s) declared in render.yaml but not on Render: {', '.join(missing)}",
               "Render Dashboard → Blueprints → New Blueprint Instance → select this repo (SETUP.md Step 2c). "
               "The infra-worker never creates services; it will park a blocker until you do this.")

    # Databases
    if spec["databases"]:
        status, dbs = api_get(f"/postgres{q}", key)
        live_dbs = {d.get("postgres", {}).get("name"): d.get("postgres", {}) for d in dbs} if status == 200 and isinstance(dbs, list) else {}
        for name in spec["databases"]:
            if name in live_dbs:
                st = live_dbs[name].get("status", "?")
                report("PASS" if st == "available" else "WARN", f"database '{name}' exists (status: {st})",
                       "Wait for the database to finish provisioning")
            else:
                report("FAIL", f"database '{name}' declared in render.yaml but not on Render",
                       "Created by the Blueprint Instance (SETUP.md Step 2c)")

    # sync: false env vars + health
    for s in spec["services"]:
        svc = live_services.get(s["name"])
        if not svc:
            continue
        if s["sync_false"]:
            status, vars_ = api_get(f"/services/{svc['id']}/env-vars?limit=100", key)
            present = {v.get("envVar", {}).get("key"): v.get("envVar", {}).get("value", "") for v in vars_} if status == 200 and isinstance(vars_, list) else {}
            empty = [k for k in s["sync_false"] if not present.get(k)]
            human_keys = [k for k in empty if "CLERK" in k or "KEY" in k or "SECRET" in k]
            auto_keys = [k for k in empty if k not in human_keys]
            if human_keys:
                report("FAIL", f"'{s['name']}': secret env vars unset: {', '.join(human_keys)}",
                       "Set them in Render Dashboard → the service → Environment (SETUP.md Step 2b)")
            if auto_keys:
                report("WARN", f"'{s['name']}': env vars unset (infra-worker sets these from discovered URLs): {', '.join(auto_keys)}")
            if not empty:
                report("PASS", f"'{s['name']}': all sync:false env vars have values")
        url = (svc.get("serviceDetails") or {}).get("url")
        if url and s["healthCheckPath"]:
            code = http_get(url + s["healthCheckPath"])
            report("PASS" if code == 200 else "WARN", f"'{s['name']}' health {url}{s['healthCheckPath']} → HTTP {code or 'unreachable'}",
                   "First deploy still building, or the last deploy failed — `render logs -r <id> -o text --type build`")


# ── main ─────────────────────────────────────────────────────────

def main():
    print(f"== software-factory preflight: {{PROJECT_NAME}} ==")
    print(f"   project: {ROOT}")
    check_tools()
    check_git()
    if DEPLOY_PLATFORM == "render":
        key, owner_id = check_render_auth()
        if key:
            check_render_state(key, owner_id)
    fails = [r for r in RESULTS if r[0] == "FAIL"]
    warns = [r for r in RESULTS if r[0] == "WARN"]
    print(f"\n== {len(fails)} FAIL · {len(warns)} WARN · {len(RESULTS) - len(fails) - len(warns)} PASS ==")
    if fails:
        print("Not ready. Fix the FAIL lines above, then re-run.")
        sys.exit(1)
    print("Ready. /spec create → paste the /goal prompt.")


if __name__ == "__main__":
    main()
