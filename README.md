# Acme Platform — DevOps Assessment Starter

This repository is the hands-on portion (Part B) of the DevOps / Platform Engineer technical assessment.

## Setup

1. Clone this repository
2. Create branch: `assessment/<your-name>`
3. Read the assessment PDF provided by the hiring team
4. Complete Part A in `docs/architecture-proposal.md` (or PDF)
5. Complete Part B fixes in this repository
6. Grant repository access to reviewers when done

## Structure

- `terraform/` — infrastructure module (needs hardening)
- `charts/billing-service/` — Helm chart (needs hardening)
- `.github/workflows/` — create `deploy.yml`
- `scripts/` — create `provision-cell.sh`
- `SECURITY.md` — create this file

## Local smoke test (optional)

```bash
docker build -t billing-service:local .
docker run --rm -p 3000:3000 billing-service:local
curl http://localhost:3000/health
```

Do not commit secrets. Do not use real company or customer names.
