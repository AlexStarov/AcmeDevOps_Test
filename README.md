# Acme Platform — DevOps Assessment Starter

This repository is the hands-on portion (Part B) of the DevOps / Platform Engineer technical assessment.

## Setup

1. Copy this repository to **your own GitHub account** (fork, duplicate, or push to a new private repo)
2. Read the assessment PDF provided by the hiring team
3. Complete Part A in `docs/architecture-proposal.md` (or PDF) in your repository
4. Complete Part B fixes in your repository
5. Share your repository URL with reviewers and grant them read access

Do not push branches or open pull requests in the starter repository provided by the hiring team.

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
