# ADR-GLB-002 Amendment — Go control plane and workers (2026-11)

- **Amends:** [ADR-GLB-002](ADR-GLB-002-languages-and-technology-stack.md)
- **Status:** Accepted (product repos migrated)
- **Scope:** `ssp-cp`, `ssp-workers`, `ssp-ui` deploy/runtime only

## Decision

| Layer | Previous (ADR-GLB-002 table) | Amended |
|-------|------------------------------|---------|
| **ssp-cp** | Python FastAPI | **Go 1.26+** — chi, sqlc, pgx, oapi-codegen, OPA CLI/sidecar |
| **ssp-workers** | Python `temporalio` | **Go** Temporal SDK — workflows native; activities completing Go port |
| **ssp-ui** | React only | React **+ Go** `cmd/portal` static server in the container image |
| **ssp-module-*** | Terraform/Rego | Unchanged (not application Go) |

## Requirements (supersede ADR-GLB-002 REQ-1, REQ-2)

- **REQ-1-GO:** `ssp-cp` API and idp plane MUST be implemented in Go; Python FastAPI MUST NOT ship on `main`.
- **REQ-2-GO:** `ssp-workers` Temporal worker process MUST be Go; Python MAY remain only as a temporary activity implementation behind `workers.run_activity` until native Go store/runner code lands.

## Unchanged

- REQ-3: `ssp-ui` storefront remains React + TypeScript for forms and catalog rendering.
- REQ-4/5: Terraform and Rego module repos unchanged.
