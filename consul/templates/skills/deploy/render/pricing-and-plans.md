# Render Pricing and Plans

## Workspace Tiers

| Tier | Cost | Key Features |
|------|------|-------------|
| Hobby | $0 | 1 project, 2 environments, no autoscaling, no SSH, no private networking |
| Professional | $19/user/mo | Unlimited projects/environments, autoscaling, preview environments, private networking |
| Organization | $29/user/mo | + SAML SSO, audit logs, org-level controls |
| Enterprise | Custom | + dedicated support, SLAs |

---

## Service Plans

| Plan | CPU | RAM | Cost/mo |
|------|-----|-----|---------|
| Free | 0.1 | 512 MB | $0 |
| Starter | 0.5 | 512 MB | $7 |
| Standard | 1 | 2 GB | $25 |
| Pro | 2 | 4 GB | $85 |
| Pro Plus | 4 | 8 GB | $175 |
| Pro Max | 4 | 16 GB | $225 |
| Pro Ultra | 8 | 32 GB | $450 |

Applies to: Web Services, Private Services, Background Workers.

---

## PostgreSQL Plans

| Plan | RAM | Storage | Cost/mo |
|------|-----|---------|---------|
| Free | Shared | 1 GB | $0 (30-day expiry) |
| Basic 256MB | 256 MB | 1 GB | $7 |
| Basic 1GB | 1 GB | 16 GB | $20 |
| Basic 4GB | 4 GB | 32 GB | $45 |
| Pro 4GB | 4 GB | 35 GB | $50 |
| Pro 8GB | 8 GB | 60 GB | $95 |
| Pro 16GB | 16 GB | 128 GB | $175 |
| Pro 32GB+ | 32-512 GB | 256 GB-3 TB | $350-$6,200 |

---

## Key Value (Redis) Plans

| Plan | Memory | Cost/mo |
|------|--------|---------|
| Free | 25 MB | $0 (in-memory only) |
| Starter | 256 MB | $10 |
| Standard | 1 GB | $30 |
| Pro 2GB | 2 GB | $60 |
| Pro 5GB | 5 GB | $130 |
| Pro 10GB | 10 GB | $260 |
| Pro 20GB | 20 GB | $550 |

---

## Cron Job Pricing

Billed per minute of execution time (minimum $1/month charge):

| Plan | $/min |
|------|-------|
| Starter | $0.00016 |
| Standard | $0.00056 |
| Pro | $0.00190 |
| Pro Ultra | $0.00405 |

---

## Free Tier Limitations

- 750 instance-hours/month shared across all free services
- Spin-down after 15 minutes idle (~1 min cold start on wake)
- Ephemeral filesystem (no persistent storage)
- No persistent disks
- No scaling (always 1 instance)
- No SSH access
- No private networking
- PostgreSQL: expires after 30 days, then deleted
- Key Value: in-memory only (no persistence)
- Outbound bandwidth: 100 GB/month

---

## Bandwidth

All paid plans include 100 GB/month outbound. Additional: $0.10/GB.
