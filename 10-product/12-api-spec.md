# 12 — Control-Plane API Specification (Go, `ssp-cp`)

OpenAPI 3.1 contract: `12-openapi.yaml` (same folder). The Go server is generated from it; the contract is edited first, never the handlers.

## 1. Stack (binding)

| Concern | Choice | Notes |
|---|---|---|
| Language | Go 1.23+ | Single module `github.com/vaishnavi4068/ssp-cp` |
| HTTP | `net/http` + `chi` router | Middleware chain: request id, OTel, auth, entitlement, rate limit |
| Codegen | `oapi-codegen` (strict server + types) | `make generate` regenerates `internal/api/gen` |
| DB | `pgx/v5` + `sqlc`; migrations with `goose` | `internal/store` |
| Workflows | Temporal Go SDK (`go.temporal.io/sdk`) | Namespace `ssp`; task queues in `13-workflows-spec.md` |
| Policy | OPA embedded (`github.com/open-policy-agent/opa/rego`) for request stage; bundles loaded from the catalog bucket | `internal/policy` |
| Validation | `santhosh-tekuri/jsonschema/v6` against the service request schema | `internal/catalog` |
| Config | env vars only; no config files in images | `SSP_*` prefix |
| Logging / tracing | `log/slog` JSON + OpenTelemetry (OTLP to the cluster collector) | |
| Auth | JWT (JWKS from IdP via gateway) + Workload Identity for internal callers | `internal/auth` |

SSP-API-001 All endpoints live under `/v1`. SSP-API-002 Every mutating endpoint requires `Idempotency-Key`; replays return the original response with `Idempotent-Replayed: true`. SSP-API-003 Errors use RFC 9457 problem details with a stable `type` URI per error code (`https://ssp/errors/<code>`). SSP-API-004 All list endpoints paginate with `page_token` / `page_size` (max 200). SSP-API-005 Every response carries `X-Request-Id`; every audit event stores it.

## 2. Endpoint catalogue

### Catalog
| Method | Path | Persona | Purpose |
|---|---|---|---|
| GET | `/v1/catalog/services` | any | List enabled services; filter `cloud`, `category`, `q`; includes "frequent for you" ordering when `sort=frequent` |
| GET | `/v1/catalog/services/{service_id}` | any | Latest version: ServiceSpec summary, request schema, UI template, guardrails preview, pricing, docs link |
| GET | `/v1/catalog/services/{service_id}/versions/{version}` | any | A specific bundle version |

### Destinations and context
| GET | `/v1/destinations` | buyer | Tenant boundaries the caller is entitled to, grouped by cloud, with APM, tier, data class, env |
| GET | `/v1/destinations/{tenant_id}/context` | buyer | The context object used for defaults: apm, tier, data_class, lob, quotas, budget headroom |

### Orders
| POST | `/v1/orders/preflight` | buyer | Body: `{tenant_id, service_id, version?, kind, resource_instance_id?, params}` → `PreflightResult` (approved_params, guardrails, policy, estimate, code{terraform, cli}, gates, preview_hash, valid_until) |
| POST | `/v1/orders` | buyer | Body: preflight input + `preview_hash` → 202 `Order` (state `requested`); 409 `preview_stale` if hash differs; 422 validation; 403 entitlement |
| GET | `/v1/orders` | buyer/operator | Filter `tenant_id`, `state`, `mine=true` |
| GET | `/v1/orders/{order_id}` | buyer/operator | Order + approved spec (if any) + latest run summary |
| GET | `/v1/orders/{order_id}/events` | buyer/operator | SSE stream of `order_event`s (`Last-Event-ID` resume) |
| GET | `/v1/orders/{order_id}/code` | buyer | `{terraform, cli, module_source, version}` equivalent code (D-17) |
| POST | `/v1/orders/{order_id}/cancel` | buyer | Allowed in `requested`/`approved` before a run starts |
| POST | `/v1/orders/{order_id}/signoff` | app_owner | Clears `owner_signoff_pending` |

### Resources
| GET | `/v1/tenants/{tenant_id}/resources` | buyer/operator | Resource instances with state, outputs, last observed |
| GET | `/v1/resources/{resource_instance_id}` | buyer/operator | Detail incl. drift findings, orders history, code |
| GET | `/v1/tenants/{tenant_id}/drift` | buyer/operator | Open drift findings |

### Runs (read for buyers, write for operators)
| GET | `/v1/runs?tenant_id=` | buyer/operator | Runs for a tenant |
| GET | `/v1/runs/{run_id}` | buyer/operator | Run detail incl. plan summary |
| GET | `/v1/runs/{run_id}/logs` | buyer/operator | Redacted log (text/plain, range requests) |
| POST | `/v1/runs/{run_id}/retry` | operator | Signals the reconciler to retry the failed generation |

