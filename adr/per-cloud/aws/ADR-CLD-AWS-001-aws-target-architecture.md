# ADR-CLD-AWS-001: AWS Per-Cloud Target Architecture

- **ADR ID:** ADR-CLD-AWS-001
- **Level:** per-cloud (aws)
- **Status:** Proposed
- **Owner:** Dwayne (Shared Mailbox: `spp-cloud-aws@tbd`, Named Owner: `Dwayne`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define how Amazon Web Services (AWS) stands on its own as a 2.0 target cloud for SPP—supporting customer-facing workloads such as Aetna.com—while orchestrated by the GCP-hosted SPP control plane.

## Context

In the design discussion (`uploads/design-digest.md`):

1. **Every Cloud Stands on Its Own:** While the SPP control plane runs in GCP (`ADR-CLD-GCP-001`), AWS must store its own `Expected` and `Observed` Terraform states in Amazon S3 and execute changes using AWS-native IAM roles.
2. **Terraform 1.10+ Native S3 Locking (No DynamoDB):** Terraform 1.10 introduced native S3 state locking (`use_lockfile = true`), eliminating the need to provision and manage DynamoDB lock tables.
3. **LOB Bucket per OU Host Account & 1 State per AWS Account:** Following `ADR-GLB-003`, AWS uses one S3 state bucket per Line of Business (LOB) / Organizational Unit (OU) host account with `expected/` and `observed/` folders and one state file per 2.0 AWS account, plus one dedicated IAM execution role per AWS account assumed by the SPP platform identity ("kill button").

## Decision

1. **State Storage in AWS:** Store `Expected` and `Observed` Terraform state files for AWS workloads in Amazon S3 (`s3://<lob-ou-state-bucket>/expected/<aws-account-id>/terraform.tfstate` and `s3://<lob-ou-state-bucket>/observed/<aws-account-id>/terraform.tfstate`) with **Terraform `>= 1.10` native S3 state locking (`use_lockfile = true`)** and AWS KMS CMEK encryption.
2. **Identity & Blast Radius in AWS:** Provision one dedicated IAM execution role per target 2.0 AWS account (`arn:aws:iam::<account-id>:role/spp-tenant-provisioner`), assumed via short-lived OIDC / workload identity federation from the central SPP Platform identity in GCP (no static `AKIA*` IAM user access keys).
3. **Approved-State Guardrails for AWS:** Enforce AWS KMS Customer-Managed Keys (CMK), `>= 90`-day retention, public access block, approved AWS regions (`us-east-1`, `us-west-2`), and mandatory tags (`apm_id`, `cost_center`, `environment`, `owner`, `data_classification`, `managed_by = "spp"`).

## Requirements

- **REQ-1 (MUST):** All AWS Terraform state backends in SPP MUST use Amazon S3 with `use_lockfile = true` (Terraform `>= 1.10`) and MUST NOT require DynamoDB lock tables.
- **REQ-2 (MUST):** AWS `Expected` and `Observed` state files MUST reside in S3 within AWS (one S3 bucket per LOB/OU host account, `expected/<aws-account-id>/terraform.tfstate` and `observed/<aws-account-id>/terraform.tfstate`), never in GCS or Azure Blob.
- **REQ-3 (MUST):** Every target 2.0 AWS account MUST have a dedicated IAM execution role assumed via short-lived federated tokens from the SPP platform runner identity; static AWS IAM access keys (`AKIA*`) are prohibited.
- **REQ-4 (MUST):** All AWS resources in `Approved` state MUST enforce KMS encryption, `>= 90`-day retention, and required governance tags (`ADR-GLB-006`, `ADR-GLB-007`).

## Guardrails

- **GR-1:** Never provision DynamoDB tables for Terraform state locking in AWS.
- **GR-2:** Never create or store static AWS IAM user access keys (`AKIA*`) in Kubernetes Secrets, PostgreSQL, or git.
- **GR-3:** Never share a single IAM execution role across multiple AWS accounts without per-account role assumption.

## Consequences

### Positive

- Eliminates DynamoDB state-locking infrastructure overhead while keeping AWS state self-contained inside AWS.
- Per-account IAM role assumption limits blast radius to a single 2.0 AWS account per run.

### Negative / Trade-offs

- Requires coordination with the Security team (who owns AWS OUs) to provision per-OU host accounts for LOB S3 state buckets.

## Acceptance Criteria

- [ ] AWS resource modules (`ssp-module-s3-bucket`, etc.) configure Terraform `>= 1.10` and pass `run_gate.sh` in Phase 6.
- [ ] `gates/policies/spp_gate.rego` enforces approved AWS regions (`us-east-1`, `us-west-2`), KMS CMEK, `>= 90`-day retention, and `AKIA*` secret rejection.

## Success Criteria

- **SC-1:**
  - **Given** an `Approved` request targeting a 2.0 AWS account in `us-east-1`
  - **When** the runner Job initializes the Terraform backend
  - **Then** it configures the `s3` backend with `use_lockfile = true` pointing to `expected/<aws-account-id>/terraform.tfstate` and assumes the account's dedicated IAM role via OIDC federation.
- **SC-2:**
  - **Given** a payload containing an AWS access key pattern (`AKIA...`) or targeting an unapproved AWS region
  - **When** evaluated by the OPA gate
  - **Then** the gate rejects the payload.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the AWS 2.0 target cloud architecture |
| `ssp-cp` | Validates AWS account targets, regions (`us-east-1`, `us-west-2`), and KMS guardrails |
| `ssp-workers` | Configures S3 backend (`use_lockfile = true`) and OIDC role assumption for AWS runner Jobs |
| `ssp-module-<type>` | Implements AWS resource modules in Phase 6 (`ADR-BP-002`) |
| `spp-factory-foundation` | Enforces AWS region and secret rules in `gates/policies/spp_gate.rego` |

## Open Questions

- [ ] **OQ-1 (Per-OU Host Accounts with Security):** Security currently owns AWS Organizational Units (OUs). Will Security approve provisioning one dedicated host AWS account per OU to hold the LOB S3 state bucket?
- [ ] **OQ-2 (Multi-App AWS Accounts):** Dwayne noted in the design session that 1-application-per-AWS-account is not guaranteed ("can't convince a lot of people"). If multiple applications (`apm_id`s) share a single 2.0 AWS account, should state remain 1 state file per AWS account or partition by `<aws-account-id>/<apm-id>/terraform.tfstate`?

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](../../global/ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](../../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../../business-process/ADR-BP-002-build-order-and-phasing.md)
