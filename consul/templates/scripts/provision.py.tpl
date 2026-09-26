#!/usr/bin/env python3
"""
provision.py — apply render.yaml to Render through the API (installed by
consul onboarding into .claude/scripts/; rendered for {{PROJECT_NAME}}).

This is Consul's own blueprint applier. Render's "Blueprint Instance"
does the same job but can only be created by clicking in the Dashboard;
this script does it from the terminal so that clone → wizard → live services
needs no Dashboard visit beyond account setup.

    python3 .claude/scripts/provision.py            # plan, confirm, apply
    python3 .claude/scripts/provision.py --dry-run  # plan only, no API writes
    python3 .claude/scripts/provision.py --yes      # apply without confirming
    python3 .claude/scripts/provision.py --set CLERK_SECRET_KEY=sk_...   # supply a secret
    python3 .claude/scripts/provision.py --destroy  # delete this project's services + databases (asks you to type the slug)

Idempotent: every resource is looked up by name in the pinned workspace and
created only if missing. It never deletes anything and never overwrites an
env var that already has a value, except the cross-service URL keys
(API_URL, NEXT_PUBLIC_API_URL, FRONTEND_URL, CORS_ORIGINS), which are
derived from Render's assigned URLs and always re-applied.

Order of operations:
  1. env groups referenced by fromGroup — created empty if missing
  2. databases — created (plan/region/version from render.yaml), waited on
     until `available`, external access opened (--allow-ip none to skip)
  3. services — created from the GitHub remote + current branch, with plain
     env vars, DATABASE_URL (fromDatabase), and any sync:false secrets that
     were supplied (--set, or the env block of .claude/settings.local.json)
  4. env groups linked to their services
  5. cross-service URLs set from the real *.onrender.com hostnames
  6. backend/.env written with the EXTERNAL DATABASE_URL (gitignored) so
     backend tests run against the real database from this machine
  7. .claude/render-services.json written (ids + urls, no secrets)

Standard library only. Exit 1 on any failure.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[2])
os.chdir(ROOT)
sys.path.insert(0, str(ROOT / ".claude" / "scripts"))
import render_yaml  # noqa: E402

API = "https://api.render.com/v1"
URL_KEYS_BACKEND_TARGET = ("API_URL", "NEXT_PUBLIC_API_URL", "BACKEND_URL")
URL_KEYS_FRONTEND_TARGET = ("FRONTEND_URL", "CORS_ORIGINS")
DB_WAIT_SECONDS = 420


def say(msg):
    print(msg, flush=True)


def die(msg, fix=""):
    say(f"\n[FAIL] {msg}")
    if fix:
        say(f"       → {fix}")
    sys.exit(1)


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return p.returncode, (p.stdout + p.stderr).strip()
    except Exception as e:  # noqa: BLE001
        return 1, str(e)


# ── Render API ───────────────────────────────────────────────────

class Render:
    def __init__(self, key, dry_run=False):
        self.key = key
        self.dry_run = dry_run

    def call(self, method, path, body=None):
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(f"{API}{path}", data=data, method=method, headers={
            "Authorization": f"Bearer {self.key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read().decode("utf-8")
                return r.status, (json.loads(raw) if raw.strip() else {})
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", "replace")
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, {"message": raw}
        except Exception as e:  # noqa: BLE001
            return 0, {"message": str(e)}

    def get(self, path):
        return self.call("GET", path)

    def write(self, method, path, body=None):
        if self.dry_run:
            say(f"       (dry-run) {method} {path} {json.dumps(_redact(body))[:160] if body else ''}")
            return 200, {}
        return self.call(method, path, body)

    def list_all(self, path, wrapper):
        """Follow cursors; unwrap {wrapper: {...}} items."""
        items, cursor = [], None
        for _ in range(20):
            sep = "&" if "?" in path else "?"
            status, page = self.get(path + (f"{sep}cursor={cursor}" if cursor else ""))
            if status != 200 or not isinstance(page, list):
                return status, items
            items.extend(i.get(wrapper, {}) for i in page)
            if len(page) < 100:
                break
            cursor = page[-1].get("cursor")
            if not cursor:
                break
        return 200, items


def _redact(body):
    if not isinstance(body, dict):
        return body
    out = dict(body)
    if "envVars" in out:
        out["envVars"] = [{"key": v.get("key"), "value": "***"} if "value" in v else v for v in out["envVars"]]
    if "value" in out:
        out["value"] = "***"
    return out


# ── inputs ───────────────────────────────────────────────────────

def resolve_key():
    helper = ROOT / ".claude" / "scripts" / "render-api-key.sh"
    if not helper.exists():
        die("missing .claude/scripts/render-api-key.sh — re-run onboarding")
    code, key = run(["bash", str(helper)])
    _, source = run(["bash", str(helper), "--source"])
    if code != 0 or not key.strip():
        die("no Render credential found",
            "Create an API key (Render Dashboard → Account Settings → API Keys) and add it to the env block of "
            ".claude/settings.local.json, or run `render login`.")
    if source.strip() == "cli-token-EXPIRED":
        die("the only Render credential is an expired `render login` token",
            "Run `render login`, or add a long-lived API key to .claude/settings.local.json (durable).")
    return key.strip(), source.strip()


def read_pins():
    pin = ROOT / ".claude" / "render-workspace"
    if not pin.exists():
        return []
    return [l.strip() for l in pin.read_text(encoding="utf-8").splitlines() if l.strip()]


def resolve_owner(rnd, explicit):
    status, owners = rnd.list_all("/owners?limit=100", "owner")
    if status == 401:
        die("Render rejected the credential (401)", "Create a new API key or run `render login`.")
    if status != 200:
        die(f"could not list workspaces (HTTP {status})")
    pins = [explicit] if explicit else read_pins()
    if not pins:
        if len(owners) == 1:
            return owners[0]
        die("project is not pinned to a workspace and the credential sees several",
            "Write the workspace name and tea-... ID to .claude/render-workspace (one per line), or pass --owner tea-...")
    for o in owners:
        if o.get("id") in pins or (o.get("name") or "").strip() in pins:
            return o
    die(f"pinned workspace {pins} is not visible to this credential",
        "Use a key from a user with access to the pinned workspace, or fix .claude/render-workspace.")


def resolve_repo(cli_branch):
    code, url = run(["git", "remote", "get-url", "origin"])
    if code != 0 or not url:
        die("no git remote named origin — Render deploys from GitHub",
            "gh repo create <slug> --private --source=. --remote=origin --push")
    url = url.strip()
    m = re.match(r"^git@github\.com:(.+?)(\.git)?$", url)
    if m:
        url = f"https://github.com/{m.group(1)}"
    url = re.sub(r"\.git$", "", url)
    if cli_branch:
        branch = cli_branch
    else:
        code, branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"])
        branch = branch.strip() if code == 0 else "main"
    code, status = run(["git", "status", "-sb"])
    head = status.splitlines()[0] if status else ""
    pushed = "..." in head and "ahead" not in head
    return url, branch, pushed


def supplied_secrets(cli_sets):
    """Secrets for sync:false keys: --set KEY=VALUE, then the env block of
    .claude/settings.local.json (where the wizard stores Clerk keys)."""
    out = {}
    local = ROOT / ".claude" / "settings.local.json"
    if local.exists():
        try:
            out.update({k: v for k, v in (json.loads(local.read_text(encoding="utf-8")).get("env") or {}).items() if v})
        except ValueError:
            pass
    for item in cli_sets or []:
        if "=" in item:
            k, v = item.split("=", 1)
            out[k.strip()] = v
    out.pop("RENDER_API_KEY", None)
    return out


# ── steps ────────────────────────────────────────────────────────

def ensure_env_groups(rnd, owner_id, names):
    if not names:
        return {}
    status, groups = rnd.list_all(f"/env-groups?ownerId={owner_id}&limit=100", "envGroup")
    by_name = {g.get("name"): g for g in groups}
    out = {}
    for name in names:
        if name in by_name:
            say(f"[ok  ] env group '{name}' exists ({by_name[name].get('id')})")
            out[name] = by_name[name].get("id")
            continue
        say(f"[new ] env group '{name}' — creating (empty; add shared keys in the Dashboard later)")
        status, created = rnd.write("POST", "/env-groups", {"name": name, "ownerId": owner_id, "envVars": []})
        if status not in (200, 201):
            die(f"could not create env group '{name}' (HTTP {status}): {created.get('message', '')}")
        out[name] = created.get("id", "dry-run")
    return out


def ensure_databases(rnd, owner_id, dbs, allow_ip):
    if not dbs:
        return {}
    status, live = rnd.list_all(f"/postgres?ownerId={owner_id}&limit=100", "postgres")
    by_name = {d.get("name"): d for d in live}
    out = {}
    for db in dbs:
        name = db["name"]
        if name in by_name:
            say(f"[ok  ] database '{name}' exists ({by_name[name].get('id')}, {by_name[name].get('status')})")
            out[name] = by_name[name]
            continue
        body = {
            "name": name,
            "ownerId": owner_id,
            "plan": render_yaml.api_plan(db.get("plan") or "basic_256mb"),
            "region": db.get("region") or "oregon",
            "version": str(db.get("postgresMajorVersion") or "16"),
        }
        if allow_ip and allow_ip != "none":
            cidr = "0.0.0.0/0" if allow_ip == "all" else allow_ip
            body["ipAllowList"] = [{"cidrBlock": cidr, "description": "consul: local backend tests"}]
        say(f"[new ] database '{name}' — creating ({body['plan']}, {body['region']}, PG{body['version']}) — this starts billing")
        status, created = rnd.write("POST", "/postgres", body)
        if status not in (200, 201):
            die(f"could not create database '{name}' (HTTP {status}): {created.get('message', '')}",
                "A 402/403 here usually means the workspace has no payment method: Render Dashboard → Billing.")
        out[name] = created if created else {"id": "dry-run", "status": "available", "name": name}
    return out


def wait_for_databases(rnd, dbs):
    for name, db in dbs.items():
        if db.get("id") == "dry-run":
            continue
        deadline = time.time() + DB_WAIT_SECONDS
        while db.get("status") != "available":
            if time.time() > deadline:
                die(f"database '{name}' still '{db.get('status')}' after {DB_WAIT_SECONDS}s", "Check the Render Dashboard, then re-run.")
            say(f"       waiting for database '{name}' ({db.get('status')})…")
            time.sleep(15)
            status, db = rnd.get(f"/postgres/{db['id']}")
            if status != 200:
                die(f"could not poll database '{name}' (HTTP {status})")
        dbs[name] = db


def connection_strings(rnd, db):
    if db.get("id") == "dry-run":
        return "postgres://dry-run-internal", "postgres://dry-run-external"
    status, info = rnd.get(f"/postgres/{db['id']}/connection-info")
    if status != 200:
        die(f"could not read connection info for database '{db.get('name')}' (HTTP {status})")
    return info.get("internalConnectionString", ""), info.get("externalConnectionString", "")


def build_env_vars(svc, dbs, conn_cache, secrets, rnd):
    """Env vars to send at creation: plain values, DATABASE_URL, supplied secrets."""
    out, skipped = [], []
    for v in svc["envVars"]:
        if "fromGroup" in v:
            continue
        key = v["key"]
        if v.get("fromDatabase"):
            db = dbs.get(v["fromDatabase"].get("name"))
            if not db:
                die(f"'{svc['name']}' references database '{v['fromDatabase'].get('name')}' which is not declared or not created")
            if db["name"] not in conn_cache:
                conn_cache[db["name"]] = connection_strings(rnd, db)
            out.append({"key": key, "value": conn_cache[db["name"]][0]})
        elif v.get("generateValue"):
            out.append({"key": key, "generateValue": True})
        elif v.get("value") is not None and v["sync"]:
            out.append({"key": key, "value": v["value"]})
        elif not v["sync"]:
            if key in secrets:
                out.append({"key": key, "value": secrets[key]})
            elif key in URL_KEYS_BACKEND_TARGET + URL_KEYS_FRONTEND_TARGET:
                pass  # set in the URL pass
            else:
                skipped.append(key)
    return out, skipped


def ensure_services(rnd, owner_id, services, repo, branch, dbs, secrets):
    status, live = rnd.list_all(f"/services?ownerId={owner_id}&limit=100", "service")
    by_name = {s.get("name"): s for s in live}
    out, conn_cache, pending_secrets = {}, {}, {}
    for svc in services:
        name = svc["name"]
        env_vars, skipped = build_env_vars(svc, dbs, conn_cache, secrets, rnd)
        if skipped:
            pending_secrets[name] = skipped
        if name in by_name:
            say(f"[ok  ] service '{name}' exists ({by_name[name].get('id')})")
            out[name] = by_name[name]
            ensure_existing_env(rnd, by_name[name], env_vars)
            continue
        runtime = svc.get("runtime") or ("python" if svc.get("startCommand", "").startswith(("uvicorn", "gunicorn", "python")) else "node")
        body = {
            "type": "web_service" if svc.get("type", "web") == "web" else svc["type"],
            "name": name,
            "ownerId": owner_id,
            "repo": repo,
            "branch": branch,
            "autoDeploy": "yes",
            "envVars": env_vars,
            "serviceDetails": {
                "runtime": runtime,
                "plan": render_yaml.api_plan(svc.get("plan") or "starter"),
                "region": svc.get("region") or "oregon",
                "numInstances": 1,
                "envSpecificDetails": {
                    "buildCommand": svc.get("buildCommand", ""),
                    "startCommand": svc.get("startCommand", ""),
                },
            },
        }
        if svc.get("rootDir"):
            body["rootDir"] = svc["rootDir"]
        if svc.get("healthCheckPath"):
            body["serviceDetails"]["healthCheckPath"] = svc["healthCheckPath"]
        say(f"[new ] service '{name}' — creating ({runtime}, {body['serviceDetails']['plan']}, rootDir={svc.get('rootDir') or '/'}) — this starts billing")
        status, created = rnd.write("POST", "/services", body)
        if status not in (200, 201):
            msg = created.get("message", "") if isinstance(created, dict) else str(created)
            fix = "Render cannot read the repo: connect GitHub in Render (Dashboard → Account Settings → GitHub) and grant access to this repository, then re-run." \
                if re.search(r"repo|github|permission|access", msg, re.I) else \
                "A 402/403 usually means no payment method (Dashboard → Billing). Otherwise check the message above."
            die(f"could not create service '{name}' (HTTP {status}): {msg}", fix)
        out[name] = created.get("service", {"id": "dry-run", "name": name, "serviceDetails": {"url": f"https://{name}.onrender.com"}}) if created else \
            {"id": "dry-run", "name": name, "serviceDetails": {"url": f"https://{name}.onrender.com"}}
    return out, pending_secrets, conn_cache


def ensure_existing_env(rnd, live_svc, env_vars):
    """For a pre-existing service: fill env vars that are missing or empty. Never overwrite a set value."""
    if live_svc.get("id") == "dry-run":
        return
    status, current = rnd.list_all(f"/services/{live_svc['id']}/env-vars?limit=100", "envVar")
    present = {v.get("key"): v.get("value", "") for v in current} if status == 200 else {}
    for v in env_vars:
        if "value" in v and not present.get(v["key"]):
            rnd.write("PUT", f"/services/{live_svc['id']}/env-vars/{v['key']}", {"value": v["value"]})
            say(f"       set {v['key']} on '{live_svc.get('name')}'")


def link_env_groups(rnd, services_spec, live_services, group_ids):
    for svc in services_spec:
        for g in svc["fromGroups"]:
            gid, sid = group_ids.get(g), live_services.get(svc["name"], {}).get("id")
            if not gid or not sid or "dry-run" in (gid, sid):
                continue
            status, _ = rnd.write("POST", f"/env-groups/{gid}/services/{sid}")
            say(f"[ok  ] env group '{g}' linked to '{svc['name']}'" if status in (200, 201, 204, 409)
                else f"[warn] could not link env group '{g}' to '{svc['name']}' (HTTP {status})")


def set_cross_service_urls(rnd, services_spec, live_services):
    urls = {}
    for svc in services_spec:
        live = live_services.get(svc["name"])
        if live:
            urls[render_yaml.role_of(svc)] = (live.get("serviceDetails") or {}).get("url", "")
    for svc in services_spec:
        live = live_services.get(svc["name"])
        if not live:
            continue
        for v in svc["envVars"]:
            key = v.get("key")
            target = urls.get("backend") if key in URL_KEYS_BACKEND_TARGET else urls.get("frontend") if key in URL_KEYS_FRONTEND_TARGET else None
            if key and target:
                if live.get("id") != "dry-run":
                    rnd.write("PUT", f"/services/{live['id']}/env-vars/{key}", {"value": target})
                say(f"[ok  ] {svc['name']}.{key} = {target}")
    return urls


def write_backend_env(dbs, conn_cache, rnd):
    backend = ROOT / "backend"
    if not backend.is_dir() or not dbs:
        return
    env_path = backend / ".env"
    if env_path.exists() and "DATABASE_URL=" in env_path.read_text(encoding="utf-8"):
        say("[ok  ] backend/.env already has DATABASE_URL")
        return
    code, _ = run(["git", "check-ignore", "-q", str(env_path)])
    if code != 0:
        say("[warn] backend/.env is NOT gitignored — not writing credentials into it")
        return
    name, db = next(iter(dbs.items()))
    if name not in conn_cache:
        conn_cache[name] = connection_strings(rnd, db)
    external = conn_cache[name][1]
    if rnd.dry_run:
        say("       (dry-run) would write backend/.env with the external DATABASE_URL")
        return
    with open(env_path, "a", encoding="utf-8") as f:
        f.write(f"\n# written by provision.py — external connection for local tests\nDATABASE_URL={external}\n")
    say("[ok  ] backend/.env written with the external DATABASE_URL (gitignored)")


def write_state(live_services, dbs, urls, owner):
    state = {
        "workspace": {"id": owner.get("id"), "name": (owner.get("name") or "").strip()},
        "services": {n: {"id": s.get("id"), "url": (s.get("serviceDetails") or {}).get("url", ""),
                         "dashboard": s.get("dashboardUrl", "")} for n, s in live_services.items()},
        "databases": {n: {"id": d.get("id"), "status": d.get("status", ""), "dashboard": d.get("dashboardUrl", "")} for n, d in dbs.items()},
        "urls": urls,
        "provisionedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    (ROOT / ".claude" / "render-services.json").write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    say("[ok  ] .claude/render-services.json written (ids + urls; no secrets)")


# ── destroy ──────────────────────────────────────────────────────

def destroy(rnd, owner, spec, confirmed):
    """Delete every service and database render.yaml declares, by name, in the
    pinned workspace. Env groups are left alone (they may be shared). Billing
    stops when the resources are gone."""
    slug = "{{PROJECT_SLUG}}"
    q = f"?ownerId={owner['id']}&limit=100"
    _, live_services = rnd.list_all(f"/services{q}", "service")
    _, live_dbs = rnd.list_all(f"/postgres{q}", "postgres")
    targets = [("service", s) for s in live_services if s.get("name") in {x["name"] for x in spec["services"]}]
    targets += [("postgres", d) for d in live_dbs if d.get("name") in {x["name"] for x in spec["databases"]}]
    if not targets:
        say("   nothing to delete — no declared service or database exists in the workspace")
        return
    say("   will DELETE (irreversible; data in the database is lost):")
    for kind, r in targets:
        say(f"     {kind:8s} {r.get('name')}  ({r.get('id')})")
    if not confirmed:
        typed = input(f"\n   Type the project slug '{slug}' to confirm: ").strip()
        if typed != slug:
            say("   Aborted — nothing deleted.")
            sys.exit(0)
    for kind, r in targets:
        status, body = rnd.write("DELETE", f"/{'services' if kind == 'service' else 'postgres'}/{r['id']}")
        if status in (200, 202, 204):
            say(f"[gone] {kind} '{r.get('name')}'")
        else:
            say(f"[FAIL] could not delete {kind} '{r.get('name')}' (HTTP {status}): {body.get('message', '') if isinstance(body, dict) else body}")
    state = ROOT / ".claude" / "render-services.json"
    if state.exists() and not rnd.dry_run:
        state.unlink()
        say("[ok  ] .claude/render-services.json removed")
    say("\n== destroyed == (env groups untouched; backend/.env left in place — its DATABASE_URL is now dead)")


# ── main ─────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="Apply render.yaml to Render via the API (idempotent).")
    ap.add_argument("--dry-run", action="store_true", help="plan only; no API writes")
    ap.add_argument("--yes", "-y", action="store_true", help="apply without confirming")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE", help="value for a sync:false env var")
    ap.add_argument("--owner", default="", help="workspace tea-... ID (default: .claude/render-workspace)")
    ap.add_argument("--branch", default="", help="branch to deploy (default: current)")
    ap.add_argument("--allow-ip", default="all", help="database external access: all | <cidr> | none (default all)")
    ap.add_argument("--destroy", action="store_true", help="delete this project's declared services and databases")
    args = ap.parse_args()

    say(f"== consul provision: {{PROJECT_NAME}} ==")
    spec = render_yaml.load(ROOT)
    if spec is None:
        die("render.yaml not found at repo root")
    if not spec["services"] and not spec["databases"]:
        die("render.yaml declares no services or databases")

    key, source = resolve_key()
    rnd = Render(key, dry_run=args.dry_run)
    owner = resolve_owner(rnd, args.owner)
    say(f"   workspace : '{(owner.get('name') or '').strip()}' ({owner.get('id')})  [credential: {source}]")

    if args.destroy:
        destroy(rnd, owner, spec, confirmed=args.yes)
        return

    repo, branch, pushed = resolve_repo(args.branch)
    secrets = supplied_secrets(args.set)

    say(f"   repo      : {repo} @ {branch}" + ("" if pushed else "   (WARN: branch not pushed — Render will build whatever is on GitHub)"))
    say(f"   plan      : {len(spec['databases'])} database(s), {len(spec['services'])} service(s), "
        f"{len({g for s in spec['services'] for g in s['fromGroups']})} env group(s)")
    if secrets:
        say(f"   secrets   : will set {', '.join(sorted(secrets))} where render.yaml declares them sync:false")
    if not args.yes and not args.dry_run:
        if input("\n   Create anything missing on Render now? Paid plans start billing immediately. [y/N]: ").strip().lower() not in ("y", "yes"):
            say("   Aborted. Re-run with --dry-run to see the plan.")
            sys.exit(0)
    say("")

    groups = ensure_env_groups(rnd, owner["id"], sorted({g for s in spec["services"] for g in s["fromGroups"]}))
    dbs = ensure_databases(rnd, owner["id"], spec["databases"], args.allow_ip)
    if not args.dry_run:
        wait_for_databases(rnd, dbs)
    live_services, pending, conn_cache = ensure_services(rnd, owner["id"], spec["services"], repo, branch, dbs, secrets)
    link_env_groups(rnd, spec["services"], live_services, groups)
    urls = set_cross_service_urls(rnd, spec["services"], live_services)
    write_backend_env(dbs, conn_cache, rnd)
    if not args.dry_run:
        write_state(live_services, dbs, urls, owner)

    say("")
    if pending:
        say("[todo] secrets still unset (declared sync:false, no value supplied):")
        for svc, keys in pending.items():
            say(f"       {svc}: {', '.join(keys)}")
        say("       → re-run with --set KEY=VALUE, or set them in Render Dashboard → the service → Environment")
    say("\n== done ==" if not args.dry_run else "\n== dry run complete — nothing was created ==")
    if urls and not args.dry_run:
        for role, url in urls.items():
            say(f"   {role:8s} {url}")
        say("   First deploys are building now. Check: python3 .claude/scripts/preflight.py")


if __name__ == "__main__":
    main()
