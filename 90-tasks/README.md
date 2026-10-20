# 90 — Tasks

One file per task (`T-nnnn-slug.md`), format in `50-factory/53-task-template.md`. Phase 0/1 tasks T-0001…T-0022 are ordered so that the bootstrap runbook (80-runbooks/81-bootstrap.md) can be completed: ssp-cp core (T-0002…T-0010) → workers (T-0011…T-0013) → first module (T-0014) → UI (T-0015…T-0018) → control room, migrate, Sidekick (T-0019…T-0021) → acceptance (T-0022, human-only).

| ID | Repo | Tier | Title |
|---|---|---|---|
| T-0001 | ssp-doc | T0 | Write the decided ADRs (G-0001..G-0005, C-GCP-0001, C-GCP-0002, A-0001..A-0003, B-0007) from the decisions register using the ADR template |
| T-0002 | ssp-cp | T2 | Create Postgres migration 0001 from the domain model, sqlc queries and the store package |
| T-0003 | ssp-cp | T2 | Catalog bundle loader from GCS index.json, ServiceSpec/schema validation, derive and guardrail evaluation, pricing evaluator, code view renderer |
| T-0004 | ssp-cp | T2 | Embedded OPA request-stage evaluation, baseline platform rules SSP-POL-1xx with tests, bundle fetch by digest |
| T-0005 | ssp-cp | T2 | oapi-codegen strict server from 12-openapi.yaml, chi wiring, middleware (request id, OTel, JWT auth, persona, entitlement, idempotency, problem details), /healthz /readyz |
| T-0006 | ssp-cp | T2 | Implement /destinations and /destinations/{id}/context from entitlements and tenant/APM records |
| T-0007 | ssp-cp | T2 | Implement POST /orders/preflight via approval.Compute (shared with ComputeApproval) |
| T-0008 | ssp-cp | T2 | POST /orders with preview_hash check, order_event stream (SSE via LISTEN/NOTIFY), cancel, signoff, code endpoints |
| T-0009 | ssp-cp | T2 | OrderWorkflow with ComputeApproval, gate loop (CR via ServiceNow twin, owner sign-off), hand-off to reconciler, finalize |
| T-0010 | ssp-cp | T2 | TenantReconciler entity workflow: batching, AllocateGeneration, Render (main.tf.json), CreateRun, PlanGate, CaptureObserved, DriftScan schedule |
| T-0011 | ssp-workers | T2 | tf-worker: RunTerraform activity with deterministic Job names, re-attach, polling with heartbeats, result.json as source of truth, cancellation cleanup, metrics |
| T-0012 | ssp-workers | T3 | tf-runner image (Dockerfile.runner, runner.sh, provider mirror, gcsutil) exactly as 30-infra/tf-worker |
| T-0013 | ssp-workers | T3 | Helm chart and runs-namespace manifests mirroring 30-infra/tf-worker; NetworkPolicies; RBAC |
| T-0014 | ssp-module-gcs-bucket | T1 | Create ssp-module-gcs-bucket (or spanner) from the module template: module, ServiceSpec, request schema, ui.yaml, pricing, policies, import mapping, tests, release workflow |
| T-0015 | ssp-ui | T2 | App shell (top bar with destination selector, search ⌘K, Sidekick button, orders, theme), left nav with frequent SKUs, Storefront Home from catalog and destinations |
| T-0016 | ssp-ui | T2 | @ssp/form-renderer: steps, widgets (text, select, radio-cards, number+unit, toggle, table, key-value, derived read-only), Ajv validation, receipt bindings, Storybook |
| T-0017 | ssp-ui | T2 | Configure & Checkout page with stepper, numbered fields with mono keys, sticky Order Summary (Summary|Code), debounced preflight, Place order with preview_hash |
| T-0018 | ssp-ui | T2 | Order tracking page (SSE timeline, run panel, post-build checklist), Fulfilled Orders and Resources tables, resource detail actions |
| T-0019 | ssp-control-room | T2 | Control room shell, Fleet page, Tenants, Runs with log viewer, pause/resume with blast-radius dialog, two-person kill switch |
| T-0020 | ssp-migrate | T2 | Migration wizard steps 1-6 against ImportWorkflow: source, inventory, mapping editor (schema-aware), onboard, dry-run diff, reconcile differences |
| T-0021 | ssp-cp | T2 | Assistant gateway: context assembly, router, knowledge path via Grounded interface (contextual/vertexrag), action path with preflight cards, SSE events; Sidekick panel wiring in ssp-ui |
| T-0022 | ssp-acceptance | T3 | (human-only) Write Phase 1 holdout scenarios: e2e for first service, 10 conversational scenarios with golden OrderInput, 5 chaos, 10 red-team; evaluator posts gate/evaluator |
