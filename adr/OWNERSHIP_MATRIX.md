# SPP ADR Ownership and Stakeholder Matrix (`adr/OWNERSHIP_MATRIX.md`)

Every ADR in `ssp-doc` requires a tracked owner consisting of **both** a shared team mailbox and a named accountable person (`ADR-BP-001`). Placeholder GitHub handles (`@manoj-todo`, `@dwayne-todo`, `@norm-todo`) and `*@tbd` shared mailboxes are **accepted placeholders for the `<spp-factory-host-project-id>` MVP** (to be replaced before production), with `@vaishnavi4068` configured on every `CODEOWNERS` path so GitHub review routing works immediately. Operations cannot be bypassed (per Allen / Norm), and transitioning any ADR from `Proposed` (unsigned) to `Accepted` (signed) requires explicit sign-off from the Architect (`Manoj`), Core Approvers (`Dwayne`, `Norm`), and the accountable domain owner.

---

## 1. Stakeholder & Domain Ownership Directory

| Domain / Responsibility | Named Owner(s) | GitHub Handle (Placeholder) | Shared Mailbox (Placeholder) | Scope & Action Items |
| :--- | :--- | :--- | :--- | :--- |
| **Architect** | **Manoj** | `@vaishnavi4068` / `@manoj-todo` | `spp-architecture@tbd` | Overall architecture, GCP host/service project model, data model, Factory Console `architect` role, CODEOWNERS lead |
| **Core Approvers** | **Dwayne**, **Norm** | `@dwayne-todo`, `@norm-todo` | `spp-architecture@tbd` | ADR/PR approvers (`CODEOWNERS`), Factory Console `approver` role, dark factory & UI direction (Dwayne), Taxi parity & operations gate (Norm) |
| **Lead Engineers / Code Owners** | **Norm**, **Manoj** | `@norm-todo`, `@manoj-todo` | `spp-engineering@tbd` | Code and technical design ownership across `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, and `ssp-module-<type>` |
| **Service Accounts in `<spp-factory-host-project-id>` (Nonprod)** | **SPP Team** | `@vaishnavi4068` | `spp-engineering@tbd` | Provides and owns the `spp-platform` runner GCP Service Account (`<runner-sa>@<spp-factory-host-project-id>.iam.gserviceaccount.com`, `TODO: vaishnavi4068`) and Workload Identity bindings in `<spp-factory-host-project-id>` |
| **Enterprise Clusters & Future Prod Service Accounts** | **Hurley** | `@hurley-todo` | `spp-cloud-iam@tbd` | Enterprise cluster issuance and future production environment/APM ID provisioning outside `<spp-factory-host-project-id>` |
| **ServiceNow / CMDB (Post-MVP Placeholder)** | **Ken O'Connor** *(plus Stephanie)* | `@ken-oconnor-todo` | `spp-itsm-cmdb@tbd` | Out of scope for `<spp-factory-host-project-id>` MVP (interface placeholder only; live ServiceNow/CMDB integration deferred post-MVP) |
| **Security** | **Raju's team** *(plus Durant)* | `@raju-security-todo` | `spp-security@tbd` | Security baseline rules injected in `Approved` state (CMEK, `>= 90d` retention, public access prevention) so Raju's scanner never deletes SPP resources |
| **Operations & DBA** | **Allen**, **Karen**, **Norm** | `@allen-todo`, `@karen-todo`, `@norm-todo` | `spp-operations@tbd` | Non-bypassable Operations Gate (`ADR-GLB-007`), database operational rules (`dbaas_reviewer`), Jenkins DBA post-build criteria, persona permissions |
| **Networking / CIDR / Infoblox** | **John Simon** | `@john-simon-todo` | `spp-network@tbd` | IP/CIDR range allocation and Infoblox integration for 2.0 GCP projects |
| **Executive Sponsor / DB Strategy** | **Saul** | `@saul-todo` | `spp-leadership@tbd` | Executive sponsorship and database hosting strategy |

---

## 2. ADR Sign-Off Matrix

| ADR ID | Level | Title | Named Owner | Shared Mailbox | Required Signers | Current Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **ADR-GLB-001** | `global` | Global Architecture Overview | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-002** | `global` | Languages and Technology Stack | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-003** | `global` | Four-Gate Provisioning State Model and Storage Layout | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-004** | `global` | Data Model and Centralized PostgreSQL Database (AlloyDB for PostgreSQL) | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm, Karen | Proposed (Unsigned) |
| **ADR-GLB-005** | `global` | Identity, Workload Identity, and Authentication | Manoj | `spp-security@tbd` | Manoj, Dwayne, Norm, Raju | Proposed (Unsigned) |
| **ADR-GLB-006** | `global` | Naming Conventions and Identifier Patterns | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-007** | `global` | Governance Gates, Guardrails, Invariants, and Policy (Rego) | Manoj | `spp-policy@tbd` | Manoj, Dwayne, Norm, Raju, Allen/Karen | Proposed (Unsigned) |
| **ADR-GLB-008** | `global` | Label and Tag Standard | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-GLB-009** | `global` | Resource Kind Registry | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-BP-001** | `business-process` | Ownership Map and Stakeholder Governance | Norm | `spp-governance@tbd` | Manoj, Dwayne, Norm, Allen/Karen, Raju | Proposed (Unsigned) |
| **ADR-BP-002** | `business-process` | Product Build Order and Delivery Phasing | Manoj | `spp-architecture@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-BP-003** | `business-process` | Roles, Personas, and Approval Gate Governance | Norm | `spp-governance@tbd` | Manoj, Dwayne, Norm, Allen/Karen, Raju | Proposed (Unsigned) |
| **ADR-SVC-001** | `endpoint-service` | First Vertical Slice — GCS Bucket (`gcs_bucket`) End-to-End and Guardrails | Manoj | `spp-storage-gcp@tbd` | Manoj, Dwayne, Norm, Raju | Proposed (Unsigned) |
| **ADR-SVC-002** | `endpoint-service` | Cloud Spanner Instance (`spanner_instance`) and Database (`spanner_database`) Specification | Manoj | `spp-database-gcp@tbd` | Manoj, Dwayne, Norm, Karen, Raju | Proposed (Unsigned) |
| **ADR-EXP-001** | `endpoint-service` (`experience`) | Agentic Chatbot Experience for Self-Service Provisioning | Dwayne | `spp-experience@tbd` | Manoj, Dwayne, Norm, Raju | Proposed (Unsigned) |
| **ADR-EXP-002** | `endpoint-service` (`experience`) | MCP Server Experience for Self-Service Provisioning | Manoj | `spp-experience@tbd` | Manoj, Dwayne, Norm, Raju | Proposed (Unsigned) |
| **ADR-EXP-003** | `endpoint-service` (`experience`) | Client SDK Experience (Python First, TypeScript Later) | Manoj | `spp-experience@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-EXP-004** | `endpoint-service` (`experience`) | Portal UI Experience (`ssp-ui` Storefront on IDP Design Variant 17) | Dwayne | `spp-experience@tbd` | Manoj, Dwayne, Norm, Raju | Proposed (Unsigned) |
| **ADR-CLD-GCP-001** | `per-cloud (gcp)` | Runtime Platform (SPP GKE Cluster, Tainted `spp-pool`, Namespaces, and Self-Hosted Temporal) | Manoj | `spp-cloud-gcp@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-AUT-001** | `automation` | Temporal Orchestration and Terraform Execution via Deterministic Kubernetes Jobs | Dwayne | `spp-automation@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-AUT-002** | `automation` | Day-2 Operations, Drift Detection, and Deletion Governance | Norm | `spp-automation@tbd` | Manoj, Dwayne, Norm, Allen/Karen | Proposed (Unsigned) |
| **ADR-AUT-003** | `automation` | Software Factory ADR Flow, 10 Role Skills, and Verification Gates | Manoj | `spp-factory@tbd` | Manoj, Dwayne, Norm | Proposed (Unsigned) |
| **ADR-AUT-004** | `automation` | Agent Harness ("Jev Model") and Deterministic Temporal Workflow Execution Layer | Manoj | `spp-automation@tbd` | Manoj, Dwayne, Norm, Raju | Proposed (Unsigned) |
