---
id: T-0010
title: TenantReconciler entity workflow: batching, AllocateGeneration, Render (main.tf.json), CreateRun, PlanGate, CaptureObserved, DriftScan schedule
repo: ssp-cp
tier: T2
status: ready
specs: [SSP-WF-020..024, SSP-PROD-050..055, SSP-CP-003, SSP-CP-004]
depends_on: [T-0009]
owner: platform
---

## Goal
TenantReconciler entity workflow: batching, AllocateGeneration, Render (main.tf.json), CreateRun, PlanGate, CaptureObserved, DriftScan schedule.

## Context pack
- Read: 10-product/13-workflows-spec.md; 10-product/11-domain-model.md §4; 10-product/10-product-spec.md §6; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-cp`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-cp`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. Two Enqueue signals within 20 s produce one generation; isolation spec runs alone; PlanGate fails on an undeclared destroy (fixture plan.json); continue-as-new carries the queue.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
