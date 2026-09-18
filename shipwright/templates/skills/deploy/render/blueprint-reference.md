# render.yaml Blueprint Reference

JSON Schema available at: `https://render.com/schema/render.yaml.json` (IDE autocompletion via SchemaStore.org)

## Top-Level Structure

```yaml
previews:         # Preview environment configuration
services:         # List of services (web, pserv, worker, cron, keyvalue)
databases:        # List of PostgreSQL databases
envVarGroups:     # Shared environment variable groups
projects:         # Projects with named environments
```

---

## Service Fields (Common to All Types)

| Field | Required | Values | Notes |
|-------|----------|--------|-------|
| `name` | Yes | string | Unique per workspace. **Immutable after creation.** |
| `type` | Yes | `web`, `pserv`, `worker`, `cron`, `keyvalue` | **Immutable.** |
| `runtime` | Yes (except keyvalue) | `node`, `python`, `go`, `ruby`, `rust`, `elixir`, `docker`, `image`, `static` | **Immutable.** |
| `plan` | No | `free`, `starter`, `standard`, `pro`, `pro plus`, `pro max`, `pro ultra` | Default varies |
| `region` | No | `oregon`, `ohio`, `virginia`, `frankfurt`, `singapore` | **Immutable.** Default: `oregon` |
| `repo` | No | Git URL | Repository for this service |
| `branch` | No | string | Branch to deploy from |
| `buildCommand` | Yes (non-Docker) | shell command | Build step |
| `startCommand` | Yes (non-Docker) | shell command | Start step |
| `preDeployCommand` | No | shell command | Runs after build, before start |
| `numInstances` | No | integer | Default: 1 |
| `autoDeployTrigger` | No | `commit`, `checksPass`, `off` | When to auto-deploy |
| `healthCheckPath` | No | URL path | Web services only |
| `maxShutdownDelaySeconds` | No | 1-300 | Default: 30 |
| `domains` | No | list of strings | Custom domains |
| `rootDir` | No | string | Monorepo: subdirectory for this service |

### Immutable Fields (cannot change after creation)
`name`, `type`, `runtime`, `region`, `postgresMajorVersion`, `databaseName`, `user`

---

## Web Service Specific

```yaml
services:
  - type: web
    name: my-api
    runtime: node
    plan: starter
    region: oregon
    buildCommand: npm install
    startCommand: npm start
    healthCheckPath: /health
    domains:
      - api.example.com
    envVars:
      - key: NODE_ENV
        value: production
```

Gets a public `*.onrender.com` URL.

---

## Private Service

```yaml
  - type: pserv
    name: internal-api
    runtime: node
    buildCommand: npm install
    startCommand: npm start
```

No public URL. Accessible only via private network (same region). Use for internal microservices.

---

## Background Worker

```yaml
  - type: worker
    name: queue-processor
    runtime: node
    buildCommand: npm install
    startCommand: node worker.js
```

No inbound traffic at all. Use for queue consumers, async processors.

---

## Cron Job

```yaml
  - type: cron
    name: cleanup-job
    runtime: node
    buildCommand: npm install
    startCommand: node cleanup.js
    schedule: "0 */6 * * *"    # Every 6 hours, UTC
```

- `schedule` is required (cron expression, UTC)
- 12-hour maximum runtime
- At most one run active at a time
- Cannot use persistent disks
- Minimum $1/month charge

---

## Key Value (Redis)

```yaml
  - type: keyvalue
    name: cache
    plan: starter
    region: oregon
    maxmemoryPolicy: allkeys-lru
    ipAllowList:
      - source: 0.0.0.0/0
        description: everywhere
```

`ipAllowList` is required. `maxmemoryPolicy` options: `allkeys-lru`, `volatile-lru`, `allkeys-random`, `volatile-random`, `volatile-ttl`, `noeviction`.

---

## Static Site

```yaml
  - type: web
    runtime: static
    name: marketing-site
    buildCommand: npm run build
    staticPublishPath: ./dist
    headers:
      - path: /*
        name: X-Frame-Options
        value: sameorigin
    routes:
      - type: redirect
        source: /old
        destination: /new
      - type: rewrite
        source: /app/*
        destination: /index.html
```

Served from a global CDN with Brotli compression and HTTP/2.

---

## PostgreSQL Database

