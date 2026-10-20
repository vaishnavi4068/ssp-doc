# 02 — Decisions Register (locked)

Source: design session, Norm / Manoj / Dwayne, October 2026 (transcript in the project archive). A decision changes only through a superseding ADR in `60-adr/` approved by the platform team.

| # | Area | Decision | Rationale recorded in session | ADR |
|---|---|---|---|---|
| D-01 | Control plane cloud | **GCP.** AWS rejected as home cloud. | AWS is the smallest footprint; Aetna customer-facing stack lives there; the platform that runs everything should not live in the smallest cloud. | G-0001 |
| D-02 | State model | **Four states:** Requested → Approved → Expected → Observed. Drift = Expected vs Observed. | Clean separation of intent, policy, plan and reality. | G-0002 |
| D-03 | Requested + Approved storage | **Centralized Postgres in GCP.** No secrets stored. | Transactional, queryable, auditable. | G-0002 |
| D-04 | Approved definition | Approved = request **plus enforced guardrails** (CMEK, retention, security requirements). | Approval is policy application. | G-0002 |
| D-05 | Secrets | Injected **after approval**, into Expected only. | Keeps the request store free of secrets. | G-0004 |
| D-06 | Expected + Observed (Terraform state) | **Object storage** (GCS / S3 / Blob) with native locking. Postgres rejected. | Write amplification, TOAST/vacuum churn, weaker trust boundary in Postgres; S3 no longer needs DynamoDB for locking. | C-GCP-0002 |
| D-07 | Bucket placement | **One bucket per LOB:** GCP host project, AWS account per OU, Azure management group. Per-project buckets rejected. | Unmanageable at 5,000+ projects. | C-GCP-0002 |
| D-08 | State granularity | **One state file per project / account / subscription.** | Manoj's prior per-category pattern discussed, not adopted. | A-0003 |
| D-09 | Scope | **Design for the 2.0 layout first** (one APM ID per service project). Legacy import later via a translation shim. CAP is an outlier that must move onto the platform. | Avoid designing around legacy shared projects. | G-0003 |
| D-10 | Identity | **One service account per project / account / subscription**, reached by **impersonation** from a central platform account that doubles as a **kill switch**. Taxi's 3 SAs (prod / nonprod / sandbox) are not reused. | Blast radius and auditability. | G-0005 |
| D-11 | Orchestration | **Self-hosted Temporal** on a dedicated GKE cluster/namespace, not the shared DevX Temporal. | Isolation; confidentiality of the project. | A-0001 |
| D-12 | Terraform execution | Dedicated Temporal **activity worker → Kubernetes Job** per operation. Job name derived deterministically from the operation ID so a retry re-attaches. **Polling (~30 s) first**, callback later. Worker and jobs in the same cluster. | Idempotent retries; no ingress on the worker. | A-0002 |
| D-13 | Policy | **New OPA rules** against the platform's own JSON schema. Nothing reused from Taxi. | Clean policy model. | A-0005 |
| D-14 | Post-build / bootstrap | Orchestrated in **Temporal**. POC converts team playbooks (Ansible host build, DBA Jenkins) into Temporal workflows; long-term ownership stays with the agent teams. | One orchestration model. | B-0004 |
| D-15 | Operating model | **Self-service only.** | Hyperscaler behaviour. | G-0001 |
| D-16 | ADR taxonomy | **5 types:** Global, Business Process, Endpoint (per service), Per-Cloud, Automation. Template: Goal, Requirements, Guardrails, Success Criteria. Platform team are sole PR approvers. Each ADR has an owner plus a shared mailbox. | Ownership tracking. | B-0007 |
| D-17 | UI | **Chat, search top-center, catalog of frequent items, show the equivalent IaC/CLI.** APM-ID-driven defaults (e.g., Tier 1 → active-active DB). Template-driven micro-frontend so new services don't need a redeploy. Visual direction: prototype *Gemini 4 Argon / shadcn-stack / #17 "Shopify Polaris Infrastructure Storefront"*. | Chosen from the prototype gallery. | A-0008 |
| D-18 | Build approach | **"Software dark factory."** One repo per Terraform resource module plus a spec/ADR repo. Agents generate code from specs. Humans design reconciliation gates and performance tests (target 10–20 provisions/day initially). | Throughput with control. | A-0009 |
| D-19 | Repos | `ssp-ui`, `ssp-cp` (Go APIs + Temporal workflows), `ssp-workers`, `ssp-doc`, `ssp-module-<service>`; new repos `ssp-control-room`, `ssp-migrate`. APIs deployed to the existing GKE cluster; existing GCP project. | Owner's repo layout. | A-0009 |
| D-20 | Assistant | Conversational provisioning on a **Contextual Language Model** (grounded, retrieval-trained) for the knowledge half; schema-constrained tool calling plus deterministic code for the action half. | Groundedness without letting a model approve anything. | A-0011 |

## Open items that block specific areas (not decisions)

| Item | Blocks | Owner from session |
|---|---|---|
| AWS OU structure and per-OU host account feasibility | AWS provider work | Dwayne (via Security) |
| Azure management group / subscription mapping | Azure provider work | Norm |
| Per-project SA isolation requirements and a test account | Identity rollout beyond POC | Dwayne → Raju / Durant |
| Taxi + console integration inventory (firewall, F5 vs cloud LB, Kafka, Infoblox, ServiceNow, CMDB, backup, patching) | Post-build workflows | Norm |
| Post-build / post-post-build steps per resource type | Post-build workflows | Manoj / Norm |
| CMDB CI classes for PaaS resources | CMDB registration | Dwayne → Ken O'Connor |
| API gateway path (Apigee / APGX via API Forge) | Public API exposure | Dwayne |
