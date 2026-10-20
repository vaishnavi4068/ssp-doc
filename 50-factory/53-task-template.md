# 53 — Task Template

Tasks live in `90-tasks/<id>-<slug>.md`. IDs: `T-<nnnn>`. A task is the unit of agent work and of a PR.

```markdown
---
id: T-0007
title: Implement POST /v1/orders/preflight
repo: ssp-cp
tier: T2
status: ready            # draft | ready | in_progress | review | done | blocked
specs: [SSP-API-010, SSP-API-011, SSP-PROD-020, SSP-PROD-030, SSP-PROD-031, SSP-CP-001, SSP-CP-002]
depends_on: [T-0004, T-0005]
owner: platform
---

## Goal
One sentence: what exists when this is done.

## Context pack
- Read: ssp-doc/10-product/12-api-spec.md §2 Orders, §3; 15-catalog-servicespec.md §2–3; 14-policy-spec.md §2.
- Files you may create or change: internal/api/handlers/orders.go, internal/catalog/{derive.go,guardrails.go,pricing.go}, internal/policy/request.go, internal/approval/compute.go, tests under the same packages.
- Files you must not touch: internal/api/gen/**, db/migrations/**, deploy/**.
- Interfaces to honour: `approval.Compute(ctx, Input) (Result, error)` is shared with ComputeApproval (SSP-CP-001).

## Acceptance criteria
1. Given the sandbox catalog `gcp.spanner-instance@1.2.0` and tenant `gcp:pay-prod-7a1c` (tier 1, PHI), a preflight with `config.mode=regional` returns `approved_params.config.mode=multi-region` with a guardrail entry citing REQ-E-SPAN-0001-04 (SSP-PROD-030).
2. `preview_hash` is stable across two identical calls and changes when any approved param, guardrail or bundle digest changes (SSP-API-011).
3. Policy deny returns 200 with `policy.result=deny` and rule ids (preflight never 4xx on policy); entitlement failure returns 403 problem (SSP-POL-100).
4. p95 latency < 300 ms for the fixture under `make bench`.
5. Tests cite every spec id above.

## Out of scope
Order creation (T-0008), assistant tools (T-0021).

## Evidence to attach to the PR
`make test` output, bench numbers, example request/response JSON.
```

Rules: SSP-TASK-001 a task lists at most one repo. SSP-TASK-002 every acceptance criterion is checkable by a test or a command. SSP-TASK-003 tasks are created by humans or by the Spec Scribe as PRs; agents never create tasks for themselves.
