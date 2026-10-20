# 11 — Domain Model and Control-Plane Schema (Postgres)

Postgres holds Requested and Approved, pointers to Expected/Observed objects, catalog index, entitlements and audit. It never holds secrets or Terraform state (D-03, D-06).

## 1. Entity overview

```
lob ──< tenant ──< resource_instance >── service_version
 │         │              │
 │         │              └──< order ──< order_event
 │         │                     │
 │         │                     └── approved_spec ──< run ──< run_artifact
 │         └──< entitlement >── principal
 └── state_bucket
catalog_service ──< service_version ──< pricing_rule
policy_bundle, drift_finding, control_flag, audit_event
```

## 2. DDL (migration 0001)

```sql
-- Migration tool: goose or atlas; forward-only. Extension for ULIDs is not required; IDs are text.
create schema ssp;
set search_path to ssp;

create type cloud as enum ('gcp','aws','azure');
create type tenant_kind as enum ('project','account','subscription');
create type order_kind as enum ('create','change','decommission','upgrade','adopt','import');
create type order_state as enum ('requested','approved','expected','observed','rejected','cancelled','failed');
create type approval_gate as enum ('none','cr_pending','owner_signoff_pending');
create type run_kind as enum ('plan','apply','refresh','import','destroy');
create type run_state as enum ('queued','running','succeeded','failed','cancelled');
create type drift_class as enum ('benign','config','missing','unmanaged');

create table lob (
  lob_id            text primary key,                 -- e.g. 'pbm', 'retail'
  name              text not null,
  cloud             cloud not null,
  boundary_ref      text not null,                    -- host project id / OU id / management group id
  state_bucket      text not null,                    -- gs://ssp-state-<lob> | s3://... | https://...blob...
  cmek_key          text not null,                    -- KMS key resource name for the bucket
  created_at        timestamptz not null default now()
);

create table tenant (
  tenant_id         text primary key,                 -- '<cloud>:<boundary id>' e.g. 'gcp:pay-prod-7a1c'
  lob_id            text not null references lob,
  cloud             cloud not null,
  kind              tenant_kind not null,
  boundary_ref      text not null,                    -- project id / account id / subscription id
  apm_id            text not null,                    -- 2.0 layout: one APM per tenant
  tier              smallint not null check (tier between 1 and 4),
  data_class        text not null,                    -- PHI|PII|CONF|INTERNAL|PUBLIC
  cost_center       text not null,
  env               text not null,                    -- prod|nonprod|sandbox
  tenant_sa         text not null,                    -- ssp-tenant@<project>.iam.gserviceaccount.com / role arn / client id
  state_prefix      text not null,                    -- '<boundary_ref>/' inside the LOB bucket
  paused            boolean not null default false,
  break_glass_until timestamptz,
  created_at        timestamptz not null default now(),
  unique (cloud, boundary_ref)
);

create table principal (
  principal_id      text primary key,                 -- OIDC subject
  email             text not null unique,
  display_name      text,
  personas          text[] not null default '{buyer}' -- buyer|app_owner|operator|security|auditor
);

create table entitlement (
  principal_id      text references principal,
  apm_id            text not null,
  role              text not null check (role in ('buyer','app_owner')),
  primary key (principal_id, apm_id)
);

create table catalog_service (
  service_id        text primary key,                 -- 'gcp.spanner-instance'
  cloud             cloud not null,
  display_name      text not null,
  category          text not null,                    -- database|storage|compute|network|messaging
  adr_id            text not null,                    -- E-SPAN-0001
  owner_mailbox     text not null,
  enabled           boolean not null default true
);

create table service_version (
  service_id        text references catalog_service,
  version           text not null,                    -- semver of the catalog bundle
  bundle_uri        text not null,                    -- gs://ssp-catalog-<env>/gcp.spanner-instance/1.2.0/
  module_source     text not null,                    -- gcs::https://.../ssp-module-spanner-1.2.0.zip
  spec              jsonb not null,                   -- ServiceSpec (validated)
  request_schema    jsonb not null,
  ui_template       jsonb not null,
  pricing           jsonb not null,
  policy_digest     text not null,                    -- sha256 of the Rego bundle
  published_at      timestamptz not null default now(),
  deprecated        boolean not null default false,
  primary key (service_id, version)
);

create table "order" (
  order_id          text primary key,                 -- ord_ULID
  idempotency_key   text not null unique,
  kind              order_kind not null,
  state             order_state not null default 'requested',
  gate              approval_gate not null default 'none',
  tenant_id         text not null references tenant,
  service_id        text not null,
  service_version   text not null,
  resource_instance_id text,                          -- set for change/decommission/upgrade/adopt
  requested_by      text not null references principal,
  requested_params  jsonb not null,                   -- schema-valid, no secrets
  preview_hash      text not null,
  channel           text not null,                    -- ui|api|chat|migrate|release
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  foreign key (service_id, service_version) references service_version
);
create index on "order" (tenant_id, state);
create index on "order" (requested_by, created_at desc);

create table approved_spec (
  order_id          text primary key references "order",
  approved_params   jsonb not null,                   -- requested + injected guardrails
  guardrails        jsonb not null,                   -- [{id, field, mode, value, source}]
  policy_decision   jsonb not null,                   -- {bundle_digest, result, rules:[...], warnings:[...]}
  estimate          jsonb not null,                   -- {monthly_usd, lines:[...], pricing_version}
  cr_id             text,                             -- ServiceNow CHG number when required
  owner_signoff_by  text references principal,
  approved_by       text not null,                    -- 'system' or principal_id
  spec_hash         text not null,
  approved_at       timestamptz not null default now()
);

create table resource_instance (
  resource_instance_id text primary key,              -- ri_ULID
  tenant_id         text not null references tenant,
  service_id        text not null,
  service_version   text not null,                    -- module version currently applied
  name              text not null,                    -- stable name used as module block key
  params            jsonb not null,                   -- current approved params
  state             text not null default 'expected', -- expected|observed|drifted|decommissioning|removed
  outputs           jsonb,                            -- non-secret outputs
  last_observed_at  timestamptz,
  created_by_order  text references "order",
  created_at        timestamptz not null default now(),
  unique (tenant_id, name)
);

create table tenant_generation (
  tenant_id         text references tenant,
  generation        bigint not null,
  expected_uri      text not null,                    -- gs://.../<tenant>/expected/<generation>/
  spec_hashes       text[] not null,                  -- approved specs included
  created_at        timestamptz not null default now(),
  primary key (tenant_id, generation)
);

create table run (
  run_id            text primary key,                 -- run_ULID
  tenant_id         text not null references tenant,
  generation        bigint not null,
  kind              run_kind not null,
  state             run_state not null default 'queued',
  attempt           int not null default 1,
  job_name          text not null,                    -- tf-<hash>
  workflow_id       text not null,
  order_ids         text[] not null,
  plan_summary      jsonb,                            -- {add, change, destroy, replace, resources:[...]}
  started_at        timestamptz,
  finished_at       timestamptz,
  error             text,
  artifacts_uri     text                              -- gs://.../<tenant>/runs/<run_id>/
);
create index on run (tenant_id, started_at desc);

create table order_event (
  event_id          bigserial primary key,
  order_id          text not null references "order",
  at                timestamptz not null default now(),
  actor             text not null,                    -- principal_id | system | workflow:<id>
  from_state        order_state,
  to_state          order_state,
  type              text not null,                    -- created|approved|gate_waiting|gate_cleared|run_started|run_finished|post_build_step|delivered|failed|...
  detail            jsonb
);
create index on order_event (order_id, event_id);

create table drift_finding (
  finding_id        text primary key,
  tenant_id         text not null references tenant,
  resource_instance_id text references resource_instance,
  class             drift_class not null,
  detail            jsonb not null,
  detected_at       timestamptz not null default now(),
  resolved_at       timestamptz,
  resolution        text                              -- reconciled|adopted|accepted|removed
);

create table control_flag (
  scope             text primary key,                 -- 'global' | 'lob:<id>' | 'tenant:<id>'
  paused            boolean not null default false,
  reason            text,
  set_by            text not null,
  set_at            timestamptz not null default now()
);

create table audit_event (
  audit_id          bigserial primary key,
  at                timestamptz not null default now(),
  actor             text not null,
  action            text not null,
  subject_type      text not null,
  subject_id        text not null,
  before_hash       text,
  after_hash        text,
  detail            jsonb,
  request_id        text
);
create index on audit_event (subject_type, subject_id, at desc);
```

