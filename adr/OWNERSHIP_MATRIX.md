# SPP ADR Ownership and Stakeholder Matrix (`adr/OWNERSHIP_MATRIX.md`)

Every ADR in `ssp-doc` requires a tracked owner consisting of **both** a shared team mailbox and a named accountable person (`ADR-BP-001`). Placeholder GitHub handles (`@manoj-todo`, `@dwayne-todo`, `@norm-todo`) and `*@tbd` shared mailboxes are **accepted placeholders for the `microdrive-dev` MVP** (to be replaced before production), with `@vaishnavi4068` configured on every `CODEOWNERS` path so GitHub review routing works immediately. Operations cannot be bypassed (per Allen / Norm), and transitioning any ADR from `Proposed` (unsigned) to `Accepted` (signed) requires explicit sign-off from the Architect (`Manoj`), Core Approvers (`Dwayne`, `Norm`), and the accountable domain owner.

---

## 1. Stakeholder & Domain Ownership Directory

| Domain / Responsibility | Named Owner(s) | GitHub Handle (Placeholder) | Shared Mailbox (Placeholder) | Scope & Action Items |
| :--- | :--- | :--- | :--- | :--- |
| **Architect** | **Manoj** | `@vaishnavi4068` / `@manoj-todo` | `spp-architecture@tbd` | Overall architecture, GCP host/service project model, data model, Factory Console `architect` role, CODEOWNERS lead |
| **Core Approvers** | **Dwayne**, **Norm** | `@dwayne-todo`, `@norm-todo` | `spp-architecture@tbd` | ADR/PR approvers (`CODEOWNERS`), Factory Console `approver` role, dark factory & UI direction (Dwayne), Taxi parity & operations gate (Norm) |
| **Lead Engineers / Code Owners** | **Norm**, **Manoj** | `@norm-todo`, `@manoj-todo` | `spp-engineering@tbd` | Code and technical design ownership across `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, and `ssp-module-<type>` |
| **Service Accounts in `microdrive-dev` (Non-Prod)** | **SPP Team** | `@vaishnavi4068` | `spp-engineering@tbd` | Provides and owns the `spp-platform` runner GCP Service Account (`<runner-sa>@microdrive-dev.iam.gserviceaccount.com`, `TODO: vaishnavi4068`) and Workload Identity bindings in `microdrive-dev` |
| **Enterprise Clusters & Future Prod Service Accounts** | **Hurley** | `@hurley-todo` | `spp-cloud-iam@tbd` | Enterprise cluster issuance and future production environment/APM ID provisioning outside `microdrive-dev` |
| **ServiceNow / CMDB (Post-MVP Placeholder)** | **Ken O'Connor** *(plus Stephanie)* | `@ken-oconnor-todo` | `spp-itsm-cmdb@tbd` | Out of scope for `microdrive-dev` MVP (interface placeholder only; live ServiceNow/CMDB integration deferred post-MVP) |
| **Security** | **Raju's team** *(plus Durant)* | `@raju-security-todo` | `spp-security@tbd` | Security baseline rules injected in `Approved` state (CMEK, `>= 90d` retention, public access prevention) so Raju's scanner never deletes SPP resources |
| **Operations & DBA** | **Allen**, **Karen**, **Norm** | `@allen-todo`, `@karen-todo`, `@norm-todo` | `spp-operations@tbd` | Non-bypassable Operations Gate (`ADR-GLB-007`), database operational rules, Jenkins DBA post-build criteria, persona permissions |
| **Networking / CIDR / Infoblox** | **John Simon** | `@john-simon-todo` | `spp-network@tbd` | IP/CIDR range allocation and Infoblox integration for 2.0 GCP projects |
| **Executive Sponsor / DB Strategy** | **Saul** | `@saul-todo` | `spp-leadership@tbd` | Executive sponsorship and database hosting strategy |

---

## 2. ADR Sign-Off Matrix

| ADR ID | Level | Title | Named Owner | Shared Mailbox | Required Signers | Current Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **ADR-GLB-001** | `global` | Global Architecture Overview | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-002** | `global` | Languages and Technology Stack | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-003** | `global` | Four-State Provisioning Model and Storage Layout | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-004** | `global` | Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL) | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm, Karen | Proposed (Unsigned) |
| **ADR-GLB-005** | `global` | Identity, Workload Identity, and Authentication | Manoj | `spp-security@tbd` | Manoj, Dwayne, Norm, Raju | Proposed (Unsigned) |
| **ADR-GLB-006** | `global` | Naming and Labeling Conventions | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-007** | `global` | Governance Gates and Policy (Rego) | Manoj | `spp-policy@tbd` | Manoj, Dwayne, Norm, Raju, Allen/Karen | Proposed (Unsigned) |
| **ADR-BP-001** | `business-process` | Ownership Map and Stakeholder Governance | Norm | `spp-governance@tbd` | Manoj, Dwayne, Norm, Allen/Karen, Raju | Proposed (Unsigned) |
| **ADR-BP-002** | `business-process` | Product Build Order and Delivery Phasing | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-SVC-001** | `endpoint-service` | First Vertical Slice — GCS Bucket End-to-End (No UI) | Manoj | `spp-storage-gcp@tbd` | Manoj, Dwayne, Norm, Raju | Proposed (Unsigned) |
| **ADR-CLD-GCP-001** | `per-cloud (gcp)` | Runtime Platform (GKE `md-dev`, Tainted `spp-pool`, Namespaces, and Self-Hosted Temporal) | Manoj | `spp-cloud-gcp@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-AUT-001** | `automation` | Terraform Execution via Deterministic Kubernetes Jobs | Dwayne | `spp-automation@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-AUT-002** | `automation` | Day-2 Operations Scope | Norm | `spp-automation@tbd` | Manoj, Dwayne, Norm, Allen/Karen | Proposed (Unsigned) |
| **ADR-AUT-003** | `automation` | Software Factory ADR Flow, 10 Role Skills, and Verification Gates | Manoj | `spp-factory@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
