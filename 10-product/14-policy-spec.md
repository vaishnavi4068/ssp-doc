# 14 — Policy Specification (OPA)

New rules against the platform's own JSON schema (D-13). Two evaluation points: **request stage** (inside `ComputeApproval` and `preflight`) and **plan stage** (inside the Terraform runner on `plan.json`). Nothing from Taxi is reused.

## 1. Bundles

| Bundle | Source repo | Scope | Loaded by |
|---|---|---|---|
| `platform` | `ssp-doc/10-product/policy/` (human-owned baseline) → built by `ssp-cp` CI | Global rules: labels, naming, allowed regions, data-class controls, budget | ssp-cp (embedded OPA), runner (CLI) |
| `service/<service_id>` | `ssp-module-<service>/policy/` | Service-specific rules (both stages) | Published inside the catalog bundle |

- SSP-POL-001 Bundles are OCI/tarball artifacts in `gs://ssp-catalog-<env>/policy/` with a digest recorded in `approved_spec.policy_decision.bundle_digest` and in `run` artifacts.
- SSP-POL-002 The runner image pins the same OPA version as `ssp-cp` (`opa` 1.x; exact version in `30-infra/tf-worker/Dockerfile`).

## 2. Request-stage input document

```json
{
  "stage": "request",
  "order": {"kind": "create", "service_id": "gcp.spanner-instance", "version": "1.2.0", "name": "claims-ledger"},
  "params": { "...approved_params after guardrail injection..." },
  "tenant": {"tenant_id": "gcp:pay-prod-7a1c", "cloud": "gcp", "env": "prod", "lob_id": "pbm",
             "apm_id": "APM-10432", "tier": 1, "data_class": "PHI", "cost_center": "CC-5531", "region_allowlist": ["us-central1","us-east4"]},
  "principal": {"principal_id": "…", "personas": ["buyer"], "entitlements": ["APM-10432"]},
  "estimate": {"monthly_usd": 1234.56},
  "budget": {"monthly_limit_usd": 50000, "committed_usd": 41000},
  "catalog": {"guardrails": [ ... ]}
}
```

Decision document (`data.ssp.request.decision`):

```json
{"result": "allow|deny|warn",
 "rules": [{"id": "ssp.request.labels.required", "result": "deny", "message": "label cost_center missing", "requirement_id": "SSP-POL-110"}],
 "gates": ["cr_required"]}
```

## 3. Plan-stage input document

`terraform show -json plan.tfplan` plus context:

```json
{"stage": "plan", "tenant": {...}, "generation": 42, "batch": {"resource_instances": ["claims-ledger"]},
 "plan": { "...terraform plan JSON..." }}
```

Decision `data.ssp.plan.decision` with the same shape; additionally `data.ssp.plan.touched` lists module addresses changed.

## 4. Baseline rules (platform bundle)

| ID | Stage | Rule | Result |
|---|---|---|---|
| SSP-POL-100 | request | Principal must be entitled to `tenant.apm_id` | deny |
| SSP-POL-101 | request | Tenant not paused; global/LOB not paused | deny (`tenant_paused` gate) |
| SSP-POL-110 | request | Labels `apm_id`, `cost_center`, `lob`, `env`, `data_class`, `managed_by=ssp` present (injected by guardrails; rule verifies) | deny |
| SSP-POL-111 | request | Resource name matches `^[a-z][a-z0-9-]{2,40}$` and is unique in tenant (checked by API; rule re-asserts format) | deny |
| SSP-POL-120 | request | Region ∈ `tenant.region_allowlist` | deny |
| SSP-POL-130 | request | `data_class ∈ {PHI, PII}` ⇒ CMEK key set, public access disabled, retention ≥ class minimum | deny |
| SSP-POL-131 | request | `tier == 1` and service category `database` ⇒ multi-region/HA flag true | warn if relaxed with sign-off, else deny |
| SSP-POL-140 | request | `estimate.monthly_usd + budget.committed_usd ≤ budget.monthly_limit_usd` | deny (`budget_exceeded` gate) |
| SSP-POL-150 | request | `env == prod` and `kind ∈ {change, decommission}` ⇒ gate `cr_required` | gate |
| SSP-POL-151 | request | `kind == decommission` and service `lifecycle.holdsData` ⇒ gate `owner_signoff_required` | gate |
| SSP-POL-200 | plan | No `delete` or `replace` action on a resource outside `batch.resource_instances` | deny |
| SSP-POL-201 | plan | No change to `provider`/`backend` configuration; no `-target` | deny |
| SSP-POL-202 | plan | No resource of a type outside the service's declared `resourceTypes` | deny |
| SSP-POL-203 | plan | No IAM binding granting `roles/owner`, `roles/editor`, `allUsers`, `allAuthenticatedUsers` | deny |
| SSP-POL-204 | plan | No public ingress (0.0.0.0/0) on firewall or LB resources unless service declares `publicIngress: true` and request-stage allowed it | deny |
| SSP-POL-205 | plan | Every created resource carries the mandatory labels | deny |
| SSP-POL-206 | plan | Sensitive attributes (`password`, `private_key`, `secret`) are unknown-after-apply or reference a secret manager resource, never literals | deny |

## 5. Authoring rules (for `ssp-module-*` policies)

- SSP-POL-300 Package names: `ssp.request.svc.<service_slug>` and `ssp.plan.svc.<service_slug>`; each rule sets `id`, `message`, `requirement_id` (from the service ADR).
- SSP-POL-301 Every MUST guardrail in the ServiceSpec has at least one plan-stage rule verifying it on the plan JSON (defence in depth against module bugs).
- SSP-POL-302 Tests: `opa test` with ≥ 90 % coverage; fixtures include one allow, one deny per rule.
- SSP-POL-303 Lint with `regal`; no `http.send` in policies.

## 6. Policy-impact replay (gate)

- SSP-POL-400 CI for any bundle change replays the new bundle against the last 90 days of request inputs and plan JSONs (sanitized corpus in `gs://ssp-corpus-<env>/`) and reports newly-denied / newly-allowed counts and examples.
- SSP-POL-401 Any newly-allowed input marks the PR T3 (security review).
