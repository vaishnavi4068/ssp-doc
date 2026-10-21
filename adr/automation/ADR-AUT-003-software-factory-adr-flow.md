# ADR-AUT-003: Software Factory ADR Flow, 10 Role Skills, and Verification Gates

- **ADR ID:** ADR-AUT-003
- **Level:** automation
- **Status:** Proposed
- **Owner:** Manoj (Shared Mailbox: `spp-factory@tbd`, Named Owner: `Manoj`)
- **Signers:** Unsigned (Required Signers: Manoj [Architect], Dwayne [Approver], Norm [Approver])
- **Affected Repos:** `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`, `spp-factory-foundation`
- **Last Updated:** 2026-10-21

## Goal

Define how prerequisite and architecture ADRs in `ssp-doc` (and per-service ADRs in `ssp-cp`) flow into the AI Software Factory (`github.com/vaishnavi4068/spp-factory-foundation`), which consumes ADRs as its **sole input** and executes a single unified coding agent loading **10 role skills** under `agents/skills/` across a bounded 8-station Temporal assembly line.

## Context

In the design discussion (`uploads/design-digest.md` §6) and the deployed `spp-factory-foundation` repository:

1. **One Agent, Folder of Skills (Not Disconnected Specialized Bots):** Dwayne cited the industry shift toward "folders and skills… not necessarily specialized agents: one agent that goes to a folder structure, gets what they need." In `spp-factory-foundation`, a single sandboxed coding-agent runner (`@google/gemini-cli` on Vertex AI `gemini-2.5-pro`, running via GKE Workload Identity in namespace `spp-factory`) dynamically loads the station's `SKILL.md` from `agents/skills/<role>/SKILL.md` together with `GEMINI.md`, `AGENTS.md`, and the target ADR.
2. **ADRs as the Sole Input Contract:** Humans do not hand-write boilerplate Terraform modules, Rego policies, or repetitive API routes. Instead, humans author and sign off ADRs across the 5 ADR levels (`global`, `business-process`, `endpoint-service`, `per-cloud`, `automation`), design reconciliation loops, and govern permanent human gates.
3. **8-Station Temporal Assembly Line (`factory` Namespace):** Each factory work item runs as a `WorkItemWorkflow` on the `factory` Temporal namespace (`temporal-frontend.spp-temporal.svc.cluster.local:7233`), launching deterministic Kubernetes Jobs (`factory-wi-<work_item_id>-<station>[-attempt]`) in K8s namespace `spp-factory` with a maximum of **3 automated rework retries** before marking the work item `BLOCKED`.

## Decision

1. **Five-Level ADR Input Hierarchy (`ssp-doc/adr/` & `ssp-cp`):**
   - **Level 1 — `global` (`adr/global/`):** Platform-wide invariants (global overview, languages/stack, 4-state model, data model/Postgres, Workload Identity/auth, naming/labeling, OPA/Rego gates).
   - **Level 2 — `business-process` (`adr/business-process/`):** Stakeholder ownership map, operations governance, persona rules, and product build order.
   - **Level 3 — `endpoint-service` (`adr/endpoint-service/` & `ssp-cp`):** Per-service specifications (first vertical slice GCS bucket in `ssp-doc` and detailed GCS, Spanner, VM, API, and DB migration ADRs in `ssp-cp`).
   - **Level 4 — `per-cloud` (`adr/per-cloud/gcp/`):** Runtime platform on GCP (`md-dev`) and GCP 2.0 target architecture (`adr/per-cloud/` kept extensible for future clouds).
   - **Level 5 — `automation` (`adr/automation/`):** Deterministic K8s Job Terraform execution, Day-2 operations scope, and this factory ADR flow.
