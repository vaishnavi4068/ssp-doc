# 13 — Temporal Workflow Specification

All workflows run in the platform's self-hosted Temporal (D-11), namespace `ssp`. Workflow code lives in `ssp-cp/internal/workflows`; control-plane activities in `ssp-cp/internal/activities`; Terraform and post-build activities in `ssp-workers`.

## 1. Namespaces, task queues, workers

| Task queue | Worker binary | Repo | Activities / workflows | Scaling |
|---|---|---|---|---|
| `ssp-control` | `ssp-cp/cmd/worker` | ssp-cp | All workflows; DB, GCS, catalog, policy, ServiceNow, CMDB activities | HPA on CPU; 2–6 replicas |
| `tf-runs-<lob>` (one per LOB; `tf-runs-default` for POC) | `ssp-workers/cmd/tf-worker` | ssp-workers | `RunTerraform` (creates and watches K8s Jobs) | 1–N replicas; `MaxConcurrentActivityExecutionSize` = 10 per replica; KEDA on task-queue backlog later |
| `post-build` | `ssp-workers/cmd/postbuild-worker` | ssp-workers | Integration activities (CMDB, backup, monitoring, notify, Infoblox) | HPA |
| `drift` | `ssp-workers/cmd/drift-worker` | ssp-workers | `RunTerraform(kind=refresh)` reuse + `InventoryAssets` | HPA |

- SSP-WF-001 Namespace `ssp` with retention 30 days; `ssp-sandbox` for tests. Search attributes: `TenantId` (Keyword), `LobId` (Keyword), `OrderId` (Keyword), `RunKind` (Keyword), `State` (Keyword).
- SSP-WF-002 Workflow IDs are deterministic: `order:<order_id>`, `tenant:<tenant_id>` (reconciler), `drift:<tenant_id>`, `import:<import_id>`, `release:<service_id>:<version>`. Reuse policy `RejectDuplicate` for orders; reconcilers use `continue-as-new` every 500 cycles or 24 h.
- SSP-WF-003 Every activity has explicit `StartToCloseTimeout`, `HeartbeatTimeout` where > 1 min, and a retry policy with `NonRetryableErrorTypes` for validation and policy errors.
- SSP-WF-004 Workflows never read the DB directly; all I/O is in activities. Workflow inputs are IDs, never large payloads.

## 2. `OrderWorkflow(order_id)`

```
start ─► LoadOrder ─► Approve ─► [gate loop] ─► SignalReconciler(tenant_id, approved_spec) ─► await ResultSignal ─► PostBuild (child) ─► Finalize
```

| Step | Activity / child | Timeout | Notes |
|---|---|---|---|
| LoadOrder | `LoadOrder` | 10 s | Reads order + catalog version |
| Approve | `ComputeApproval` | 60 s | Re-runs preflight logic server-side, writes `approved_spec`, transitions `requested→approved`, emits events. Deny → `rejected`, workflow completes. |
| Gate loop | signals `CRApproved`, `OwnerSignedOff`, `Cancel`; timer 14 d | — | If `gates` contains `cr_required`: `CreateChangeRequest` activity (ServiceNow), then wait for signal or `PollCR` every 10 min. Owner sign-off waits for signal from `POST /signoff`. Timeout → `cancelled` with reason. |
| Hand-off | `SignalWithStart TenantReconciler(tenant_id)` with `Enqueue{order_id, spec_hash, isolation}` | — | Transitions `approved→expected` when the reconciler acknowledges inclusion in a generation (signal `Included{generation}`). |
| Await result | signal `RunResult{run_id, outcome, outputs}` | 6 h then escalate | On `failed`: order → `failed`, event with run error; operator may retry (reconciler re-queues). |
| PostBuild | child `PostBuildWorkflow(order_id)` | per step | Steps from ServiceSpec `postBuild`. |
| Finalize | `MarkObserved` | 10 s | Upserts `resource_instance` (state observed), order → `observed`, notify buyer. |

- SSP-WF-010 `Cancel` signal is honoured until `Included`; after that the order can only be reversed by a `decommission` order.
- SSP-WF-011 `ComputeApproval` is the only place that writes `approved_spec`; it is idempotent on `(order_id)`.

## 3. `TenantReconciler(tenant_id)` — entity workflow

Owns the single state file for a tenant boundary (D-08). One instance per tenant, started on first order, lives forever via continue-as-new.

```
loop:
  wait for Enqueue signals (or timer)                      ── batch window 20 s (SSP-PROD-052)
  if paused(global|lob|tenant) or platform SA disabled → wait, re-check every 60 s
  gen = AllocateGeneration(tenant_id, batch)               ── Postgres advisory lock; writes tenant_generation
  Render(tenant_id, gen)                                   ── desired set → expected/<gen>/ in LOB bucket
  signal each order: Included{gen}
  run = CreateRun(kind=plan)  →  RunTerraform(run)         ── on tf-runs-<lob>; Job tf-<hash>
  PlanGate(run)                                            ── only batch instances touched; plan-stage OPA allow; no undeclared destroy/replace
  if gate fails → mark run failed, orders failed, alert; continue loop
  run2 = CreateRun(kind=apply) → RunTerraform(run2)        ── applies the saved plan file from the plan run
  CaptureObserved(run2)                                    ── parse state → resource_instance outputs, last_observed_at
  signal each order: RunResult{...}
  schedule DriftScan(tenant_id) in 10 min (debounced)
```

