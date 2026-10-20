# ssp-doc — Specifications for the Self-Service Platform (SSP) and its Software Dark Factory

This repository is the **source of truth** for everything the factory builds: the multi-cloud self-service provisioning platform (SSP, successor to Taxi), the apps around it (control room, migration), and the factory process itself. Code repositories implement what is written here; when code and spec disagree, the spec wins and the code changes, or a spec-change PR is opened here first.

Decisions in `00-constitution/02-decisions-register.md` come from the design session between Norm, Manoj and Dwayne and are **locked**. Nothing in this repo or in any code repo may deviate from them without a superseding ADR approved by the platform team.

## How to read this repo

| Folder | What it holds | Read it when |
|---|---|---|
| `00-constitution/` | Principles, locked decisions, glossary, definition of done, autonomy tiers | Always, first |
| `10-product/` | The SSP product: functional spec, domain model and DDL, Go API contract, Temporal workflows, OPA policy, service catalog spec, UI spec, conversational provisioning | Building `ssp-cp`, `ssp-workers`, `ssp-ui`, `ssp-module-*` |
| `20-apps/` | Control room, migration app, operator agent chat | Building `ssp-control-room`, `ssp-migrate` |
| `30-infra/` | GKE layout, Temporal install, Terraform worker, Postgres, state buckets, observability | Standing up or changing the platform's own infrastructure |
| `40-repos/` | Repo map, per-repo structure and conventions, module template | Creating or changing any repo |
| `50-factory/` | How agents build this: roles, gates, tiers, Cursor rules, task template | Setting up Cursor / CI, writing tasks |
| `60-adr/` | Architecture decision records (5 categories) | Any design change |
| `70-acceptance/` | Pointer to the holdout acceptance repo (not here, by design) | Setting up evaluation |
| `80-runbooks/` | Bootstrap order and operational runbooks | Day 0 and operations |
| `90-tasks/` | Work items for agents, each with spec references and acceptance criteria | Starting a build task |

## Requirement IDs

Every normative statement carries an ID of the form `SSP-<AREA>-<nnn>` (for example `SSP-API-012`) and uses MUST / SHOULD / MAY. Tests, policies and scenarios reference these IDs; the traceability gate fails a PR that changes behaviour covered by an ID without a test that cites it.

## Repositories

| Repo | Role |
|---|---|
| `ssp-doc` | This repo: specs, ADRs, tasks |
| `ssp-cp` | Control plane: Go APIs, Temporal workflows, policy engine, catalog loader, assistant gateway |
| `ssp-workers` | Temporal workers: Terraform runner launcher, post-build integrations, notifications, drift scanner |
| `ssp-ui` | User-facing storefront (Next.js + Tailwind + shadcn/ui) |
| `ssp-module-<service>` | One repo per Terraform service module, e.g. `ssp-module-spanner`; each publishes a catalog bundle |
| `ssp-control-room` | Operator console and operator agent chat (new repo) |
| `ssp-migrate` | Migration app: inventory, mapping, one-time state import (new repo) |
| `ssp-acceptance` | Holdout scenarios and evaluator (new, private; never opened in a builder workspace) |

## Status

Version 0.1, 2026-10-20. Phase 0 (bootstrap) specs are complete enough to build the first vertical slice: one GCP service (`gcp.spanner-instance` is the worked example; `gcp.gcs-bucket` is the simplest alternative) through all four states, with Temporal and the Terraform worker on the existing GKE cluster.
