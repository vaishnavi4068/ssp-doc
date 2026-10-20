# 22 — Migration App Specification (`ssp-migrate`, new repo)

Moves existing cloud resources, provisioned by Taxi or by hand, into the SSP construct: one tenant boundary, one tenant SA, one state file, resources expressed as catalog services. The core platform is designed for the 2.0 layout (D-09); this app is the **translation shim** for everything else, including one-time state import.

## 1. What migration produces

For a tenant boundary (project today; account/subscription later):

1. Tenant record in `ssp-cp` (LOB, APM, tier, data class, env, tenant SA, state prefix).
2. Resource instances in the desired set, each bound to a catalog service and version.
3. A Terraform state file in the LOB bucket containing exactly those resources, created by `import` blocks, with a **zero-change** plan afterwards.
4. Orders of kind `import` (one per resource instance) in `observed`, so history and audit start at migration.
5. A report of what was skipped or flagged (resources with no catalog service, non-conforming configurations, shared 1.0 resources).

## 2. Journey (wizard)

| Step | Screen | What happens | API |
|---|---|---|---|
| 1 | **Select source** | Pick cloud, boundary (project id), legacy layout (1.0 shared / 2.0), and scope filter (labels, services) | `POST /v1/imports` |
| 2 | **Inventory** | Cloud Asset Inventory listing filtered to catalog-known resource types; grouped by suggested service; confidence score; unknown types listed separately | `GET /v1/imports/{id}` (state `inventorying` → `mapping`) |
| 3 | **Map** | For each asset: decision `import | skip | flag`, service id, stable `name`, params pre-extracted from the live resource (reverse-mapped through the module's variable schema), APM owner (for 1.0 multi-app projects, per resource) | `PUT /v1/imports/{id}/mapping` |
| 4 | **Onboard tenant** | If the boundary is not yet a tenant: creates tenant SA, grants the Platform SA token-creator, grants the SA its state prefix, writes the tenant record (this is the per-project SA isolation work Dwayne is taking to Raju / Durant; the app automates the platform side) | internal workflow step |
| 5 | **Dry run** | Generates `import { to = module.<name>.<type>.<addr>; id = "<cloud id>" }` blocks plus the rendered root module; runs plan; shows diff. Must be zero updates/destroys | `POST /v1/imports/{id}/dry-run` |
| 6 | **Reconcile differences** | For each non-zero diff: choose *adopt live value into params* (changes the order), *accept planned change* (will be applied; needs CR in prod), or *skip asset* | loop to step 3 |
| 7 | **Execute** | Isolated generation on the TenantReconciler: apply import, capture observed, create resource instances and `import` orders; post-build steps run (CMDB reconcile) | `POST /v1/imports/{id}/execute` |
| 8 | **Report** | Summary, skipped/flagged list with reasons, link to the tenant in the control room; export JSON/CSV | `GET /v1/imports/{id}` |

## 3. Requirements

- SSP-MIG-001 Inventory uses read-only credentials (Cloud Asset Inventory viewer via the Platform SA impersonating a read-only inventory SA); nothing in steps 1–6 writes to the cloud.
- SSP-MIG-002 Reverse mapping: each `ssp-module-<service>` ships `import/mapping.yaml` (asset type → module address template, attribute → param extraction) so the app has no per-service code.
- SSP-MIG-003 A resource whose live configuration violates a MUST guardrail cannot be imported as-is; the wizard offers `accept planned change` (brings it to standard; gated like a `change` order) or `flag` (recorded, excluded, assigned to the app owner).
- SSP-MIG-004 1.0 shared projects: the project becomes one tenant with a primary APM; every resource instance carries its own `apm_id` label; the report lists resources per APM so owners can later split by creating new 2.0 projects and moving workloads (the platform never moves data).
- SSP-MIG-005 Execution is idempotent and resumable: import blocks already applied are skipped on retry; a failed execution leaves the state file consistent (Terraform import is per-resource).
- SSP-MIG-006 Scale: a project with 10,000 resources imports in batches of 200 import blocks per run to keep plan time bounded; progress is shown per batch.
- SSP-MIG-007 Taxi hand-off: when Taxi still manages a resource, the wizard shows the Taxi record (from the inventory step, via label `managed_by=taxi`) and requires explicit "take over from Taxi" acknowledgement; a post-build step marks the Taxi record read-only (integration pending Norm's inventory).
- SSP-MIG-008 Every import run is a normal run (artifacts, logs, policy at plan stage) visible in the control room.

## 4. Future builds and migrations inside the construct

The same app covers two more flows, both reusing the wizard:

- **Adopt** (`kind: adopt`): a resource created out of band inside an already-managed tenant (found as `unmanaged` drift) is mapped and imported; the drift finding is resolved `adopted`.
- **Re-platform** (`kind: upgrade` with a source/target service pair): e.g., self-managed Postgres VM → Cloud SQL service. The app only orchestrates *provision target → owner migrates data → decommission source* as linked orders with a checklist; data movement is never automatic.

## 5. Repo structure

```
ssp-migrate/
├── app/(wizard)/[importId]/{source,inventory,map,onboard,dry-run,reconcile,execute,report}/page.tsx
├── components/migrate/              InventoryTable (virtualized), MappingEditor (schema-aware param form via @ssp/form-renderer), DiffViewer (plan JSON), BatchProgress
├── lib/api/                         generated client (imports + tenants + runs tags)
├── lib/reverse-map/                 applies module import/mapping.yaml to asset JSON → params
└── tests/fixtures/assets/           sanitized Cloud Asset Inventory exports (1.0 and 2.0 projects)
```

Deployment: namespace `ssp-migrate`, operator persona only in Phase 2; app owners get a read-only "my migration" view in Phase 3.