| Activity | Queue | Timeout | Heartbeat | Idempotency |
|---|---|---|---|---|
| `AllocateGeneration` | ssp-control | 30 s | — | `(tenant_id, spec_hashes)` |
| `Render` | ssp-control | 2 min | — | content-addressed output; re-render is a no-op if identical |
| `CreateRun` | ssp-control | 10 s | — | `(tenant_id, generation, kind, attempt)` |
| `RunTerraform` | tf-runs-<lob> | 90 min (plan 30 min) | 30 s | Job name `tf-<sha256(run_id:attempt)[:20]>`; re-attach if exists |
| `PlanGate` | ssp-control | 1 min | — | pure |
| `CaptureObserved` | ssp-control | 2 min | — | `(run_id)` |

- SSP-WF-020 The reconciler is the only writer to a tenant's `expected/` and the only issuer of runs for that tenant; Terraform's own GCS lock is a second safety net, not the primary serialization.
- SSP-WF-021 A `decommission` or `upgrade` spec with `isolation: true` is never batched with other specs.
- SSP-WF-022 `apply` uses the plan file produced by the `plan` run (`terraform apply plan.tfplan`) so what was gated is what is applied; the plan file is stored in the run artifacts and is valid for 24 h.
- SSP-WF-023 If `RunTerraform` fails with a state lock error, the reconciler waits 2 min and retries up to 5 times before failing the generation and alerting (someone is holding the lock out of band).
- SSP-WF-024 Queue metrics (`ssp_reconciler_queue_depth`, `ssp_reconciler_queue_oldest_seconds`) are emitted per tenant and LOB via a `QueryHandler` polled by the metrics exporter.

## 4. `PostBuildWorkflow(order_id)`

- SSP-WF-030 Steps execute sequentially in ServiceSpec order; each step is an activity on `post-build` with `StartToCloseTimeout` 10 min, retry with exponential backoff up to 24 h, then `escalate` activity (ticket to the owning agent team) and the order stays `observed (post-build incomplete)`.
- SSP-WF-031 Standard steps and their activities: `cmdb.register` (create/update CI; receipt = CI sys_id), `backup.enroll`, `monitoring.onboard`, `notify.team` (email/Teams), `dns.register` (Infoblox), `firewall.request` (opens request; does not wait).
- SSP-WF-032 Steps declare `idempotencyKey` templates (e.g. `cmdb:<resource_instance_id>`); receipts are stored in `order_event.detail` and in `resource_instance.outputs.post_build`.

## 5. `DriftScanWorkflow(tenant_id)` (scheduled)

- SSP-WF-040 Temporal Schedule per tenant, every 6 h with jitter; also triggered 10 min after any apply. Skips if a run is in progress.
- SSP-WF-041 `RunTerraform(kind=refresh)` performs `terraform plan -refresh-only -json`; `ClassifyDrift` maps resource changes to `benign|config|missing` using per-service allowlists; `InventoryAssets` (Cloud Asset Inventory) finds `unmanaged` resources of catalog-known types in the boundary.
- SSP-WF-042 Findings are upserted (`drift_finding`), the resource marked `drifted`, notifications sent. Auto-revert only when ServiceSpec `drift.autoRevert: true` and no break-glass window: enqueue a `reconcile` to the TenantReconciler.

## 6. `ImportWorkflow(import_id)` (used by `ssp-migrate`)

```
Inventory ─► SuggestMapping ─► await MappingConfirmed ─► GenerateImportBlocks ─► DryRun (plan with import blocks; expect 0 changes) ─► await ExecuteApproved ─► Execute (apply import) ─► CreateInstances ─► Done
```

- SSP-WF-050 Dry-run must show only `import` actions and zero `update/destroy`; otherwise the workflow stops in `mapping` with the diff for the operator.
- SSP-WF-051 Legacy 1.0 projects (multi-app) import into the single state of that project; each resource instance carries its own `apm_id` label from the mapping; the tenant's `apm_id` is the primary owner chosen by the operator.
- SSP-WF-052 Execution runs as an isolated generation on the TenantReconciler (so the lock discipline holds).

## 7. `ReleaseWorkflow(service_id, version)` (module upgrade waves)

- SSP-WF-060 Waves are defined by the operator: `canary` (named tenants), then LOBs in order, each with `soak` duration and `maxFailures`. For each tenant in a wave, create an `upgrade` order (channel `release`) and wait for Observed; stop the wave on `maxFailures`.
- SSP-WF-061 Upgrade orders carry `isolation: true` and are subject to the plan gate; any destroy/replace not declared in the module CHANGELOG fails the wave.

## 8. Signals, queries, errors

| Workflow | Signals | Queries |
|---|---|---|
| OrderWorkflow | `CRApproved{cr_id}`, `OwnerSignedOff{by}`, `Cancel{by, reason}`, `Included{gen}`, `RunResult{...}` | `Status` |
| TenantReconciler | `Enqueue{order_id, spec_hash, isolation}`, `Pause`, `Resume`, `Retry{generation}`, `ForceReconcile` | `Queue`, `Current` |
| DriftScan | `RunNow` | `Last` |
| Import | `MappingConfirmed`, `ExecuteApproved`, `Abort` | `Status` |
| Release | `Advance`, `Halt` | `Progress` |

- SSP-WF-070 Error taxonomy: `ValidationError`, `PolicyDenied`, `EntitlementError` (non-retryable); `TransientError` (retryable); `TerraformError{phase, exit_code, summary}` (retryable only for `init`/network classes); `LockError` (retry with backoff).
- SSP-WF-071 Replay tests: recorded histories for each workflow are stored in `ssp-cp/internal/workflows/testdata/histories/`; CI runs `replayer.ReplayWorkflowHistory` for all; any change that breaks replay must use `workflow.GetVersion`.