### Operator controls (control room)
| GET | `/v1/ops/fleet` | operator | Counts by state, queue depth and age per LOB, worker health, Temporal namespace health, kill-switch status |
| GET | `/v1/ops/tenants?lob=&paused=&drifted=` | operator | Tenant table |
| POST | `/v1/ops/controls/pause` | operator | `{scope: global|lob:<id>|tenant:<id>, reason}` |
| POST | `/v1/ops/controls/resume` | operator | same |
| POST | `/v1/ops/controls/killswitch` | operator (2-person) | Disables the Platform SA via IAM; requires `confirm: "<scope>"` and a second approver token |
| POST | `/v1/ops/tenants/{tenant_id}/reconcile` | operator | Forces a reconcile run |
| POST | `/v1/ops/tenants/{tenant_id}/drift-scan` | operator | Forces a drift scan |
| POST | `/v1/ops/tenants/{tenant_id}/break-glass` | operator | `{until, incident}` |
| GET | `/v1/ops/releases` / POST `/v1/ops/releases/{service_id}/{version}/waves` | operator | Module upgrade waves |
| GET | `/v1/ops/policy/impact?bundle=` | security | Policy-impact replay result |

### Migration (used by `ssp-migrate`)
| POST | `/v1/imports` | operator | `{tenant_id | legacy_project, scope}` → import job (inventory) |
| GET | `/v1/imports/{import_id}` | operator | Inventory, mapping status, dry-run result |
| PUT | `/v1/imports/{import_id}/mapping` | operator | Resource → service mapping decisions |
| POST | `/v1/imports/{import_id}/dry-run` | operator | Generates `import` blocks, runs plan, expects zero changes |
| POST | `/v1/imports/{import_id}/execute` | operator | Executes the import run; creates resource instances and orders of kind `import` |

### Assistant (Sidekick and operator chat)
| POST | `/v1/assistant/conversations` | any | New conversation bound to the caller and an optional tenant |
| POST | `/v1/assistant/conversations/{id}/messages` | any | SSE: tokens, tool events, cards (`preflight_card`, `status_card`, `citation`) |
| GET | `/v1/assistant/conversations/{id}` | any | Transcript |

### Catalog admin and health
| POST | `/v1/admin/catalog/reload` | operator | Re-read `index.json` from the catalog bucket (also triggered by Pub/Sub) |
| GET | `/healthz`, `/readyz`, `/metrics` | internal | Liveness, readiness (DB + Temporal + catalog loaded), Prometheus |

## 3. Behavioural requirements

- SSP-API-010 `preflight` is pure: no writes, deterministic for the same input and catalog version; result cached 60 s by `preview_hash`.
- SSP-API-011 `preview_hash = sha256(canonical_json(tenant_id, service_id, version, kind, resource_instance_id, approved_params, guardrails, policy.bundle_digest, pricing_version))`.
- SSP-API-012 `POST /orders` validates entitlement, re-runs preflight server-side, compares hashes, inserts order + event in one transaction, then starts `OrderWorkflow(order_id)` with `WorkflowIDReusePolicy: RejectDuplicate` using workflow id `order:<order_id>`.
- SSP-API-013 Ops endpoints require persona `operator`; `killswitch` requires two distinct operators within 10 minutes (second call carries `approval_token` from the first).
- SSP-API-014 Logs endpoint streams from the run artifact in GCS; secrets are redacted by the runner before upload, and the API applies a second redaction pass (regex set from `policy_bundle`).
- SSP-API-015 Rate limits: 60 preflights/min per principal, 10 orders/min per principal, 600 reads/min.
- SSP-API-016 The `code` endpoint renders exactly the module block the reconciler would render (same renderer package), plus a `gcloud`/`aws`/`az` CLI approximation labelled "approximate".
- SSP-API-017 All timestamps RFC 3339 UTC; money as `{currency: "USD", amount: "123.45"}` strings.

## 4. Package layout (`ssp-cp`)

```
cmd/api/main.go                     HTTP server
cmd/worker/main.go                  Temporal worker for workflows + control-plane activities (not Terraform)
cmd/catalogctl/main.go              validate/publish catalog bundles
internal/api/gen/                   oapi-codegen output (do not edit)
internal/api/handlers/              strict-server implementations per tag
internal/auth/                      JWT, personas, entitlements
internal/catalog/                   bundle loader, schema validation, derive rules, pricing
internal/policy/                    OPA request-stage evaluation, bundle cache, impact replay
internal/render/                    desired set → main.tf.json, backend.hcl, code view
internal/store/                     sqlc queries, migrations
internal/workflows/                 OrderWorkflow, TenantReconciler, DriftScan, PostBuild, Import, Release
internal/activities/                control-plane activities (DB, GCS, ServiceNow, CMDB clients)
internal/assistant/                 gateway to CLM + tool-calling model; tools = this API
internal/events/                    SSE hub backed by Postgres LISTEN/NOTIFY
pkg/ssp/                            shared types used by ssp-workers and apps
```
