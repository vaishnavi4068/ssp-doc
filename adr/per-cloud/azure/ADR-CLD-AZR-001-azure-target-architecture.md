# ADR-CLD-AZR-001: Azure Per-Cloud Target Architecture

- **ADR ID:** ADR-CLD-AZR-001
- **Level:** per-cloud (azure)
- **Status:** Proposed
- **Owner:** Norm (Shared Mailbox: `spp-cloud-azure@tbd`, Named Owner: `Norm`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver], Raju [Security])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define how Microsoft Azure stands on its own as a 2.0 target cloud for SPP while orchestrated by the GCP-hosted SPP control plane.

## Context

In the design discussion (`uploads/design-digest.md`):

1. **Every Cloud Stands on Its Own:** Azure target environments must store their own `Expected` and `Observed` Terraform states in Azure Blob Storage (with native Blob lease state locking) and execute using per-subscription Azure Managed Identities / Service Principals.
2. **2.0 Management Group & Subscription Layout:** Following `ADR-GLB-003`, Azure uses one state storage account/container per Line of Business (LOB) management group with `expected/` and `observed/` folder prefixes and one state file per 2.0 Azure subscription.

## Decision

1. **State Storage in Azure:** Store `Expected` and `Observed` Terraform state files for Azure workloads in Azure Blob Storage (one storage container per LOB management group, with blob paths `expected/<subscription-id>/terraform.tfstate` and `observed/<subscription-id>/terraform.tfstate`), encrypted with Azure Key Vault Customer-Managed Keys (CMK) and locked via native Azure Blob leases.
2. **Identity & Blast Radius in Azure:** Provision one dedicated Managed Identity / Service Principal per target 2.0 Azure subscription, federated via Workload Identity Federation from the central SPP Platform identity in GCP (zero static client secrets).
3. **Approved-State Guardrails for Azure:** Enforce Azure Key Vault CMK encryption, `>= 90`-day retention, private endpoints / public network access disabled, approved Azure regions (`eastus`, `centralus`), and mandatory governance tags (`apm_id`, `cost_center`, `environment`, `owner`, `data_classification`, `managed_by = "spp"`).

## Requirements

- **REQ-1 (MUST):** Azure `Expected` and `Observed` Terraform state files MUST be stored in Azure Blob Storage within Azure under `expected/<subscription-id>/terraform.tfstate` and `observed/<subscription-id>/terraform.tfstate`.
- **REQ-2 (MUST):** Every target 2.0 Azure subscription MUST use a dedicated Managed Identity or federated Service Principal with zero static client secrets stored in SPP.
- **REQ-3 (MUST):** All Azure resources in `Approved` state MUST enforce Customer-Managed Keys (CMK), `>= 90`-day retention, public access disabled, approved regions (`eastus`, `centralus`), and required governance tags (`ADR-GLB-006`, `ADR-GLB-007`).

## Guardrails

- **GR-1:** Never store Azure `Expected` or `Observed` Terraform state files in GCS or S3.
- **GR-2:** Never store static Azure Service Principal `client_secret` values in PostgreSQL, Kubernetes Secrets, or git.
- **GR-3:** Never use a shared subscription-spanning `prod` or `nonprod` identity across multiple 2.0 Azure subscriptions.

## Consequences

### Positive

- Native Azure Blob lease locking and per-subscription federated identities keep Azure self-contained and aligned with the GCP and AWS blast-radius model.

### Negative / Trade-offs

- Requires alignment with the Azure 2.0 platform team to finalize the Management Group to LOB state storage account mapping before Phase 6 Azure modules launch.

## Acceptance Criteria

- [ ] Azure resource modules (`ssp-module-azure-storage`, etc.) configure Terraform `>= 1.10` and pass `run_gate.sh` in Phase 6.
- [ ] `gates/policies/spp_gate.rego` enforces approved Azure regions (`eastus`, `centralus`), CMK encryption, and `>= 90`-day retention.

## Success Criteria

- **SC-1:**
  - **Given** an `Approved` request targeting a 2.0 Azure subscription in `eastus`
  - **When** the runner Job initializes the Terraform `azurerm` backend
  - **Then** it authenticates via OIDC Workload Identity Federation to that subscription's identity and writes state to `expected/<subscription-id>/terraform.tfstate` in the LOB Azure Blob container.
- **SC-2:**
  - **Given** an Azure request targeting an unapproved region or containing a `client_secret` key
  - **When** evaluated by the OPA gate
  - **Then** the gate rejects the payload.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Defines the Azure 2.0 target cloud architecture |
| `ssp-cp` | Validates Azure subscription targets, regions (`eastus`, `centralus`), and CMK guardrails |
| `ssp-workers` | Configures `azurerm` backend and OIDC federation for Azure runner Jobs |
| `ssp-module-<type>` | Implements Azure resource modules in Phase 6 (`ADR-BP-002`) |
| `spp-factory-foundation` | Enforces Azure region and secret rules in `gates/policies/spp_gate.rego` |

## Open Questions

- [ ] **OQ-1 (Azure 2.0 Management Group Mapping):** What is the exact mapping between Azure Management Groups and the dedicated subscription/storage account hosting each LOB's state container?
- [ ] **OQ-2 (Azure Naming Constraints):** Certain Azure resource types (such as `azurerm_storage_account`) only allow lowercase alphanumeric characters (`3..24` chars, no hyphens). How should `ADR-GLB-006` normalize hyphenated `resource_name` values for Azure storage accounts?

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](../../global/ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-003: Four-State Provisioning Model and Storage Layout](../../global/ADR-GLB-003-four-state-model.md)
- [ADR-GLB-005: Identity, Workload Identity, and Authentication](../../global/ADR-GLB-005-identity-and-authentication.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../../business-process/ADR-BP-002-build-order-and-phasing.md)
