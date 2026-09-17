#!/usr/bin/env python3
"""
Software Factory — Project Onboarding

Sets up the Claude Code orchestration system for a target project.
Copies generic skills, renders customizable templates, and generates
project-specific CLAUDE.md and settings.

Usage:
    python onboard.py                       # Setup in current directory
    python onboard.py /path/to/project      # Setup in target dir (created if missing)
    python onboard.py --reconfigure         # Re-run with saved config
    python onboard.py --preflight [path]    # Only run the project's readiness check
"""

import getpass
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Optional


# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────

@dataclass
class ProjectConfig:
    project_name: str = ""
    project_slug: str = ""
    project_description: str = ""
    domain: str = ""
    frontend_framework: str = "none"
    backend_framework: str = "none"
    database: str = "none"
    deploy_platform: str = "none"
    env_group_name: str = "general_builder_keys"
    render_workspace: str = ""
    render_workspace_id: str = ""
    auth_provider: str = "none"
    design_context: str = ""
    dev_server_port: int = 3000
    dev_server_command: str = "npm run dev"
    testing_policy: str = "local"
    mode: str = "quick"            # quick (defaults, plain-language runner) | custom (developer chooses)
    push_policy: str = "human"     # human (review checkpoint) | factory (runner pushes)

    def to_replacements(self) -> dict:
        """Return a dict of {{PLACEHOLDER}} → value for template rendering."""
        return {
            "{{MODE}}": self.mode,
            "{{MODE_SECTION}}": self._mode_section(),
            "{{PUSH_POLICY}}": self.push_policy,
            "{{PUSH_POLICY_LINE}}": self._push_policy_line(),
            "{{ENV_GROUP_LINE}}": (
                f"- Shared env group: `{self.env_group_name}` (linked to all services via render.yaml `fromGroup`; created empty by provision.py if missing)"
                if self.env_group_name else
                "- Shared env group: none (add one to render.yaml with `fromGroup` if services need shared keys)"
            ),
            "{{QUICKSTART_PERMISSIONS}}": QUICKSTART_PERMISSIONS if self.mode == "quick" else "",
            "{{PROJECT_NAME}}": self.project_name,
            "{{PROJECT_SLUG}}": self.project_slug,
            "{{PROJECT_DESCRIPTION}}": self.project_description,
            "{{DOMAIN}}": self.domain,
            "{{FRONTEND_FRAMEWORK}}": self.frontend_framework,
            "{{BACKEND_FRAMEWORK}}": self.backend_framework,
            "{{DATABASE}}": self.database,
            "{{DEPLOY_PLATFORM}}": self.deploy_platform,
            "{{ENV_GROUP_NAME}}": self.env_group_name,
            "{{RENDER_WORKSPACE}}": self.render_workspace or self.render_workspace_id or "(not pinned)",
            "{{RENDER_WORKSPACE_ID}}": self.render_workspace_id or "(no ID pinned)",
            # Prefer the ID for `render workspace set` — names can carry whitespace
            "{{RENDER_WORKSPACE_SET_TARGET}}": self.render_workspace_id or self.render_workspace or "<workspace>",
            "{{AUTH_PROVIDER}}": self.auth_provider,
            "{{AUTH_SECTION}}": self._auth_section(),
            "{{DESIGN_CONTEXT}}": self.design_context,
            "{{DEV_SERVER_PORT}}": str(self.dev_server_port),
            "{{DEV_SERVER_COMMAND}}": self.dev_server_command,
            "{{TESTING_POLICY}}": self.testing_policy,
        }

    def _push_policy_line(self) -> str:
        if self.push_policy == "factory":
            return ("- **Push policy: factory.** After a deploy subtask commits, the runner runs `git push` itself, "
                    "records the SHA in the Progress Log, and then spawns the deploy-verification subtask. No human push checkpoint.")
        return ("- **Push policy: human.** Deploy subtasks commit and then raise an `external-action` blocker; "
                "the human reviews and runs `git push`. Render auto-deploys on push.")

    def _mode_section(self) -> str:
        if self.mode != "quick":
            return ""
        return """## Working Mode: Quick Start

This project was set up in Quick Start mode. The person running it may not be a developer. Every session — runner and workers — follows these rules:

- **Plain language, always.** Describe what is happening in terms of the product ("the sign-in page", "saving an invoice"), not the stack. Expand any technical term the first time it is used. No file paths or command names in messages to the human unless they must type them, and then give the exact line to paste.
- **Blockers are questions, not tickets.** When the runner needs a human decision, ask it as a short question with 2–3 concrete options and a recommendation. Accept the answer in chat: write it onto the blocker's `Resolution:` line yourself and continue. Never ask the human to edit a file in `briefs/`.
- **Anything a script can do, the human does not.** Render services come from `.claude/scripts/provision.py`, readiness from `.claude/scripts/preflight.py`. If either reports a `[FAIL]`, relay its `→ fix` line verbatim — those are written for non-developers.
- **Money and time are visible.** When work will start billing (new Render resources) or take a long time (a full deploy cycle), say so in one sentence before doing it.
- **Done means they can use it.** The final message of a completed brief leads with the live URL and what they can do there, not with what was built."""

    def _auth_section(self) -> str:
        if self.auth_provider == "clerk":
            return """### Authentication — Clerk

**Do NOT implement custom auth.** No password hashing, no JWT generation, no session management, no login/signup forms from scratch. Use Clerk for all authentication.

- **Frontend**: Use `@clerk/nextjs` — `<ClerkProvider>` in layout, `<SignIn>`, `<SignUp>`, `<UserButton>` components, `auth()` for server-side auth checks, `useAuth()` for client-side
- **Backend**: Use `clerk-backend-api` Python SDK — verify session tokens from the `Authorization: Bearer <token>` header. Protect routes with a dependency that validates the Clerk JWT.
- **Keys**: `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` and `CLERK_SECRET_KEY` are declared in render.yaml (`sync: false`) and set in the Render Dashboard by the human.
- **Auth is infrastructure, not a feature.** It should be set up in the first backend task (Clerk middleware) before any user-specific endpoints are built. Models that need `user_id` depend on auth being in place."""
        return ""


# Hooks installed into .claude/hooks/ — must match what settings.json.tpl wires
HOOK_FILES = [
    "brief-progress-guard.sh",
    "trajectory-log.sh",
    "render-workspace-guard.sh",
]