```yaml
databases:
  - name: mydb
    plan: starter
    region: oregon
    postgresMajorVersion: 16
    databaseName: mydb            # Auto-generated if omitted
    user: myuser                  # Auto-generated if omitted
    diskSizeGB: 35
    ipAllowList:
      - source: 0.0.0.0/0
        description: everywhere
    readReplicas:
      - name: replica-1          # Up to 5
    highAvailability:
      enabled: true               # Pro+ plan, v13+, Professional workspace
```

Database plans: `free`, `basic-256mb`, `basic-1gb`, `basic-4gb`, `pro-4gb`, `pro-8gb`, `pro-16gb`, `pro-32gb`, `pro-64gb`, `pro-128gb`, `pro-192gb`, `pro-256gb`, `pro-384gb`, `pro-512gb`, accelerated tiers up to `accelerated-1024gb`.

---

## Docker Deployment

```yaml
  - type: web
    name: my-app
    runtime: docker
    dockerfilePath: ./Dockerfile     # Default: ./Dockerfile
    dockerContext: .                  # Build context
    dockerCommand: node server.js    # Override CMD

# OR use a prebuilt image:
  - type: web
    name: my-app
    runtime: image
    image:
      url: docker.io/myorg/myapp:latest
      creds:
        fromRegistryCreds:
          name: dockerhub-creds
```

---

## Persistent Disk

```yaml
    disk:
      name: data
      mountPath: /data
      sizeGB: 10     # Cannot decrease after creation
```

Cannot be used with autoscaling or cron jobs.

---

## Autoscaling (Professional+ workspace)

```yaml
    scaling:
      minInstances: 1
      maxInstances: 3
      targetMemoryPercent: 60    # 1-90
      targetCPUPercent: 60       # 1-90
```

Cannot be used with persistent disks.

---

## Environment Variables

```yaml
    envVars:
      # Hardcoded value
      - key: API_URL
        value: https://api.example.com

      # Auto-generated secret (base64, 256-bit)
      - key: APP_SECRET
        generateValue: true

      # Prompt user in Dashboard (never stored in code)
      - key: STRIPE_KEY
        sync: false

      # From a database
      - key: DATABASE_URL
        fromDatabase:
          name: mydb
          property: connectionString    # also: user, password, database

      # From another service
      - key: CACHE_URL
        fromService:
          name: cache
          type: keyvalue
          property: connectionString    # also: host, port, hostport

      # Link an entire env group
      - fromGroup: shared-config
```

**Precedence:** Service-level vars always override group vars. Between multiple linked groups, precedence is not guaranteed.

---

## Environment Variable Groups

```yaml
envVarGroups:
  - name: shared-config
    envVars:
      - key: LOG_LEVEL
        value: info
      - key: JWT_SECRET
        generateValue: true
```

- Can be linked to unlimited services
- Cannot use `fromService` or `sync: false`
- Editing a group triggers redeploy of all linked services with autodeploy enabled

---

## Build Filters (Monorepo)

```yaml
    buildFilter:
      paths:
        - src/**/*.js
      ignoredPaths:
        - src/**/*.test.js
```

Only trigger builds when matching files change.

---

## Preview Environments (Professional+ workspace)

```yaml
previews:
  generation: automatic    # or: manual, off
  expireAfterDays: 30
```

Per-service overrides:
```yaml
    previews:
      generation: automatic
      plan: starter          # Smaller plan for previews
      numInstances: 1
```

- `automatic`: creates preview env on every PR
- `manual`: requires `[render preview]` in PR title
- Suppress with `[skip preview]` in PR title

---

## Projects and Environments

```yaml
projects:
  - name: my-project
    environments:
      - name: production
        services: [...]
        databases: [...]
        envVarGroups: [...]
        networking:
          isolation: enabled       # Block cross-environment private traffic
        permissions:
          protection: enabled      # Admin-only destructive actions
```

- Hobby workspace: 1 project, 2 environments max
- Professional+: unlimited
- Service names must be unique across the entire workspace

---

## Default Environment Variables (auto-provided by Render)

`RENDER`, `RENDER_SERVICE_ID`, `RENDER_SERVICE_NAME`, `RENDER_SERVICE_TYPE`, `RENDER_INSTANCE_ID`, `RENDER_EXTERNAL_HOSTNAME`, `RENDER_EXTERNAL_URL`, `RENDER_GIT_BRANCH`, `RENDER_GIT_COMMIT`, `RENDER_GIT_REPO_SLUG`, `RENDER_DISCOVERY_SERVICE`, `IS_PULL_REQUEST`, `NODE_ENV=production` (for Node.js)
