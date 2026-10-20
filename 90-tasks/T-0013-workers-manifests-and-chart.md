---
id: T-0013
title: Helm chart and runs-namespace manifests mirroring 30-infra/tf-worker; NetworkPolicies; RBAC
repo: ssp-workers
tier: T3
status: ready
specs: [SSP-INF-001, SSP-INF-002, SSP-INF-010]
depends_on: [T-0011, T-0012]
owner: platform
---

## Goal
Helm chart and runs-namespace manifests mirroring 30-infra/tf-worker; NetworkPolicies; RBAC.

## Context pack
- Read: 30-infra/33-terraform-worker-on-gke.md §2; 30-infra/31-gke-platform-layout.md; 00-constitution/* (always).
- Repo structure and binding notes: 40-repos/ (file for `ssp-workers`), or 45-ssp-module-template.md for module repos, or 20-apps/ for apps.
- Files you may touch: those implied by the goal inside `ssp-workers`; never protected paths (.github/, CODEOWNERS, deploy/foundation/, gate scripts).

## Acceptance criteria
1. kubeconform + conftest pass; RBAC verbs limited to the allowlist; default-deny present in ssp-runs.
2. Tests cite every spec id listed above (gate/traceability).

## Evidence to attach to the PR
Command output for `make test` (or repo equivalent), fixture request/response samples, screenshots for UI tasks.