# Helper scripts installed into .claude/scripts/ — (template name, installed name)
SCRIPT_FILES = [
    ("render-api-key.sh", "render-api-key.sh"),   # copied as-is: credential resolver
    ("render_yaml.py", "render_yaml.py"),         # copied as-is: shared render.yaml reader
    ("preflight.py.tpl", "preflight.py"),         # rendered: readiness check
    ("provision.py.tpl", "provision.py"),         # rendered: apply render.yaml via the Render API
]

# Extra permission rules for Quick Start projects: an unattended /goal run must
# not stop for approval on every command. The workspace guard hook remains the
# hard safety boundary for anything touching Render. Rendered into
# settings.json.tpl as a JSON fragment (leading comma included).
QUICKSTART_PERMISSIONS = """,
      "Read", "Edit", "Write", "Glob", "Grep", "Task",
      "Bash(git *)", "Bash(gh *)",
      "Bash(python3 *)", "Bash(python *)", "Bash(pip *)", "Bash(pip3 *)", "Bash(pytest*)", "Bash(uvicorn *)",
      "Bash(npm *)", "Bash(npx *)", "Bash(node *)",
      "Bash(render *)", "Bash(curl *)",
      "Bash(ls*)", "Bash(cat *)", "Bash(head *)", "Bash(tail *)", "Bash(grep *)", "Bash(find *)", "Bash(wc *)",
      "Bash(mkdir *)", "Bash(touch *)", "Bash(cp *)", "Bash(mv *)", "Bash(lsof *)", "Bash(kill *)", "Bash(sleep *)",
      "Bash(cd *)", "Bash(echo *)", "Bash(printf *)", "Bash(test *)", "Bash([ *)", "Bash(which *)", "Bash(env*)", "Bash(export *)",
      "Bash(.claude/scripts/*)", "Bash(bash .claude/scripts/*)", "Bash(sh .claude/scripts/*)\""""

# Smart defaults by framework
FRAMEWORK_DEFAULTS = {
    "react":       {"port": 5173, "command": "npm run dev"},
    "vue":         {"port": 5173, "command": "npm run dev"},
    "svelte":      {"port": 5173, "command": "npm run dev"},
    "nextjs":      {"port": 3000, "command": "npm run dev"},
    "static-html": {"port": 3000, "command": "npx serve public -l 3000"},
    "express":     {"port": 3000, "command": "node server.js"},
    "fastapi":     {"port": 8000, "command": "uvicorn main:app --reload --port 8000"},
    "django":      {"port": 8000, "command": "python manage.py runserver 8000"},
    "flask":       {"port": 5000, "command": "flask run --port 5000"},
}


# ──────────────────────────────────────────────
# Interactive Questionnaire
# ──────────────────────────────────────────────

