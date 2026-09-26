"""
render_yaml.py — minimal reader for the project's render.yaml (installed by
consul onboarding into .claude/scripts/; shared by preflight.py and
provision.py).

Not a YAML parser. It understands the shape onboarding generates plus
ordinary hand edits: top-level `services:` / `databases:` / `envVarGroups:`
lists, scalar fields on each item, and `envVars:` entries of the forms

    - key: X
      value: "..."
    - key: X
      sync: false
    - key: X
      fromDatabase:
        name: my-db
        property: connectionString
    - key: X
      generateValue: true
    - fromGroup: my-group

Anything it does not recognise is ignored rather than raising, so a richer
blueprint still parses down to what Consul needs.
"""

import re
from pathlib import Path


def _val(s):
    v = s.split(":", 1)[1].strip() if ":" in s else ""
    v = v.split(" #", 1)[0].strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v


def _key(s):
    return s.lstrip("- ").split(":", 1)[0].strip()


def parse(text):
    services, databases, groups = [], [], []
    section = None
    current = None
    in_envvars = False
    cur_var = None
    in_from_db = False

    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        s = raw.strip()

        if indent == 0:
            section = s[:-1] if s.endswith(":") else None
            current = None
            in_envvars = False
            continue

        if section == "services":
            if s.startswith("- ") and indent == 2:
                current = {"envVars": [], "type": "", "name": "", "runtime": "", "rootDir": "",
                           "plan": "starter", "region": "oregon", "buildCommand": "", "startCommand": "",
                           "healthCheckPath": "", "branch": ""}
                services.append(current)
                in_envvars = False
                cur_var = None
                current[_key(s)] = _val(s)
                continue
            if current is None:
                continue
            if indent == 4 and not s.startswith("-"):
                k = _key(s)
                in_envvars = (k == "envVars")
                if not in_envvars:
                    current[k] = _val(s)
                continue
            if in_envvars and indent >= 6:
                if s.startswith("- key:"):
                    cur_var = {"key": _val(s), "value": None, "sync": True, "fromDatabase": None, "generateValue": False}
                    current["envVars"].append(cur_var)
                    in_from_db = False
                elif s.startswith("- fromGroup:"):
                    current["envVars"].append({"fromGroup": _val(s)})
                    cur_var = None
                elif cur_var is not None:
                    k = _key(s)
                    if k == "value":
                        cur_var["value"] = _val(s)
                    elif k == "sync":
                        cur_var["sync"] = _val(s).lower() != "false"
                    elif k == "fromDatabase":
                        cur_var["fromDatabase"] = {}
                        in_from_db = True
                    elif in_from_db and k in ("name", "property"):
                        cur_var["fromDatabase"][k] = _val(s)
                    elif k == "generateValue":
                        cur_var["generateValue"] = _val(s).lower() == "true"
        elif section == "databases":
            if s.startswith("- ") and indent == 2:
                current = {"name": "", "plan": "basic_256mb", "region": "oregon", "postgresMajorVersion": "16"}
                databases.append(current)
                current[_key(s)] = _val(s)
            elif current is not None and indent == 4:
                current[_key(s)] = _val(s)
        elif section == "envVarGroups":
            if s.startswith("- ") and indent == 2:
                current = {"name": ""}
                groups.append(current)
                current[_key(s)] = _val(s)
            elif current is not None and indent == 4 and not s.startswith("-"):
                current[_key(s)] = _val(s)

    for svc in services:
        svc["sync_false"] = [v["key"] for v in svc["envVars"] if "key" in v and not v["sync"]]
        svc["fromGroups"] = [v["fromGroup"] for v in svc["envVars"] if "fromGroup" in v]
    return {"services": services, "databases": databases, "envVarGroups": groups}


def load(root):
    path = Path(root) / "render.yaml"
    if not path.exists():
        return None
    return parse(path.read_text(encoding="utf-8"))


def api_plan(plan):
    """Blueprint plan names use dashes (basic-256mb); the API uses underscores."""
    return re.sub(r"-", "_", plan or "")


def role_of(svc):
    """backend | frontend | other — from rootDir first, then the name suffix."""
    rd = (svc.get("rootDir") or "").strip("/").lower()
    name = (svc.get("name") or "").lower()
    if rd == "backend" or name.endswith("-api") or name.endswith("-backend"):
        return "backend"
    if rd == "frontend" or name.endswith("-frontend") or name.endswith("-web"):
        return "frontend"
    return "other"
