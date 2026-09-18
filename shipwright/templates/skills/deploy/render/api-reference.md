# Render API Reference

**Base URL:** `https://api.render.com/v1/`
**Auth:** `Authorization: Bearer <api_key>`
**Pagination:** Cursor-based. Params: `limit` (default 20, max 100), `cursor` (from previous response).

```bash
# Resolve the API key (long-lived key from settings.local.json / .env / env,
# falling back to the `render login` token — see SKILL.md "Authentication")
export RENDER_API_KEY=$(.claude/scripts/render-api-key.sh)

# Usage pattern
curl -s -H "Authorization: Bearer $RENDER_API_KEY" \
  -H "Content-Type: application/json" \
  https://api.render.com/v1/<endpoint>
```

---

## Services

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/services` | List all services |
| POST | `/services` | Create service |
| GET | `/services/{id}` | Get service details |
| PATCH | `/services/{id}` | Update service |
| DELETE | `/services/{id}` | Delete service |
| POST | `/services/{id}/suspend` | Suspend service |
| POST | `/services/{id}/resume` | Resume service |
| POST | `/services/{id}/restart` | Restart service |
| POST | `/services/{id}/scale` | Adjust instance count |
| PUT | `/services/{id}/autoscaling` | Configure autoscaling |
| DELETE | `/services/{id}/autoscaling` | Remove autoscaling |
| GET | `/services/{id}/instances` | List instances |

### Create a web service
```bash
curl -s -X POST -H "Authorization: Bearer $RENDER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "web_service",
    "name": "my-api",
    "repo": "https://github.com/user/repo",
    "branch": "main",
    "plan": "starter",
    "region": "oregon",
    "runtime": "node",
    "buildCommand": "npm install",
    "startCommand": "npm start",
    "envVars": [{"key": "NODE_ENV", "value": "production"}]
  }' \
  https://api.render.com/v1/services
```

---

## Deploys

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/services/{id}/deploys` | List deploys |
| POST | `/services/{id}/deploys` | Trigger deploy |
| GET | `/services/{id}/deploys/{deployId}` | Deploy details |
| POST | `/services/{id}/deploys/{deployId}/cancel` | Cancel deploy |
| POST | `/services/{id}/deploys/{deployId}/rollback` | Rollback to this deploy |

---

## Environment Variables

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/services/{id}/env-vars` | List env vars |
| PUT | `/services/{id}/env-vars` | Bulk update env vars |
| GET | `/services/{id}/env-vars/{key}` | Get single var |
| PUT | `/services/{id}/env-vars/{key}` | Set single var |
| DELETE | `/services/{id}/env-vars/{key}` | Delete var |

### Bulk update example
```bash
curl -s -X PUT -H "Authorization: Bearer $RENDER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '[
    {"key": "DATABASE_URL", "value": "postgres://..."},
    {"key": "REDIS_URL", "value": "redis://..."}
  ]' \
  https://api.render.com/v1/services/<SERVICE_ID>/env-vars
```

---

## Environment Groups

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/env-groups` | List env groups |
| POST | `/env-groups` | Create env group |
| GET | `/env-groups/{id}` | Get group details |
| PATCH | `/env-groups/{id}` | Update group |
| DELETE | `/env-groups/{id}` | Delete group |
| POST | `/env-groups/{id}/services/{serviceId}` | Link to service |
| DELETE | `/env-groups/{id}/services/{serviceId}` | Unlink from service |
| GET/PUT/DELETE | `/env-groups/{id}/env-vars/{key}` | Per-variable CRUD |

---

## PostgreSQL

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/postgres` | List databases |
| POST | `/postgres` | Create database |
| GET | `/postgres/{id}` | Get details |
| PATCH | `/postgres/{id}` | Update |
| DELETE | `/postgres/{id}` | Delete |
| GET | `/postgres/{id}/connection-info` | Connection info |
| POST | `/postgres/{id}/suspend` | Suspend |
| POST | `/postgres/{id}/resume` | Resume |
| POST | `/postgres/{id}/restart` | Restart |
| POST | `/postgres/{id}/failover` | Trigger failover |
| GET | `/postgres/{id}/recovery/status` | PITR status |
| POST | `/postgres/{id}/recover` | Point-in-time recovery |
| GET/POST | `/postgres/{id}/users` | Manage users |

---

## Key Value (Redis)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/key-value` | List instances |
| POST | `/key-value` | Create |
| GET | `/key-value/{id}` | Details |
| GET | `/key-value/{id}/connection-info` | Connection info |
| PATCH | `/key-value/{id}` | Update |
| DELETE | `/key-value/{id}` | Delete |
| POST | `/key-value/{id}/suspend` | Suspend |
| POST | `/key-value/{id}/resume` | Resume |

---

## Custom Domains

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/services/{id}/custom-domains` | List domains |
| POST | `/services/{id}/custom-domains` | Add domain |
| DELETE | `/services/{id}/custom-domains/{domainId}` | Remove |
| POST | `/services/{id}/custom-domains/{domainId}/verify` | Verify DNS |

---

## Disks

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/services/{id}/disks` | List disks |
| POST | `/services/{id}/disks` | Add disk |
| PATCH | `/disks/{id}` | Update disk |
| DELETE | `/disks/{id}` | Delete disk |
| GET | `/disks/{id}/snapshots` | List snapshots |
| POST | `/disks/{id}/snapshots/{snapshotId}/restore` | Restore snapshot |

---

## Logs & Metrics

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/services/{id}/logs` | Query logs |
| GET | `/services/{id}/logs/subscribe` | SSE log stream |
| GET | `/services/{id}/metrics/{type}` | Get metrics |

Metric types: `cpu`, `memory`, `http-requests`, `http-latency`, `bandwidth`, `disk-usage`, `active-connections`, `replica-lag`, `instance-count`

---

## Projects & Environments

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET/POST | `/projects` | List/create projects |
| GET/PATCH/DELETE | `/projects/{id}` | Project CRUD |
| GET/POST | `/projects/{id}/environments` | List/create environments |
| GET/PATCH/DELETE | `/projects/{id}/environments/{envId}` | Environment CRUD |
| POST | `/projects/{id}/environments/{envId}/resources` | Add resources |
| DELETE | `/projects/{id}/environments/{envId}/resources` | Remove resources |

---

## Blueprints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/blueprints` | List blueprints |
| POST | `/blueprints/validate` | Validate render.yaml |
| GET | `/blueprints/{id}` | Get details |
| PATCH | `/blueprints/{id}` | Update |
| DELETE | `/blueprints/{id}` | Disconnect |
| GET | `/blueprints/{id}/syncs` | List syncs |

---

## Owners (Workspaces)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/owners` | List all workspaces |

---

## Other Endpoints

- **Secret files:** `GET/PUT/DELETE /services/{id}/secret-files/{name}`
- **Registry credentials:** CRUD at `/registry-credentials`
- **Webhooks:** CRUD at `/webhooks`
- **One-off jobs:** `GET/POST /services/{id}/jobs`, `POST /services/{id}/jobs/{jobId}/cancel`
- **Audit logs:** `GET /audit-log` (workspace), `GET /organizations/{id}/audit-log`
- **Notification settings:** `GET/PUT /notification-settings`