2. **Ten Role Skills Loaded by the Unified Factory Agent (`spp-factory-foundation/agents/skills/`):**

   | # | Skill Directory (`agents/skills/<role>/SKILL.md`) | Assembly-Line Station | Role & Output |
   | :--- | :--- | :--- | :--- |
   | **1** | `requirements-impact` | Station 1 (`impact`) | Analyzes changed/new ADRs across the 5 levels and produces an Impact Assessment Report mapping affected schemas, policies, and repos (`ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-<type>`). |
   | **2** | `change-plan` | Station 2 (`plan`) | Translates the Impact Assessment and ADR `REQ-*` / `GR-*` / `SC-*` into an ordered, testable Execution Change Plan with a 3-retry rework bound. |
   | **3** | `iac-module` | Station 3 (`build`) | Authors/updates Terraform `>= 1.10` modules (`module/`), `requested.json`/`approved.json` (`examples/`), and `mock_provider` tests (`tests/`) in `ssp-module-<type>`. |
   | **4** | `control-plane` | Station 3 (`build`) | Authors/updates Python FastAPI routes, PostgreSQL models/migrations, `Approved`-state enrichment, and Temporal/K8s Job contracts in `ssp-cp` and `ssp-workers`. |
   | **5** | `portal-and-catalog` | Station 3 (`build`) | Authors/updates declarative catalog schemas, Handlebars/micro-frontend UI templates, IaC preview templates, and persona field permissions for `ssp-ui`. |
   | **6** | `policy-and-compliance` | Station 3 (`build`) | Authors/updates clean-slate OPA/Rego policies (`*.rego`), unit tests (`*_test.rego`), and JSON Schemas enforcing CMEK, `>= 90`-day retention, Raju baseline, and zero secrets. |
   | **7** | `validation` | Station 4 (`gate`) | Executes the 7-stage verification gate (`gates/scripts/run_gate.sh`: YAML lint, ADR lint, JSON Schema, `opa test`, `conftest`, `terraform fmt/validate/test`, `tfsec`). Loops back to `build` up to **3 times** before marking `BLOCKED`. |
   | **8** | `change-review` | Station 5 (`review`) | Audits the git diff against all guardrails and compiles the ADR traceability summary and open questions (`OQ-*`) for human reviewers at Station 6 (`approval`). |
   | **9** | `drift-and-reconciliation` | Station 8 (`reconcile`) | Governs post-merge `Expected` vs. `Observed` drift detection keyed by CSP resource ID and reconciliation workflows. |
   | **10** | `standards-feedback` | Continuous Learning | Codifies lessons from gate failures, rework loops, PR review comments, and drift incidents back into ADRs, Rego policies, templates, and skills. |

3. **Phased Autonomy & Permanent Human Gates:**
   - **Phase 1 (Supervised Factory — Initial):** Human sign-off required at **1) ADR**, **2) Change Plan (`plan`)**, and **3) Pull Request (`approval` before `merge`)**.
   - **Phase 2 (ADR-Driven Autonomy):** Human sign-off at **1) ADR** and **2) Pull Request** (`plan` auto-advances when impact checks pass).
   - **Phase 3 (Low-Risk Auto-Merge):** Human sign-off at **1) ADR only** for low-risk 2.0 resource modules passing 100% of gates with zero security/operations exceptions.
   - **Permanent Human Gates (Never Auto-Merged):** Moving an ADR from `Proposed` to `Accepted`, production Change Requests (`CHG*`), destructive deletes/decommissions, and security policy exceptions.

## Requirements

- **REQ-1 (MUST):** Every ADR in `ssp-doc/adr/` (and `ssp-cp`) MUST pass `spp-factory-foundation/gates/scripts/lint_adrs.py` (valid `Status`, `Level`, `Owner` with `Shared Mailbox:` and `Named Owner:`, `## Goal`, `## Requirements` with `REQ-N (MUST|SHOULD)`, `## Guardrails` with `GR-N`, `## Success Criteria` with `**Given**`/`**When**`/`**Then**`, `## Open Questions`, and `## Related ADRs`).
- **REQ-2 (MUST):** The software factory (`spp-factory-foundation`) MUST consume ADRs as its sole architectural specification input; factory agents MUST NOT invent product decisions beyond the ADRs and `uploads/design-digest.md`.
- **REQ-3 (MUST):** Any requirement that is ambiguous, assumed, or pending external stakeholder confirmation MUST be recorded under `## Open Questions` (`- [ ] **OQ-N:** ...`) in the governing ADR.
- **REQ-4 (MUST):** Factory coding-agent Kubernetes Jobs (`factory-wi-<id>-<station>[-attempt]`) MUST run in namespace `spp-factory` with zero cloud provisioning credentials and enforce a maximum of **3 rework retries** on gate failure before transitioning to `BLOCKED`.

