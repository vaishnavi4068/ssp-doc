# 21 — Control Room Specification (`ssp-control-room`, new repo)

The operator console for the platform team. Same design system as the storefront (tokens from `experiences/portal-ui/16-ui-spec.md`), different information architecture: fleet first, then drill-down, with an operator agent chat that turns instructions into confirmed platform actions. It uses only `ssp-cp` `/v1/ops/*`, `/v1/runs/*`, `/v1/imports/*` and `/v1/assistant/*` endpoints; it has no database of its own.

## 1. Personas and access

Operators (full), security reviewers (policy and audit views, T3 approvals), auditors (read-only). Access via OIDC group claims mapped to personas by `ssp-cp` (SSP-PROD-101). SSP-CR-001 Every action in the control room is an API call that `ssp-cp` audits; the UI adds nothing privileged.

## 2. Screens

| Route | Screen | Content | Key actions |
|---|---|---|---|
| `/` | **Fleet** | Tiles: orders by state (last 24 h / 7 d), runs in progress, queue depth and oldest age per LOB, worker health per task queue, Temporal namespace health, drift open, kill-switch status banner (red if Platform SA disabled or global pause) | Pause/resume global or LOB (reason required), open Temporal UI |
| `/tenants` | **Tenants** | Table: tenant, LOB, APM, env, paused, queue depth, last run, drift open, break-glass | Pause/resume tenant, force reconcile, force drift scan, set break-glass |
| `/tenants/[id]` | **Tenant detail** | Desired set (resource instances + versions), generations timeline, runs, drift findings, orders, state bucket path, tenant SA | Retry generation, open run logs, open resource |
| `/runs` and `/runs/[id]` | **Runs** | Live table; detail: plan summary, policy result, log viewer (SSE tail, redacted), artifacts links, Job name, workflow id link | Retry, cancel (if running), download plan.json |
| `/orders` | **Orders** | Cross-tenant order table with gates (CR pending, sign-off pending), stuck detection (> SLO) | Open order, nudge (re-poll CR), cancel with reason |
| `/drift` | **Drift board** | Findings by class and age, grouped by LOB; `unmanaged` list from asset inventory | Mark accepted, enqueue reconcile (if autoRevert allowed), create adopt task |
| `/releases` | **Module releases** | Catalog versions, tenants per version, wave planner (canary → LOBs), wave progress, failures | Create waves, advance, halt |
| `/policy` | **Policy** (security) | Bundles and digests, policy-impact replay results (newly denied / allowed with examples), T3 queue | Approve impact review |
| `/catalog` | **Catalog admin** | Services, versions, deprecations, publish status, reload | Deprecate, set successor, reload index |
| `/audit` | **Audit** | Searchable audit events; export CSV for a time range | — |
| `/kill-switch` | **Kill switch** | Current state of Platform SA, scope pauses; two-person flow (first operator requests, second confirms within 10 min) | Disable / re-enable Platform SA |
| `/chat` (also a right slide-over everywhere) | **Operator chat** | See `23-operator-agent-chat-spec.md` | — |

## 3. Requirements

- SSP-CR-010 Fleet metrics refresh every 15 s via `/v1/ops/fleet`; run logs stream via SSE; nothing is polled faster than 5 s.
- SSP-CR-011 Every destructive or scope-wide action (pause global/LOB, kill switch, halt wave, cancel run) requires a typed reason and shows the blast radius (tenants affected, runs in flight) before confirm.
- SSP-CR-012 Kill switch requires two distinct operators (API-enforced, SSP-API-013); the UI shows the pending approval with a countdown.
- SSP-CR-013 Links to Temporal Web UI are deep links (`/namespaces/ssp/workflows/<id>`) behind the same SSO; the control room never embeds Temporal UI in an iframe.
- SSP-CR-014 Stuck detection: an order in `approved` with gate `none` for > 10 min, or a run `running` beyond its timeout, is highlighted and counted in a "needs attention" tile.
- SSP-CR-015 The control room renders fine when `ssp-cp` is degraded: cached last fleet snapshot with an age badge; actions disabled.
- SSP-CR-016 No tenant-owned secrets or raw state are ever displayed; outputs shown are the non-secret outputs recorded in `resource_instance.outputs`.

## 4. Monitoring status (what "status" means here)

Three layers, one source of truth (events and metrics from `ssp-cp` and workers):

1. **Order/run status** — event stream per order (buyer and operator see the same).
2. **Fleet status** — aggregates from Postgres plus Temporal visibility queries (`ListWorkflow` with search attributes) plus worker health (task queue pollers).
3. **Platform health** — Prometheus metrics (`30-infra/36-observability.md`) rendered in Grafana; the control room links to dashboards rather than re-implementing them, except the fleet tiles.

## 5. Repo structure

```
ssp-control-room/
├── app/(shell)/layout.tsx          top bar (env badge, search, chat), left nav (Fleet, Tenants, Runs, Orders, Drift, Releases, Policy, Catalog, Audit, Kill switch)
├── app/… one folder per route above
├── components/ops/                 FleetTile, QueueGauge, RunLogViewer (SSE), BlastRadiusDialog, TwoPersonConfirm
├── lib/api/                        generated client from 12-openapi.yaml (ops + runs + imports + assistant tags)
├── packages/ui → git subtree or npm package @ssp/ui from ssp-ui (shared tokens/components)
└── tests/e2e/
```

Deployment: namespace `ssp-control-room`, internal ingress only, operator group required at the gateway.
