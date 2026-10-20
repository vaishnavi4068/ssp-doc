# 03 — Glossary and cloud-neutral ontology

Use these words exactly. The storefront metaphor (from the chosen prototype) and the platform model map one-to-one; the table makes the mapping explicit so UI, API and workflows never disagree.

## Platform terms

| Term | Definition | GCP | AWS | Azure |
|---|---|---|---|---|
| **Tenant boundary** | The unit that owns one platform service account and one Terraform state file | Project | Account | Subscription |
| **LOB boundary** | The grouping that owns one state bucket and one CMEK key | Host project (folder) | OU (per-OU host account) | Management group |
| **APM ID** | Application identifier from the enterprise portfolio; drives tier, data classification, cost center, entitlements | label `apm_id` | tag `apm_id` | tag `apm_id` |
| **Tier** | Application criticality (1 = highest). Drives defaults such as active-active databases | — | — | — |
| **Data classification** | PHI / PII / Confidential / Internal / Public. Drives CMEK, retention, residency | — | — | — |
| **Service** | A provisionable offering defined by one ServiceSpec, implemented by one `ssp-module-<service>` repo | e.g. `gcp.spanner-instance` | e.g. `aws.s3-bucket` | e.g. `azure.sql-database` |
| **ServiceSpec** | The YAML definition of a service: request schema, guardrails, module reference, UI template, pricing, post-build steps, lifecycle | | | |
| **Catalog bundle** | The released artifact of a service: ServiceSpec + request schema + UI template + Rego + pricing + module zip, versioned | | | |
| **Order** | A user's request to create, change or delete one resource instance in one tenant boundary. The API object behind "Requested" | | | |
| **Approved spec** | The immutable result of applying guardrails and policy to an order. The object behind "Approved" | | | |
| **Resource instance** | One provisioned thing (a Spanner instance, a bucket) produced by one order; lives in a tenant boundary's desired set | | | |
| **Desired set** | All approved resource instances of a tenant boundary; rendered into that boundary's single Terraform root module. The object behind "Expected" | | | |
| **Run** | One Terraform operation (plan, apply, import, refresh, destroy) executed as a Kubernetes Job for one tenant boundary | | | |
| **Observed state** | The Terraform state after apply plus periodic refresh, for one tenant boundary. The object behind "Observed" | | | |
| **Drift** | Any difference between the desired set's rendered configuration and the observed state | | | |
| **Platform SA** | The central service account the Terraform runner uses to impersonate tenant SAs; disabling it is the kill switch | `ssp-tf-runner@<cp-project>` | role in the platform account | app registration |
| **Tenant SA** | The one service account per tenant boundary that Terraform acts as | `ssp-tenant@<project>` | role `ssp-tenant` in account | managed identity |
| **Post-build** | Steps after apply that register or configure the resource (CMDB, backup enrolment, monitoring, notifications) | | | |
| **Kill switch** | Disabling the Platform SA, or pausing the reconciler at global / LOB / tenant scope | | | |

## Storefront vocabulary ↔ platform model

| Storefront word (UI) | Platform object | State |
|---|---|---|
| SKU | Service (catalog bundle) | — |
| Delivery destination | Tenant boundary the buyer is entitled to | — |
| Configure & Buy / Checkout | Building an order from the ServiceSpec request schema | — |
| Order Summary (receipt) | Preflight result: guardrails applied, policy result, price estimate, equivalent code | — |
| Place order | `POST /v1/orders` | **Requested** |
| Order confirmed | Approved spec created (guardrails applied, policy passed, CR attached if needed) | **Approved** |
| Preparing / Shipping | Desired set re-rendered; run planned and applied | **Expected** |
| Delivered | Observed state captured; post-build complete | **Observed** |
| Fulfilled Orders | Orders in Observed state | — |
| Wishlist | Saved drafts | — |
| Sidekick Concierge | Conversational provisioning assistant | — |

## Identifiers

| ID | Format | Example |
|---|---|---|
| Order ID | `ord_` + ULID | `ord_01JAM3K8Z2W7Q4N9B5X0F1C2D3` |
| Run ID | `run_` + ULID | `run_01JAM3…` |
| Operation ID | `<run_id>:<attempt>` ; Job name = `tf-` + first 20 hex of SHA-256(operation ID) | `tf-9f2c1a0b7d3e4f5a6b7c` |
| Service ID | `<cloud>.<service-slug>` | `gcp.spanner-instance` |
| Requirement ID | `SSP-<AREA>-<nnn>` | `SSP-API-012` |
| ADR ID | `<G|B|E|C|A>-<nnnn>` (E and C carry a suffix) | `E-SPAN-0001`, `C-GCP-0002` |

## Words we do not use

- "Approve" for a human click — say "CR approval" or "owner sign-off".
- "Environment" for a tenant boundary — say project / account / subscription, or "tenant boundary".
- "Workspace" — ambiguous (Terraform, Temporal, Slack).
- "Stack" — ambiguous; say desired set or root module.