def ask(prompt: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    result = input(f"  {prompt}{suffix}: ").strip()
    return result or default


def ask_choice(prompt: str, choices: list, default: str = "") -> str:
    print(f"\n  {prompt}")
    for i, choice in enumerate(choices, 1):
        marker = " *" if choice == default else ""
        print(f"    {i}. {choice}{marker}")
    while True:
        raw = input(f"  Choose [1-{len(choices)}]: ").strip()
        if not raw and default:
            return default
        try:
            idx = int(raw) - 1
            if 0 <= idx < len(choices):
                return choices[idx]
        except ValueError:
            if raw in choices:
                return raw
        print(f"  Please enter a number 1-{len(choices)}")


def machine_preflight():
    """Report the tools a net-new user needs before anything else happens.

    Non-blocking: the wizard continues either way, but a missing tool is
    much cheaper to learn about here than from a blocked brief. The
    per-project check (.claude/scripts/preflight.py, /preflight) covers the
    Render-side state after onboarding.
    """
    print()
    print("  --- Machine check ---")

    def line(ok, label, fix=""):
        mark = "ok " if ok else "MISSING"
        print(f"    [{mark}] {label}" + (f"  → {fix}" if fix and not ok else ""))

    line(True, f"python {sys.version.split()[0]}")
    ok, out = run_cmd(["git", "--version"], Path.cwd())
    line(ok, out if ok else "git", "install git 2.28+")

    render_ok = shutil.which("render") is not None
    line(render_ok, "render CLI", "brew install render && render login")
    if render_ok:
        name, ws_id = detect_render_workspace()
        expired = render_token_expired()
        if not name and not ws_id:
            line(False, "render login (no ~/.render/cli.yaml workspace)", "render login")
        elif expired:
            line(False, f"render login token EXPIRED (workspace '{name}')",
                 "render login  — or add a long-lived API key when asked below")
        else:
            line(True, f"render login → workspace '{name}' ({ws_id})")

    gh_ok = shutil.which("gh") is not None
    if gh_ok:
        auth_ok, _ = run_cmd(["gh", "auth", "status"], Path.cwd())
        line(auth_ok, "gh CLI authenticated" if auth_ok else "gh CLI (not logged in)", "gh auth login")
    else:
        line(False, "gh CLI (optional — repo creation)", "brew install gh && gh auth login")

    line(shutil.which("dev-browser") is not None, "dev-browser (frontend screenshots)",
         "npm install -g dev-browser")
    node_ok = shutil.which("node") is not None
    if node_ok:
        _, ver = run_cmd(["node", "--version"], Path.cwd())
        line(True, f"node {ver}")
    else:
        line(False, "node (local frontend dev server)", "install Node 18+")
    print()


def render_token_expired() -> bool:
    cfg = Path.home() / ".render" / "cli.yaml"
    if not cfg.exists():
        return False
    import time
    for line in cfg.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s+expires_at:\s*(\d+)", line)
        if m:
            return int(m.group(1)) < time.time()
    return False


def write_local_secret(claude_dir: Path, key: str, value: str):
    """Merge one env var into .claude/settings.local.json (gitignored).

    Claude Code injects the file's "env" block into every Bash call and
    hook, so RENDER_API_KEY placed here reaches the CLI, curl, and the
    workspace guard without touching the user's shell profile.
    """
    path = claude_dir / "settings.local.json"
    data = {}
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            data = {}
    data.setdefault("env", {})[key] = value
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def detect_render_workspace() -> tuple:
    """Read the workspace the Render CLI is currently pointed at.

    `render login` writes ~/.render/cli.yaml with `workspace: tea-...` (ID)
    and `workspace_name: '...'`. Reading the file avoids a network call and
    works even when the stored token has expired. Returns (name, id) with
    both stripped — workspace names can carry trailing whitespace, which is
    why the guard hook pins by ID as well.
    """
    cfg = Path.home() / ".render" / "cli.yaml"
    if not cfg.exists():
        return "", ""
    name = ws_id = ""
    for line in cfg.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^(workspace|workspace_name):\s*(.*)$", line)
        if not m:
            continue
        value = m.group(2).strip().strip("'\"").strip()
        if m.group(1) == "workspace":
            ws_id = value
        else:
            name = value
    return name, ws_id


def ask_secret(prompt: str) -> str:
    """Hidden input on a terminal; plain input when piped (tests, CI)."""
    try:
        return (getpass.getpass(prompt) if sys.stdin.isatty() else input(prompt)).strip()
    except (EOFError, KeyboardInterrupt):
        return ""


def ask_render_api_key(config: ProjectConfig):
    print("\n  The `render login` token expires. A long-lived API key keeps autonomous runs")
    print("  working: Render Dashboard → Account Settings → API Keys → Create. Input is hidden.")
    config.render_api_key_input = ask_secret("  Render API key (rnd_...; blank = rely on `render login`): ")


def ask_clerk_keys(config: ProjectConfig):
    print("\n  Sign-in is handled by Clerk (clerk.com). Create an application there, then paste its two keys.")
    print("  Blank is fine — you can add them later; sign-in just won't work until you do. Input is hidden.")
    secrets = {}
    pk = ask_secret("  Clerk publishable key (pk_...): ")
    sk = ask_secret("  Clerk secret key (sk_...): ")
    if pk:
        secrets["NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY"] = pk
    if sk:
        secrets["CLERK_SECRET_KEY"] = sk
    config.secrets_input = secrets  # not a dataclass field → excluded from asdict()


def interview_quick() -> ProjectConfig:
    """Quick Start: four plain questions; every technical choice takes the default."""
    config = ProjectConfig(mode="quick", push_policy="factory", env_group_name="")

    print()
    print("=" * 60)
    print("  SOFTWARE FACTORY — Quick Start")
    print("=" * 60)
    print()
    print("  Four questions. Everything technical is chosen for you:")
    print("  a web app (Next.js) with an API (FastAPI) and a database (PostgreSQL),")
    print("  hosted on Render, in one GitHub repository. Press Enter to accept [defaults].")
    print()

    config.project_name = ask("What is the project called?")
    config.project_slug = re.sub(r"-+", "-", re.sub(r"[^a-z0-9-]", "-", config.project_name.lower())).strip("-")
    config.project_description = ask("In one sentence, what does it do?")
    config.domain = ask("Who is it for, or what world does it live in? (e.g. 'freelancers sending invoices')")
    config.design_context = (
        f"This product lives in the world of {config.domain}. "
        f"Design choices should feel domain-specific, not generic SaaS. "
        f"See `session/design-direction.md` for the full design direction when it exists."
    )

    config.frontend_framework = "nextjs"
    config.backend_framework = "fastapi"
    config.database = "postgresql"
    config.deploy_platform = "render"
    fe = FRAMEWORK_DEFAULTS["nextjs"]
    config.dev_server_port, config.dev_server_command = fe["port"], fe["command"]

    login = ask("Will people need to sign in with an account? (y/n)", "n").lower() in ("y", "yes")
    config.auth_provider = "clerk" if login else "none"
    if login:
        ask_clerk_keys(config)

    detected_name, detected_id = detect_render_workspace()
    if detected_name or detected_id:
        config.render_workspace, config.render_workspace_id = detected_name, detected_id
        print(f"\n  Render workspace: '{detected_name}' ({detected_id}) — this project is pinned to it.")
    else:
        print("\n  No Render login found. Run `render login` before provisioning; the pin can be set later with --reconfigure.")
    ask_render_api_key(config)
    return config


def interview() -> ProjectConfig:
    """Custom: the developer chooses the stack."""
    config = ProjectConfig(mode="custom")

    print()
    print("=" * 60)
    print("  SOFTWARE FACTORY — Project Onboarding (Custom)")
    print("=" * 60)
    print()
    print("  Answer a few questions to set up the orchestration system.")
    print("  Press Enter to accept defaults shown in [brackets].")
    print()

    # ── Identity ──
    print("  --- Project Identity ---")
    config.project_name = ask("Project name")
    config.project_slug = re.sub(r"[^a-z0-9-]", "-", config.project_name.lower())
    config.project_slug = re.sub(r"-+", "-", config.project_slug).strip("-")
    config.project_slug = ask("Project slug (for URLs)", config.project_slug)
    config.project_description = ask("Describe your project in 1-2 sentences")
    config.domain = ask("Domain/industry (e.g., 'finance', 'healthcare', 'e-commerce')")

    # ── Design Direction ──
    print("\n  --- Design Direction ---")
    config.design_context = ask(
        "Design context (brand aesthetic, visual feel — or press Enter to auto-generate)"
    )
    if not config.design_context:
        config.design_context = (
            f"This product lives in the world of {config.domain}. "
            f"Design choices should feel domain-specific, not generic SaaS. "
            f"See `session/design-direction.md` for the full design direction when it exists."
        )

    # ── Tech Stack ──
    print("\n  --- Tech Stack ---")
    config.frontend_framework = ask_choice(
        "Frontend framework:",
        ["react", "vue", "svelte", "nextjs", "static-html", "none"],
        default="nextjs",
    )
    config.backend_framework = ask_choice(
        "Backend framework:",
        ["fastapi", "express", "django", "flask", "none"],
        default="fastapi",
    )
    config.database = ask_choice(
        "Database:",
        ["postgresql", "sqlite", "mongodb", "none"],
        default="postgresql",
    )

    # ── Deployment ──
    print("\n  --- Deployment ---")
    config.deploy_platform = ask_choice(
        "Deployment platform (Render is the only supported platform in V1):",
        ["render", "none"],
        default="render",
    )

    if config.deploy_platform == "render":
        config.env_group_name = ask(
            "Render shared env group name (for API keys)", "general_builder_keys"
        )

        detected_name, detected_id = detect_render_workspace()
        if detected_name or detected_id:
            print(f"\n  Render CLI is logged in to workspace: '{detected_name}' ({detected_id or 'no ID'})")
            if ask("Pin this project to that workspace? (y/n)", "y").lower() in ("y", "yes"):
                config.render_workspace = detected_name
                config.render_workspace_id = detected_id
        if not config.render_workspace and not config.render_workspace_id:
            print("  (No Render CLI login detected — run `render login` later. You can still pin by hand.)")
            config.render_workspace = ask(
                "Render workspace NAME to pin (ALL Render ops blocked outside it; blank = no pin)"
            )
            if config.render_workspace:
                config.render_workspace_id = ask(
                    "Render workspace ID (tea-...; from `render workspace current -o json`; blank = name only)"
                )

        # Long-lived API key (optional). Never stored in factory-config.json;
        # written to .claude/settings.local.json (gitignored) by setup_project.
        ask_render_api_key(config)

        config.push_policy = ask_choice(
            "Who pushes to deploy? 'human' = you review and git push (checkpoint); 'factory' = the runner pushes",
            ["human", "factory"],
            default="human",
        )

    # ── Authentication ──
    print("\n  --- Authentication ---")
    config.auth_provider = ask_choice(
        "User authentication:",
        ["clerk", "none"],
        default="clerk",
    )
    if config.auth_provider == "clerk":
        ask_clerk_keys(config)

    # ── Dev Server ──
    print("\n  --- Dev Server ---")
    fe = FRAMEWORK_DEFAULTS.get(config.frontend_framework, {})
    be = FRAMEWORK_DEFAULTS.get(config.backend_framework, {})

    if config.frontend_framework != "none":
        default_port = fe.get("port", 3000)
        default_cmd = fe.get("command", "npm run dev")
    elif config.backend_framework != "none":
        default_port = be.get("port", 3000)
        default_cmd = be.get("command", "npm start")
    else:
        default_port = 3000
        default_cmd = "npm start"

    config.dev_server_port = int(ask("Dev server port", str(default_port)))
    config.dev_server_command = ask("Dev server start command", default_cmd)

    return config


# ──────────────────────────────────────────────
# Template Rendering
# ──────────────────────────────────────────────

def render_template(content: str, replacements: dict) -> str:
    result = content
    for placeholder, value in replacements.items():
        result = result.replace(placeholder, value)
    return result


def render_file(src: Path, dest: Path, replacements: dict):
    content = src.read_text(encoding="utf-8")
    rendered = render_template(content, replacements)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(rendered, encoding="utf-8")
    print(f"    + {dest.relative_to(dest.parent.parent.parent) if len(dest.parts) > 3 else dest.name}")


def copy_file(src: Path, dest: Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    print(f"    + {dest.relative_to(dest.parent.parent.parent) if len(dest.parts) > 3 else dest.name}")


def copy_directory(src: Path, dest: Path):
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest)
    file_count = sum(1 for _ in dest.rglob("*") if _.is_file())
    print(f"    + {dest.name}/ ({file_count} files)")


# ──────────────────────────────────────────────
# Render Blueprint Generation
# ──────────────────────────────────────────────

# Render production commands by framework (monorepo: commands run from rootDir)
RENDER_BACKEND = {
    "fastapi": {
        "runtime": "python",
        "buildCommand": "pip install -r requirements.txt",
        "startCommand": "uvicorn main:app --host 0.0.0.0 --port $PORT",
    },
    "django": {
        "runtime": "python",
        "buildCommand": "pip install -r requirements.txt && python manage.py collectstatic --noinput",
        "startCommand": "gunicorn project.wsgi:application --bind 0.0.0.0:$PORT",
    },
    "flask": {
        "runtime": "python",
        "buildCommand": "pip install -r requirements.txt",
        "startCommand": "gunicorn app:app --bind 0.0.0.0:$PORT",
    },
    "express": {
        "runtime": "node",
        "buildCommand": "npm install",
        "startCommand": "node server.js",
    },
}

RENDER_FRONTEND = {
    "nextjs": {
        "buildCommand": "npm install --legacy-peer-deps && npm run build",
        "startCommand": "npm run start",
    },
    "react": {
        "buildCommand": "npm install && npm run build",
        "startCommand": "npx serve build -l $PORT",
    },
    "vue": {
        "buildCommand": "npm install && npm run build",
        "startCommand": "npx serve dist -l $PORT",
    },
    "svelte": {
        "buildCommand": "npm install && npm run build",
        "startCommand": "npx serve build -l $PORT",
    },
    "static-html": {
        "buildCommand": "npm install",
        "startCommand": "node server.js",
    },
}


def generate_render_yaml(config: ProjectConfig, target: Path):
    """Generate a starter render.yaml blueprint based on project config.

    Uses monorepo layout: backend/ and frontend/ subdirectories, each
    configured as a separate Render web service with rootDir.
    """
    dest = target / "render.yaml"
    if dest.exists():
        print(f"    . render.yaml (already exists — skipping)")
        return

    lines = [
        f"# Render Blueprint — {config.project_name}",
        f"# Generated by software-factory onboarding. Customize as needed.",
        f"# Docs: https://docs.render.com/blueprint-spec",
        "",
    ]

    services = []

    # Backend service (runs from backend/ directory)
    has_frontend = config.frontend_framework != "none"
    has_backend = config.backend_framework != "none"

    if has_backend:
        be = RENDER_BACKEND.get(config.backend_framework, RENDER_BACKEND["express"])
        svc = [
            f"  - type: web",
            f"    name: {config.project_slug}-api",
            f"    runtime: {be['runtime']}",
            f"    rootDir: backend",
            f"    plan: starter",
            f"    region: oregon",
            f"    buildCommand: {be['buildCommand']}",
            f"    startCommand: {be['startCommand']}",
            f"    healthCheckPath: /health",
            f"    envVars:",
        ]
        if be["runtime"] == "python":
            svc.extend([
                f"      - key: PYTHON_VERSION",
                f'        value: "3.11.6"',
            ])
        if config.database == "postgresql":
            svc.extend([
                f"      - key: DATABASE_URL",
                f"        fromDatabase:",
                f"          name: {config.project_slug}-db",
                f"          property: connectionString",
            ])
        if has_frontend:
            svc.extend([
                f"      - key: FRONTEND_URL",
                f"        sync: false  # Set by provision.py with the actual Render URL (https://)",
                f"      - key: CORS_ORIGINS",
                f"        sync: false  # Set by provision.py with the actual Render URL (https://)",
            ])
        if config.auth_provider == "clerk":
            svc.extend([
                f"      - key: CLERK_SECRET_KEY",
                f"        sync: false  # Set in Render Dashboard after creating Clerk app",
            ])
        if config.env_group_name:
            svc.append(f"      - fromGroup: {config.env_group_name}")
        services.append("\n".join(svc))

    # Frontend service (runs from frontend/ directory)
    if has_frontend:
        fe = RENDER_FRONTEND.get(config.frontend_framework, RENDER_FRONTEND["nextjs"])
        svc = [
            f"  - type: web",
            f"    name: {config.project_slug}-frontend",
            f"    runtime: node",
            f"    rootDir: frontend",
            f"    plan: starter",
            f"    region: oregon",
            f"    buildCommand: {fe['buildCommand']}",
            f"    startCommand: {fe['startCommand']}",
            f"    healthCheckPath: /api/health",
            f"    envVars:",
            f"      - key: NODE_ENV",
            f"        value: production",
            f"      - key: PORT",
            f'        value: "10000"',
        ]
        if has_backend:
            svc.extend([
                f"      - key: API_URL",
                f"        sync: false  # Set by provision.py with the actual Render URL (https://)",
            ])
            if config.frontend_framework == "nextjs":
                svc.extend([
                    f"      - key: NEXT_PUBLIC_API_URL",
                    f"        sync: false  # Same URL, exposed to browser code by Next.js",
                ])
        if config.auth_provider == "clerk":
            svc.extend([
                f"      - key: NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY",
                f"        sync: false  # Set in Render Dashboard after creating Clerk app",
                f"      - key: CLERK_SECRET_KEY",
                f"        sync: false",
            ])
        if config.env_group_name:
            svc.append(f"      - fromGroup: {config.env_group_name}")
        services.append("\n".join(svc))

    if services:
        lines.append("services:")
        lines.append("\n\n".join(services))
        lines.append("")

    # Database (Basic-256mb — $6/month, persistent, no expiry)
    if config.database == "postgresql":
        lines.extend([
            "databases:",
            f"  - name: {config.project_slug}-db",
            f"    plan: basic-256mb",
            f"    region: oregon",
            f"    postgresMajorVersion: 16",
            "",
        ])

    dest.write_text("\n".join(lines), encoding="utf-8")
    print(f"    + render.yaml")


# ──────────────────────────────────────────────
# App Skeleton Generation
# ──────────────────────────────────────────────

BACKEND_SKELETONS = {
    "fastapi": {
        "main.py": '''from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}
''',
        "requirements.txt": "fastapi\nuvicorn\nhttpx\n",
    },
    "express": {
        "server.js": '''const express = require("express");
const cors = require("cors");
const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", (req, res) => res.json({ status: "ok" }));

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`Backend running on port ${PORT}`));
''',
        "package.json": '{\n  "name": "backend",\n  "version": "0.1.0",\n  "private": true,\n  "scripts": { "start": "node server.js" },\n  "dependencies": { "express": "^4.18.0", "cors": "^2.8.5" }\n}\n',
    },
    "django": {
        "requirements.txt": "django\ngunicorn\n",
    },
    "flask": {
        "app.py": '''from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

@app.route("/health")
def health():
    return jsonify(status="ok")
''',
        "requirements.txt": "flask\nflask-cors\ngunicorn\n",
    },
}

FRONTEND_SKELETONS = {
    "nextjs": {
        "package.json": '''{
  "name": "frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start"
  },
  "dependencies": {
    "next": "^14.0.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0",
    "typescript": "^5.0.0",
    "@types/react": "^18.0.0",
    "@types/node": "^20.0.0"
  }
}
''',
        "tsconfig.json": '''{
  "compilerOptions": {
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": false,
    "noEmit": true,
    "incremental": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
  "exclude": ["node_modules"]
}
''',
        "app/layout.tsx": '''export const metadata = {
  title: "APP_TITLE",
  description: "APP_DESC",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
''',
        "app/page.tsx": '''export default function Home() {
  return (
    <main>
      <h1>APP_TITLE</h1>
      <p>Coming soon...</p>
    </main>
  );
}
''',
        "app/api/health/route.ts": '''import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({ status: "ok" });
}
''',
    },
}


def generate_backend_skeleton(config: ProjectConfig, target: Path):
    """Create minimal backend directory so Render's first build succeeds."""
    backend_dir = target / "backend"
    if backend_dir.exists() and any(backend_dir.iterdir()):
        print(f"    . backend/ (already exists — skipping)")
        return

    skeleton = BACKEND_SKELETONS.get(config.backend_framework)
    if not skeleton:
        print(f"    ! No skeleton for {config.backend_framework}")
        return

    backend_dir.mkdir(parents=True, exist_ok=True)
    for filename, content in skeleton.items():
        filepath = backend_dir / filename
        filepath.parent.mkdir(parents=True, exist_ok=True)
        filepath.write_text(content, encoding="utf-8")

    # Add Clerk SDK if auth is configured
    if config.auth_provider == "clerk":
        req_path = backend_dir / "requirements.txt"
        existing = req_path.read_text(encoding="utf-8") if req_path.exists() else ""
        if "clerk" not in existing:
            with open(req_path, "a", encoding="utf-8") as f:
                f.write("clerk-backend-api\n")

    print(f"    + backend/ (skeleton: {config.backend_framework})")


def generate_frontend_skeleton(config: ProjectConfig, target: Path):
    """Create minimal frontend directory so Render's first build succeeds."""
    frontend_dir = target / "frontend"
    if frontend_dir.exists() and any(frontend_dir.iterdir()):
        print(f"    . frontend/ (already exists — skipping)")
        return

    skeleton = FRONTEND_SKELETONS.get(config.frontend_framework)
    if not skeleton:
        print(f"    ! No skeleton for {config.frontend_framework}")
        return

    frontend_dir.mkdir(parents=True, exist_ok=True)
    for filename, content in skeleton.items():
        content = content.replace("APP_TITLE", config.project_name)
        content = content.replace("APP_DESC", config.project_description)
        filepath = frontend_dir / filename
        filepath.parent.mkdir(parents=True, exist_ok=True)
        filepath.write_text(content, encoding="utf-8")

    # Add Clerk package if auth is configured
    if config.auth_provider == "clerk":
        pkg_path = frontend_dir / "package.json"
        if pkg_path.exists():
            import json as _json
            pkg = _json.loads(pkg_path.read_text(encoding="utf-8"))
            pkg.setdefault("dependencies", {})["@clerk/nextjs"] = "^5.0.0"
            pkg_path.write_text(_json.dumps(pkg, indent=2) + "\n", encoding="utf-8")

    print(f"    + frontend/ (skeleton: {config.frontend_framework})")


# ──────────────────────────────────────────────
# Git Repository
# ──────────────────────────────────────────────

def run_cmd(cmd: list, cwd: Path) -> tuple:
    """Run a command, returning (ok, combined output)."""
    try:
        result = subprocess.run(
            cmd, cwd=str(cwd), capture_output=True, text=True, timeout=180
        )
        return result.returncode == 0, (result.stdout + result.stderr).strip()
    except FileNotFoundError:
        return False, f"{cmd[0]}: command not found"
    except subprocess.TimeoutExpired:
        return False, f"{' '.join(cmd)}: timed out"


def setup_git_repo(config: ProjectConfig, target: Path) -> bool:
    """Initialize git, then create and link a GitHub remote, commit, push.

    Returns True when the setup commit is on a remote — the precondition for
    provisioning, since Render builds from GitHub. This is step 3 of the
    factory's contract (clone → wizard → new repo), so the defaults say yes.
    """
    if (target / ".git").is_dir():
        print("    . git repo (already initialized)")
    else:
        ok, out = run_cmd(["git", "init", "-b", "main"], target)
        if not ok:
            print(f"    ! git init failed: {out.splitlines()[0] if out else 'unknown error'}")
            return False
        print("    + git init (branch: main)")

    ok, remotes = run_cmd(["git", "remote"], target)
    if ok and remotes:
        print(f"    . remote '{remotes.split()[0]}' already configured")
    else:
        gh_ok, _ = run_cmd(["gh", "auth", "status"], target)
        if not gh_ok:
            print("    - no GitHub remote (gh CLI missing or not authenticated)")
            print(f"      Add one later: gh repo create {config.project_slug} "
                  f"--private --source=. --remote=origin --push")
        elif ask(f"Create the GitHub repo '{config.project_slug}' now? (y/n)", "y").lower() in ("y", "yes"):
            visibility = "private" if config.mode == "quick" else ask_choice(
                "Repository visibility:", ["private", "public"], default="private"
            )
            ok, out = run_cmd(
                ["gh", "repo", "create", config.project_slug,
                 f"--{visibility}", "--source=.", "--remote=origin"],
                target,
            )
            if ok:
                print(f"    + GitHub repo '{config.project_slug}' ({visibility}) → remote 'origin'")
            else:
                print(f"    ! gh repo create failed: {out.splitlines()[0] if out else 'unknown error'}")
        else:
            print("    - skipped GitHub repo creation")

    # Initial commit — Render needs the skeleton + render.yaml on the remote
    ok, dirty = run_cmd(["git", "status", "--porcelain"], target)
    if ok and dirty:
        if ask("Commit the factory setup? (y/n)", "y").lower() in ("n", "no"):
            print("    - skipped initial commit")
            return False
        run_cmd(["git", "add", "-A"], target)
        ok, out = run_cmd(["git", "commit", "-m", "factory setup"], target)
        if not ok:
            print(f"    ! commit failed: {out.splitlines()[0] if out else 'unknown error'}")
            return False
        print("    + commit 'factory setup'")

    ok, remotes = run_cmd(["git", "remote"], target)
    if not (ok and remotes):
        return False
    ok, status = run_cmd(["git", "status", "-sb"], target)
    head = status.splitlines()[0] if status else ""
    if "..." in head and "ahead" not in head:
        print("    . remote is up to date")
        return True
    if ask("Push to GitHub now? (y/n)", "y").lower() in ("n", "no"):
        print("    - skipped push (run 'git push -u origin main' before provisioning)")
        return False
    ok, out = run_cmd(["git", "push", "-u", "origin", "HEAD"], target)
    print("    + pushed to origin" if ok
          else f"    ! push failed: {out.splitlines()[-1] if out else 'unknown error'}")
    return ok


def provision_render(config: ProjectConfig, target: Path, pushed: bool):
    """Step 3 of the contract: the new repo gets its live services.

    Runs the installed provisioner (idempotent). Skips with a clear message
    when the preconditions are missing rather than failing the wizard.
    """
    script = target / ".claude" / "scripts" / "provision.py"
    print("\n  Render services:")
    if not script.exists():
        print("    - provisioner not installed")
        return
    if not pushed:
        print("    - skipped: the repo is not on GitHub yet. When it is, run:")
        print("      python3 .claude/scripts/provision.py")
        return
    ok, source = run_cmd(["bash", str(target / ".claude" / "scripts" / "render-api-key.sh"), "--source"], target)
    if not ok or not source or source.strip() == "cli-token-EXPIRED":
        print("    - skipped: no working Render credential (run `render login` or add an API key), then run:")
        print("      python3 .claude/scripts/provision.py")
        return
    print("    Creating the database and web services on Render from render.yaml.")
    print("    Paid plans (starter services, basic-256mb database ≈ $20/month) start billing immediately.")
    if ask("    Create them now? (y/n)", "y").lower() in ("n", "no"):
        print("    - skipped. Later: python3 .claude/scripts/provision.py")
        return
    print()
    code = subprocess.call([sys.executable, str(script), "--yes"], cwd=str(target))
    if code != 0:
        print("\n    ! provisioning did not complete — fix the [FAIL] above and re-run: python3 .claude/scripts/provision.py")


# ──────────────────────────────────────────────
# Project Setup
# ──────────────────────────────────────────────

def setup_project(config: ProjectConfig, target: Path, factory: Path):
    skills_src = factory / "skills"
    templates = factory / "templates"
    replacements = config.to_replacements()

    claude_dir = target / ".claude"
    skills_dir = claude_dir / "skills"
    agents_dir = claude_dir / "agents"

    print()
    print("-" * 40)
    print("  Installing orchestration system...")
    print("-" * 40)

    # ── 1. Generic skills (copy as-is) ──
    print("\n  Generic skills:")
    for skill_name in ["orchestrate", "worker-protocol", "backend-test", "spec", "status", "bold-design"]:
        src = skills_src / skill_name
        dest = skills_dir / skill_name
        if src.exists():
            copy_directory(src, dest)

    # ── 2. Customized skills (render from templates) ──
    print("\n  Customized skills:")

    # verify-ui (only if frontend)
    if config.frontend_framework != "none":
        src = templates / "skills" / "verify-ui" / "SKILL.md.tpl"
        if src.exists():
            render_file(src, skills_dir / "verify-ui" / "SKILL.md", replacements)

    # deploy skill (platform-specific)
    if config.deploy_platform != "none":
        platform_dir = templates / "skills" / "deploy" / config.deploy_platform
        if platform_dir.exists():
            # Render the main SKILL.md
            skill_tpl = platform_dir / "SKILL.md.tpl"
            if skill_tpl.exists():
                render_file(skill_tpl, skills_dir / "deploy" / "SKILL.md", replacements)

            # Copy reference files (non-template .md files)
            for ref_file in sorted(platform_dir.glob("*.md")):
                if not ref_file.name.endswith(".tpl"):
                    copy_file(ref_file, skills_dir / "deploy" / ref_file.name)
        else:
            print(f"    ! No deploy adapter for '{config.deploy_platform}' — skipping")
            print(f"      (only 'render' is currently supported; the infra-worker will not be installed)")
            config.deploy_platform = "none"

    # ── 3. Agent definitions (render from templates) ──
    print("\n  Agent definitions:")

    agent_configs = {
        "backend-worker": config.backend_framework != "none",
        "frontend-worker": config.frontend_framework != "none",
        "infra-worker": config.deploy_platform != "none",
    }

    for agent_name, should_install in agent_configs.items():
        if not should_install:
            print(f"    - {agent_name} (skipped — not needed)")
            continue
        src = templates / "agents" / f"{agent_name}.md.tpl"
        if src.exists():
            render_file(src, agents_dir / f"{agent_name}.md", replacements)

    # ── 4. Settings.json + hooks (harness-enforced documentation + trajectory) ──
    print("\n  Configuration:")

    settings_tpl = templates / "settings.json.tpl"
    settings_path = claude_dir / "settings.json"
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    settings_path.write_text(render_template(settings_tpl.read_text(encoding="utf-8"), replacements), encoding="utf-8")
    json.loads(settings_path.read_text(encoding="utf-8"))  # fail loudly if the rendered JSON is broken
    print(f"    + settings.json (permissions + hooks{'; Quick Start allowlist' if config.mode == 'quick' else ''})")

    # Explicit list (not a glob): these are exactly the hooks settings.json
    # wires up, so stray files in the templates folder can never leak.
    hooks_src = templates / "hooks"
    hooks_dir = claude_dir / "hooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    for hook_name in HOOK_FILES:
        hook_file = hooks_src / hook_name
        if not hook_file.exists():
            print(f"    ! missing hook template: {hook_name}")
            continue
        dest = hooks_dir / hook_name
        shutil.copy2(hook_file, dest)
        dest.chmod(0o755)
        print(f"    + .claude/hooks/{hook_name}")

    # Helper scripts: API-key resolver (as-is) + preflight (rendered)
    scripts_src = templates / "scripts"
    scripts_dir = claude_dir / "scripts"
    scripts_dir.mkdir(parents=True, exist_ok=True)
    for tpl_name, out_name in SCRIPT_FILES:
        src = scripts_src / tpl_name
        if not src.exists():
            print(f"    ! missing script template: {tpl_name}")
            continue
        dest = scripts_dir / out_name
        if tpl_name.endswith(".tpl"):
            dest.write_text(render_template(src.read_text(encoding="utf-8"), replacements), encoding="utf-8")
        else:
            shutil.copy2(src, dest)
        dest.chmod(0o755)
        print(f"    + .claude/scripts/{out_name}")

    # Preflight skill (/preflight wraps the script above)
    preflight_tpl = templates / "skills" / "preflight" / "SKILL.md.tpl"
    if preflight_tpl.exists():
        render_file(preflight_tpl, skills_dir / "preflight" / "SKILL.md", replacements)

    # Secrets → .claude/settings.local.json (gitignored): Render API key,
    # Clerk keys. provision.py reads Clerk keys from here for sync:false vars.
    local_secrets = dict(getattr(config, "secrets_input", {}) or {})
    api_key = getattr(config, "render_api_key_input", "")
    if config.deploy_platform == "render" and api_key:
        local_secrets["RENDER_API_KEY"] = api_key
    for k, v in local_secrets.items():
        write_local_secret(claude_dir, k, v)
    if local_secrets:
        print(f"    + .claude/settings.local.json ({', '.join(sorted(local_secrets))} — gitignored)")

    # Workspace pin — the render-workspace-guard hook fail-closes Render
    # CLI/API commands unless the current workspace matches a line in this
    # file. Name AND ID are written when known (names can carry whitespace).
    if config.deploy_platform == "render" and (config.render_workspace or config.render_workspace_id):
        pins = [p for p in (config.render_workspace, config.render_workspace_id) if p]
        pin_path = claude_dir / "render-workspace"
        pin_path.write_text("\n".join(pins) + "\n", encoding="utf-8")
        print(f"    + .claude/render-workspace (pinned to {' / '.join(repr(p) for p in pins)})")

    # ── 5. CLAUDE.md ──
    claude_tpl = templates / "CLAUDE.md.tpl"
    if claude_tpl.exists():
        render_file(claude_tpl, target / "CLAUDE.md", replacements)

    # ── 5b. Brief board (committed Kanban: folder = status) ──
    print("\n  Brief board:")
    briefs_dir = target / "briefs"
    for folder in ["1-backlog", "2-active", "3-blocked", "4-done"]:
        (briefs_dir / folder).mkdir(parents=True, exist_ok=True)
        gitkeep = briefs_dir / folder / ".gitkeep"
        if not gitkeep.exists():
            gitkeep.write_text("", encoding="utf-8")
    board_readme_src = templates / "briefs-README.md"
    if board_readme_src.exists():
        shutil.copy2(board_readme_src, briefs_dir / "README.md")
    print(f"    + briefs/ (1-backlog, 2-active, 3-blocked, 4-done + README)")

    # ── 6. .gitignore ──
    gitignore_path = target / ".gitignore"
    lines_to_add = ["session/", ".claude/settings.local.json", ".claude/.turn-marker", ".env", ".env.local", "*.env.local"]
    if gitignore_path.exists():
        existing = gitignore_path.read_text(encoding="utf-8")
        additions = [l for l in lines_to_add if l not in existing]
        if additions:
            with open(gitignore_path, "a", encoding="utf-8") as f:
                f.write("\n# Orchestration (added by software-factory)\n")
                for line in additions:
                    f.write(f"{line}\n")
            print(f"    + .gitignore (updated)")
        else:
            print(f"    . .gitignore (already configured)")
    else:
        gitignore_path.write_text(
            "# Orchestration (added by software-factory)\n" + "".join(f"{l}\n" for l in lines_to_add),
            encoding="utf-8",
        )
        print(f"    + .gitignore (created)")

    # ── 7. render.yaml (if platform is render) ──
    if config.deploy_platform == "render":
        print("\n  Infrastructure:")
        generate_render_yaml(config, target)

    # ── 8. Skeleton app directories (so first Render deploy succeeds) ──
    print("\n  App skeleton:")
    if config.backend_framework != "none":
        generate_backend_skeleton(config, target)
    if config.frontend_framework != "none":
        generate_frontend_skeleton(config, target)

    # ── 9. Save config for re-onboarding ──
    config_path = claude_dir / "factory-config.json"
    config_path.write_text(json.dumps(asdict(config), indent=2) + "\n", encoding="utf-8")
    print(f"    + factory-config.json (for re-onboarding)")

    # ── 10. Git repo + remote (.gitignore and all files exist by now) ──
    print("\n  Git:")
    pushed = setup_git_repo(config, target)

    # ── 11. Live services on Render (step 3 of the contract) ──
    if config.deploy_platform == "render":
        provision_render(config, target, pushed)

    # ── Done ──
    print()
    print("=" * 60)
    print("  SETUP COMPLETE")
    print("=" * 60)
    blocked_hint = ("If the run stops with a question, answer it in the chat — the runner records it and continues."
                    if config.mode == "quick" else
                    "If a brief lands in briefs/3-blocked/ it NEEDS YOU: answer its Resolution: lines, then run /orchestrate to resume.")
    print(f"""
  Your new project repo is set up: code skeleton, brief board, skills, hooks,
  render.yaml{', GitHub remote' if pushed else ''}.

  Next steps:
    1. cd {target}
    2. Check readiness:  python3 .claude/scripts/preflight.py
       (or /preflight inside Claude Code) — fix every FAIL line; it tells you how
    3. Open Claude Code:  claude
    4. Run:  /spec create "describe what you want to build"
    5. Approve the brief, then paste the /goal prompt it hands you.
       The factory works until the brief is done or needs you.
    6. /status shows the board at any time.
    7. {blocked_hint}

  Skills installed:
    - /preflight     Readiness check: tools, git, Render auth, services, secrets
    - /spec          Create goal briefs + their /goal prompts
    - /orchestrate   Board runner: decompose, delegate to subagents, route
    - /status        Board diagnostic: progress, blockers, requirements
""")

    if config.frontend_framework != "none":
        print("    - /bold-design   Domain-specific UI design enforcement")
        print("    - /verify-ui     Visual verification with dev-browser screenshots")

    if config.deploy_platform != "none":
        platform_name = config.deploy_platform.capitalize()
        print(f"    - /deploy        {platform_name} infrastructure management")

    print(f"""
  Worker subagents (delegated via the Task tool):
    - backend-worker   {'Installed' if config.backend_framework != 'none' else 'Skipped (no backend)'}
    - frontend-worker  {'Installed' if config.frontend_framework != 'none' else 'Skipped (no frontend)'}
    - infra-worker     {'Installed' if config.deploy_platform != 'none' else 'Skipped (no deploy platform)'}

  See docs/HUMAN-INTERVENTION-GUIDE.md in the software-factory
  repo for when you'll need to step in during orchestration.
""")


# ───────────────────────────────���──────────────
# Main
# ──────────────────────────────────────────────

def main():
    # Determine factory directory (where this script lives)
    script_dir = Path(__file__).resolve().parent
    factory_dir = script_dir / "factory"

    if not factory_dir.exists():
        print(f"Error: factory/ directory not found at {factory_dir}")
        print("Make sure you're running this from the software-factory repo.")
        sys.exit(1)

    # Determine target directory
    reconfigure = "--reconfigure" in sys.argv
    preflight_only = "--preflight" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]

    if args:
        target = Path(args[0]).resolve()
    else:
        target = Path.cwd()

    if preflight_only:
        script = target / ".claude" / "scripts" / "preflight.py"
        if not script.exists():
            print(f"  No preflight script at {script} — onboard the project first.")
            sys.exit(1)
        sys.exit(subprocess.call([sys.executable, str(script)], cwd=str(target)))

    machine_preflight()

    # Mode: Quick Start (defaults, plain-language runner) or Custom (developer chooses the stack)
    if "--quick" in sys.argv:
        mode = "quick"
    elif "--custom" in sys.argv:
        mode = "custom"
    else:
        mode = "custom" if input("  Choose your own tech stack (developers)? [y/N]: ").strip().lower() in ("y", "yes") else "quick"

    if not target.exists():
        print(f"\n  Target directory does not exist: {target}")
        if input("  Create it? [Y/n]: ").strip().lower() in ("n", "no"):
            print("  Aborted.")
            sys.exit(0)
        target.mkdir(parents=True)
        print(f"  Created {target}")
    elif not target.is_dir():
        print(f"Error: Target path is not a directory: {target}")
        sys.exit(1)

    print(f"\n  Target project: {target}")

    # Check for existing config (re-onboarding)
    existing_config = target / ".claude" / "factory-config.json"
    if reconfigure and existing_config.exists():
        print(f"  Loading saved configuration from {existing_config.name}...")
        saved = json.loads(existing_config.read_text(encoding="utf-8"))
        config = ProjectConfig(**saved)

        print()
        print("  Saved configuration:")
        for key, value in asdict(config).items():
            print(f"    {key}: {value}")

        confirm = input("\n  Re-apply this configuration? [Y/n]: ").strip().lower()
        if confirm in ("n", "no"):
            config = interview_quick() if mode == "quick" else interview()
        # else use saved config
    else:
        config = interview_quick() if mode == "quick" else interview()

    # Show generation summary
    print()
    print("-" * 50)
    print("  What will be generated:")
    print("-" * 50)
    print(f"  Project:    {config.project_name} ({config.project_slug})")
    print(f"  Domain:     {config.domain}")
    print(f"  Mode:       {'Quick Start (defaults; runner pushes; plain-language)' if config.mode == 'quick' else 'Custom'}")
    print()

    def _status(enabled, label, detail=""):
        mark = "+" if enabled else "-"
        suffix = f" ({detail})" if detail and enabled else f" (skipped)" if not enabled else ""
        print(f"    [{mark}] {label}{suffix}")

    _status(True, "CLAUDE.md", "project context, architecture, deployment")
    _status(config.frontend_framework != "none", "Frontend skeleton",
            f"{config.frontend_framework}")
    _status(config.backend_framework != "none", "Backend skeleton",
            f"{config.backend_framework}")
    _status(config.deploy_platform != "none", "render.yaml",
            f"{config.deploy_platform}")
    _status(config.database != "none", "Database",
            f"{config.database}")
    _status(config.auth_provider != "none", "Authentication",
            f"{config.auth_provider}")
    print()

    _status(config.frontend_framework != "none", "frontend-worker agent")
    _status(config.backend_framework != "none", "backend-worker agent")
    _status(config.deploy_platform != "none", "infra-worker agent")
    print()

    skills = ["preflight", "orchestrate", "spec", "status", "worker-protocol", "bold-design"]
    if config.backend_framework != "none":
        skills.append("backend-test")
    if config.frontend_framework != "none":
        skills.append("verify-ui")
    if config.deploy_platform != "none":
        skills.append("deploy")
    print(f"    Skills: {', '.join(skills)}")
    print()

    confirm = input("  Proceed with setup? [Y/n]: ").strip().lower()
    if confirm in ("n", "no"):
        print("  Aborted.")
        sys.exit(0)

    setup_project(config, target, factory_dir)


if __name__ == "__main__":
    main()
