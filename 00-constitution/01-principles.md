# 01 — Principles

These are the non-negotiables. Each later spec is an elaboration of one or more of these.

| ID | Principle | Consequence |
|---|---|---|
| SSP-PRIN-001 | **Self-service only; behave like a hyperscaler.** | No ticket-driven provisioning path exists. Every capability is reachable through UI, API and chat with the same contract. Humans in the platform team operate the platform; they do not provision for tenants. |
| SSP-PRIN-002 | **Four states, nothing else.** Requested → Approved → Expected → Observed. | Every resource the platform knows about is in exactly one state at a time; drift is defined as Expected ≠ Observed. |
| SSP-PRIN-003 | **Approval is guardrail application, not a signature.** | "Approved" means the request plus every guardrail the catalog and policy enforce (CMEK, retention, security requirements). It is produced by code. A human approval or ServiceNow CR is an additional gate only where change management requires it. |
| SSP-PRIN-004 | **No secrets before Expected.** | Requested and Approved never contain secrets. Secrets are injected after approval, only into Expected, and are kept out of Terraform state wherever the provider allows. |
| SSP-PRIN-005 | **One tenant boundary, one identity, one state.** | Each GCP project / AWS account / Azure subscription has exactly one platform service account and one Terraform state file. |
| SSP-PRIN-006 | **Control plane in GCP.** | The platform runs on GCP (GKE, Cloud SQL, GCS). Other clouds are targets, reached by federated identity, never by static keys. |
| SSP-PRIN-007 | **Generate, don't duplicate.** | The ServiceSpec is the single definition of a service. UI forms, API validation, policy inputs, Terraform variables, pricing and docs are derived from it. Adding a service never requires redeploying the storefront. |
| SSP-PRIN-008 | **Everything is a workflow.** | Provisioning, post-build, drift, import and decommission run as Temporal workflows on the platform's own Temporal cluster. There are no cron scripts or hand-run playbooks on the critical path. |
| SSP-PRIN-009 | **Humans own intent; agents own code; gates own merge.** | Specs, ADRs, holdout scenarios and gate definitions are written by humans. Code is written by agents. Automated gates decide what merges, with human approval added by autonomy tier. |
| SSP-PRIN-010 | **Blast radius is designed, not assumed.** | Every identity, bucket, lock and module upgrade has an explicit blast-radius statement and a kill switch. |
| SSP-PRIN-011 | **Show the code.** | Every order can be viewed as the equivalent Terraform and CLI, so the platform never hides what it does. |
| SSP-PRIN-012 | **Design for the 2.0 layout.** | One APM ID per service project. Legacy (1.0, multi-app shared projects) is imported through the migration app, not accommodated in the core model. |
