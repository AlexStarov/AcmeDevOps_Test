# Security Policy

## Overview
This document describes the security controls, identified risks, and operational runbooks for the Acme Platform. It is maintained to support our SOC 2 Type II audit programme and to provide transparency to enterprise customers.

---

## SOC 2 Controls Implemented

### CC6 — Logical and Physical Access Controls
The platform enforces strict logical access boundaries to ensure only authorized entities can access systems and data.

- **Human Access:** All engineer access to AWS environments is federated via an Identity Provider (Okta/Entra ID) through AWS IAM Identity Center. Credentials are temporary and scoped to the minimum required permissions (least-privilege IAM roles). No persistent IAM access keys are issued to humans.
- **Machine Access:** All microservices use IAM Roles for Service Accounts (IRSA), granting each workload a unique, narrowly scoped IAM role. Credentials are rotated automatically by the AWS STS service.
- **Break-Glass Access:** Emergency access to production environments requires a dual-approval workflow and is time-limited (1–2 hours). All session activity is recorded by AWS Systems Manager Session Manager and shipped to an immutable S3 audit bucket.

---

### CC7 — System Operations
The platform implements continuous monitoring, alerting, and incident response procedures to detect and respond to threats rapidly.

- **Threat Detection:** AWS GuardDuty is enabled in all accounts to automatically detect anomalous API calls, port scans, and compromised credential usage.
- **Centralised Logging:** All application logs (via Fluent Bit), AWS CloudTrail control-plane events, and VPC Flow Logs are shipped to a centralised, tamper-evident log aggregator (Amazon OpenSearch / Datadog) and retained for a minimum of 365 days.
- **Alerting:** Symptom-based alerts (HTTP 5xx error rate, latency P99, EC2/pod CPU anomalies) are routed to PagerDuty for on-call engineers. Severity thresholds are reviewed quarterly.

---

### CC8 — Change Management
All changes to production infrastructure and application code pass through a controlled, auditable delivery pipeline.

- **Code Review:** All pull requests require at least one peer reviewer approval before merging. Direct pushes to the `main` branch are protected.
- **CI/CD Pipeline:** The GitHub Actions `deploy.yml` workflow performs automated security checks (`npm audit`, Trivy container scanning) and fails the build on `CRITICAL` findings, preventing vulnerable artifacts from reaching production.
- **Infrastructure as Code:** All AWS resources are provisioned exclusively via Terraform (no manual console changes). ArgoCD enforces GitOps for Kubernetes workloads, and configuration drift from the desired state triggers an automated alert.

---

## Top 5 Identified Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **Privileged Access Abuse** — An engineer or compromised account performs destructive operations in production. | Medium | Critical | Break-glass approval workflow, time-limited roles, SSM Session Manager logging, real-time CloudTrail alerts to SIEM. |
| 2 | **Stale Dependency Vulnerabilities** — A critical CVE in an npm package or base Docker image exposes a running service. | High | High | `npm audit` in every CI run; Trivy blocks CRITICAL images from reaching ECR; weekly scheduled Trivy scans of production images; Dependabot PRs enabled. |
| 3 | **Accidental Public Data Exposure** — An S3 bucket or RDS instance is accidentally made publicly accessible. | Medium | Critical | `aws_s3_bucket_public_access_block` enforced on all buckets; RDS `publicly_accessible = false`; AWS Config rule `s3-bucket-public-read-prohibited` triggers automated remediation. |
| 4 | **Data Exfiltration via Compromised Pod** — A compromised microservice pod exfiltrates data to an external attacker-controlled endpoint. | Low | Critical | Kubernetes NetworkPolicy default-deny egress; AWS Network Firewall FQDN allowlist; all egress routes through NAT Gateway with VPC Flow Logs and GuardDuty monitoring. |
| 5 | **Noisy Neighbour / Tenant Data Bleed (Standard Tier)** — A resource-heavy or compromised tenant affects or accesses another tenant's data in the shared cluster. | Low | High | Row-Level Security (RLS) in PostgreSQL enforces `tenant_id` predicates; Kubernetes NetworkPolicy between namespaces (default deny); Pod Security Admission `restricted` profile prevents container escapes. |

---

## Secrets Rotation Runbook

This runbook covers the manual rotation procedure for two critical secret types: **RDS database credentials** and **JWT signing secrets**. It should be executed by an on-call engineer with break-glass access or during a scheduled rotation window.

### Prerequisites
- Approved break-glass access request (or scheduled maintenance window ticket).
- AWS CLI configured with appropriate role.
- `kubectl` access to the target cell cluster.

---

### RDS Credential Rotation

> This procedure rotates the master user password for the billing service PostgreSQL database in AWS Secrets Manager.

1. **Trigger rotation in AWS Secrets Manager:**
   ```bash
   aws secretsmanager rotate-secret \
     --secret-id <environment>-billing-db-credentials \
     --region eu-central-1
   ```
   Secrets Manager will automatically invoke the rotation Lambda function to generate a new password and update the database. Wait for the rotation to complete:
   ```bash
   aws secretsmanager describe-secret \
     --secret-id <environment>-billing-db-credentials \
     --query 'RotationEnabled,LastRotatedDate'
   ```

2. **Force pod restart to pick up the new secret:**
   The External Secrets Operator will sync the new secret to Kubernetes automatically within its poll interval (default: 1 hour). To force an immediate refresh:
   ```bash
   kubectl annotate externalsecret billing-service-secrets \
     force-sync=$(date +%s) -n <namespace>
   # Then restart the Deployment
   kubectl rollout restart deployment/billing-service -n <namespace>
   ```

3. **Verify:**
   ```bash
   kubectl rollout status deployment/billing-service -n <namespace>
   kubectl logs -l app=billing-service -n <namespace> --tail=50
   ```
   Confirm there are no `connection refused` or `authentication failed` errors.

4. **Audit:** Log the rotation event in the incident/change ticket and confirm the CloudTrail event for `RotateSecret` is present.

---

### JWT Secret Rotation

> This procedure rotates the `jwtSecret` used for signing authentication tokens. Note: this causes all existing user sessions to be invalidated.

1. **Announce a maintenance window** (notify customer support and, if required, affected tenants).

2. **Generate a new JWT secret:**
   ```bash
   openssl rand -base64 48
   ```

3. **Update the secret in AWS Secrets Manager:**
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id billing-service-secrets \
     --secret-string "{\"jwtSecret\":\"<NEW_SECRET>\", \"dbPassword\":\"<EXISTING>\", \"stripeKey\":\"<EXISTING>\"}" \
     --region eu-central-1
   ```

4. **Force sync and pod restart** (same as steps 2–3 in RDS rotation above).

5. **Audit:** Log the rotation event and confirm the CloudTrail `PutSecretValue` entry. Close the maintenance window ticket.