## Guardrails

- **GR-1:** Never trigger a factory build run to invent unapproved product features without a corresponding ADR in `ssp-doc` or `ssp-cp`.
- **GR-2:** Never grant factory coding-agent Jobs (`spp-factory`) IAM permissions to impersonate the SPP runtime platform service account or modify live cloud infrastructure.
- **GR-3:** Never configure permanent human gates (ADR acceptance, `prod` CRs, destructive deletes, security exceptions) for `auto_merge`.

## Consequences

### Positive

- Clear, deterministic contract between `ssp-doc` (human-approved ADR intent) and `spp-factory-foundation` (automated 10-skill execution and 7-stage verification).
- Every line of generated Terraform, Rego, Python, or React code traces back to an `ADR-*` and `REQ-*` identifier.

### Negative / Trade-offs

- Requires discipline to keep ADRs updated first whenever requirements evolve ("Specs are the contract").

## Acceptance Criteria

- [ ] `README.md` in `ssp-doc` documents how ADRs flow into `spp-factory-foundation` and maps the 5 ADR levels and 10 role skills.
- [ ] All ADRs in `ssp-doc/adr/` pass `lint_adrs.py` with zero errors.
- [ ] Every ADR in this initial prerequisite PR has `Status: Proposed`, `Signers: Unsigned`, and an explicit `## Open Questions` section.

## Success Criteria

- **SC-1:**
  - **Given** the `ssp-doc/adr/` directory containing the prerequisite ADRs across all 5 levels
  - **When** validated by `spp-factory-foundation/gates/scripts/lint_adrs.py` and parsed by `services/factory-api/app/seed.py`
  - **Then** 100% of ADR files pass structural linting and parse cleanly into the Factory Console ADR catalog.
- **SC-2:**
  - **Given** an operator triggering a factory run from an ADR in the Factory Console
  - **When** `WorkItemWorkflow` executes in the `factory` Temporal namespace
  - **Then** each station (`impact`, `plan`, `build`, `gate`, `review`) loads its corresponding skill from `agents/skills/<role>/SKILL.md` and the target ADR from `ssp-doc`.

## Affected Repos

| Repository | Impact Summary |
| :--- | :--- |
| `ssp-doc` | Upstream ADR source of truth consumed by the factory |
| `spp-factory-foundation` | Reads `ssp-doc` ADRs, loads the 10 skills in `agents/skills/`, and runs `gates/scripts/run_gate.sh` |
| `ssp-cp` | Built and verified by the factory (`control-plane` & `policy-and-compliance` skills) |
| `ssp-workers` | Built and verified by the factory (`control-plane` & `drift-and-reconciliation` skills) |
| `ssp-ui` | Built and verified by the factory (`portal-and-catalog` skill) |
| `ssp-module-<type>` | Built and verified by the factory (`iac-module` & `policy-and-compliance` skills) |

## Open Questions

- [x] **OQ-1 (Cross-Repo ADR Sync into `spp-factory-foundation` — RESOLVED 2026-10-21):** *Resolved:* `factory-agent` performs a **multi-repo checkout via the Factory GitHub App** (checking out `ssp-doc`, `spp-factory-foundation`, and the target product repo for each station run).
- [x] **OQ-2 (GitHub App Installation Scope — DEFERRED TO LIVE GITHUB APP CUTOVER [Owner: Manoj / `@vaishnavi4068`]):** *Deferred to live GitHub App cutover:* When switching `factory-agent` from `dry` mode to `live` mode, install the Factory GitHub App across `ssp-doc`, `ssp-cp`, `ssp-workers`, `ssp-ui`, and all `ssp-module-<type>` repositories.

## Related ADRs

- [ADR-GLB-001: Global Architecture Overview](../global/ADR-GLB-001-global-architecture-overview.md)
- [ADR-GLB-007: Governance Gates and Policy (Rego)](../global/ADR-GLB-007-governance-gates-and-policy-rego.md)
- [ADR-BP-001: Ownership Map and Stakeholder Governance](../business-process/ADR-BP-001-ownership-map-and-governance.md)
- [ADR-BP-002: Product Build Order and Delivery Phasing](../business-process/ADR-BP-002-build-order-and-phasing.md)
