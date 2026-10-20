# 42 — `ssp-cp` Repository Structure and Build Instructions

Go control plane: API, workflows, control-plane activities, policy baseline, catalog tooling, migrations. Implements `10-product/12-api-spec.md`, `13-workflows-spec.md`, `14-policy-spec.md` (baseline), `15-catalog-servicespec.md` (loader), `17-conversational-provisioning-spec.md` (gateway).

```
ssp-cp/
├── AGENTS.md  .cursor/rules/  CODEOWNERS  Makefile  go.mod
├── cmd/
│   ├── api/main.go                 HTTP server (chi) — serves generated strict server
│   ├── worker/main.go              Temporal worker: task queue ssp-control (workflows + control activities); --selftest runs a hello workflow
│   ├── migrate/main.go             goose migrations (K8s Job)
│   ├── catalogctl/main.go          validate | publish | reload — used by module CI
│   └── policyctl/main.go           build platform bundle | impact-replay
├── api/openapi.yaml                copied from ssp-doc/10-product/12-openapi.yaml (CI verifies identical)
├── internal/
│   ├── api/gen/                    oapi-codegen (strict-server, types, chi)
│   ├── api/handlers/{catalog,destinations,orders,resources,runs,ops,imports,assistant}.go
│   ├── api/middleware/             requestid, otel, auth(jwt), persona, entitlement, idempotency, ratelimit, problem
│   ├── auth/                       JWKS cache, claims → principal, entitlement lookup (entitlements.yaml | ServiceNow)
│   ├── catalog/                    bucket index loader, bundle cache, schema validation, derive (CEL via cel-go), pricing evaluator, code view renderer
│   ├── policy/                     embedded OPA, bundle fetch/verify by digest, request-stage eval, impact replay
│   ├── render/                     desired set → main.tf.json + backend.hcl + manifest.json (shared by reconciler and /code)
│   ├── store/                      sqlc queries (queries/*.sql), tx helpers, LISTEN/NOTIFY event hub
│   ├── workflows/                  order.go, reconciler.go, drift.go, postbuild.go, import.go, release.go, testdata/histories/
│   ├── activities/                 approval.go (ComputeApproval), generation.go, render.go, runs.go (CreateRun, CaptureObserved, PlanGate), servicenow.go, cmdb.go, notify.go, inventory.go
│   ├── assistant/                  gateway.go (SSE), context.go, router.go, tools.go (calls own handlers in-process), llm/{vertex,anthropic}.go, grounded/{contextual,vertexrag}.go
│   └── events/                     SSE hub, event types
├── pkg/ssp/                        shared types: RunInput, RunResult, PolicyInput, Bundle, OrderEvent (imported by ssp-workers)
├── db/migrations/0001_init.sql …   from 11-domain-model.md
├── policy/platform/*.rego + tests  baseline rules SSP-POL-1xx/2xx
├── deploy/chart/                   Helm: api Deployment+Service+HPA, control-worker Deployment, migrate Job (pre-upgrade hook), ConfigMap, ServiceAccounts (WI annotations), NetworkPolicies
├── deploy/envs/{sandbox,nonprod,prod}.yaml
├── deploy/foundation/              Terraform for buckets, SAs, IAM conditions, Cloud SQL (T3; humans apply)
└── test/
    ├── integration/                testcontainers Postgres + Temporal dev server (temporalio/temporal dev-server image), twins
    └── e2e/                        sandbox smoke: order → observed with ssp-module-spanner
```

## Make targets

```
make generate   # oapi-codegen, sqlc, mocks; fails if git diff after regen
make lint       # golangci-lint, govulncheck, gitleaks
make test       # unit + workflow replay + policy tests
make itest      # integration (testcontainers)
make build      # images via ko or docker buildx; tags <semver>-<sha>
make bundle-policy  # policyctl build → ssp-catalog-<env>/policy/<digest>.tar.gz
```

## Key implementation notes (binding)

- SSP-CP-001 `ComputeApproval` and `preflight` share one function `approval.Compute(ctx, input) (Result, error)`; the only difference is persistence.
- SSP-CP-002 Derive/guardrail `when` expressions are CEL with the variables `params`, `tenant`, `apm`, `lob`, `principal`; templates `{{ }}` are Go `text/template` restricted to field access (no functions besides `lower`, `upper`, `join`).
- SSP-CP-003 `render.RootModule(tenant, desiredSet)` is deterministic (sorted keys, canonical JSON); its output hash is the generation content hash; the same package produces `/orders/{id}/code`.
- SSP-CP-004 Reconciler workflow uses `workflow.Await` on a queue in workflow state; signals are deduplicated by `spec_hash`; `continue-as-new` carries the pending queue.
- SSP-CP-005 The API never calls Temporal synchronously on the request path except `SignalWithStart`/`ExecuteWorkflow` with a 2 s timeout; reads use Postgres.
- SSP-CP-006 Assistant tools call handler functions directly with the caller's principal (no HTTP loopback), so authorization is identical.
- SSP-CP-007 All external clients (ServiceNow, CMDB, Infoblox, IAM) sit behind interfaces with twin implementations selected by `SSP_INTEGRATIONS_MODE=twin|live`.
- SSP-CP-008 Secrets never enter workflow histories: activities receive references, resolve inside the activity, and return only receipts.