## 3. Invariants

- SSP-DM-001 `order.state` transitions only through the API/workflow functions `TransitionOrder(order_id, to, reason)`, which inserts the `order_event` in the same transaction.
- SSP-DM-002 `approved_spec.approved_params` is write-once.
- SSP-DM-003 `resource_instance.name` is the module block key in the rendered root module; it never changes after creation (renames are new instances).
- SSP-DM-004 `tenant_generation` is monotonically increasing per tenant; the reconciler holds an advisory lock `pg_advisory_xact_lock(hashtext(tenant_id))` while allocating a generation.
- SSP-DM-005 No column anywhere may hold a secret value; the `secret_scan` CI gate greps migrations and fixtures for forbidden patterns.
- SSP-DM-006 Row counts: designed for 10,000 tenants, 1,000,000 orders, 5,000,000 events; partition `order_event` and `audit_event` by month from day one.

## 4. Object layout in the LOB state bucket

```
gs://ssp-state-<lob>/
└── <tenant boundary ref>/                     e.g. pay-prod-7a1c/
    ├── terraform.tfstate                      Observed (Terraform-managed; versioning on)
    ├── .terraform.lock.hcl                    provider lock (copied in by the runner)
    ├── expected/<generation>/
    │   ├── main.tf.json                       rendered root module
    │   ├── variables.auto.tfvars.json         non-secret inputs
    │   ├── backend.hcl                        backend config used
    │   └── manifest.json                      spec hashes, module versions, rendered_at
    └── runs/<run_id>/
        ├── plan.json                          terraform show -json
        ├── plan.txt                           human plan
        ├── policy.json                        plan-stage OPA result
        ├── apply.log                          redacted
        └── result.json                        {state, summary, outputs(non-secret), finished_at}
```

IAM: tenant SA has `objectAdmin` on `resource.name.startsWith("projects/_/buckets/ssp-state-<lob>/objects/<tenant>/")` only; bucket default CMEK = LOB key; uniform bucket-level access; versioning on; soft delete 30 days; no public access.
