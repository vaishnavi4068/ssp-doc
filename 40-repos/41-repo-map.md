# 41 — Repository Map and Conventions

| Repo | Owns | Language / stack | Deployed to | Tier of typical change |
|---|---|---|---|---|
| `ssp-doc` | Specs, ADRs, tasks, factory rules (this repo) | Markdown, YAML, JSON Schema | — | T0 (docs) / T3 (constitution, factory) |
| `ssp-cp` | Go API (`ssp-api`), control worker (workflows + control-plane activities), policy baseline build, catalogctl, DB migrations, Helm chart | Go 1.23, chi, oapi-codegen, sqlc, Temporal SDK, OPA | GKE `ssp-cp` | T2 |
| `ssp-workers` | `tf-worker`, `tf-runner` image, `postbuild-worker`, `drift-worker`, `gcsutil`, twins of ServiceNow/CMDB/Infoblox for tests | Go, bash, Docker | GKE `ssp-workers`, Jobs in `ssp-runs` | T2 (T3 for runner image security settings) |
| `ssp-ui` | Storefront, `@ssp/form-renderer`, `@ssp/ui` tokens | Next.js 15, TS, Tailwind v4, shadcn/ui | GKE `ssp-ui` | T2 |
| `ssp-module-<service>` | One Terraform module + ServiceSpec + request schema + ui.yaml + pricing + Rego + import mapping + tests; publishes a catalog bundle | Terraform, Rego | catalog bucket | T1 (new) / T2 (in use) |
| `ssp-control-room` | Operator console + operator chat UI | Next.js, shared `@ssp/ui` | GKE `ssp-control-room` | T2 |
| `ssp-migrate` | Migration wizard | Next.js, shared `@ssp/ui` | GKE `ssp-migrate` | T2 |
| `ssp-acceptance` | Holdout scenarios, LLM-as-user harness, red-team sets, evaluator | Go/TS, YAML | CI only, private | human-only |

## Conventions (all repos)

- SSP-REPO-001 Default branch `main`, protected: PR required, linear history, required checks from `50-factory/54-gates.md`, CODEOWNERS review per tier. Agents push to `agent/<task-id>-<slug>` branches.
- SSP-REPO-002 Every repo has `AGENTS.md` (copied from `50-factory/cursor-rules/AGENTS.<repo>.md`), `.cursor/rules/*.mdc`, `CODEOWNERS`, `Makefile` with `make generate lint test build`, `deploy/chart/` (services) and `.github/workflows/{ci,release}.yml`.
- SSP-REPO-003 Conventional commits; PR title `[<task-id>] <summary>`; PR body template lists spec IDs, tier, blast radius, test evidence.
- SSP-REPO-004 Versioning: services use image tags `<semver>-<sha>`; modules use git tags `v<semver>` and publish bundles at the same version.
- SSP-REPO-005 Generated code is committed (`internal/api/gen`, `lib/api`) and verified unchanged by a CI step that regenerates and diffs.
- SSP-REPO-006 One GitHub App per agent role (`ssp-builder`, `ssp-reviewer`, `ssp-evaluator`, `ssp-release`) with repo permissions by role; no personal tokens in CI.
- SSP-REPO-007 Shared UI package `@ssp/ui` is published from `ssp-ui` to GitHub Packages and consumed by `ssp-control-room` and `ssp-migrate`; no copy-paste of components.

## CODEOWNERS template

```
# Platform team owns everything by default
*                         @vaishnavi4068/ssp-platform
# Security co-owns identity, network, policy relaxations, runner image
/deploy/foundation/       @vaishnavi4068/ssp-platform @vaishnavi4068/ssp-security
/policy/                  @vaishnavi4068/ssp-platform @vaishnavi4068/ssp-security
/30-infra/                @vaishnavi4068/ssp-platform @vaishnavi4068/ssp-security
/.github/                 @vaishnavi4068/ssp-platform
/CODEOWNERS               @vaishnavi4068/ssp-platform
```

(Replace team slugs with the real GitHub teams; in the personal-account phase, individual handles.)

## Cross-repo contracts

| Contract | Producer | Consumers | Change rule |
|---|---|---|---|
| `12-openapi.yaml` | ssp-doc | ssp-cp (server), ssp-ui / control-room / migrate (clients) | oasdiff no-break or version bump |
| `15-service-spec.schema.json` | ssp-doc | ssp-cp (validator), every module repo (CI validate) | additive only within v1 |
| Catalog bundle layout | ssp-doc §15 | module CI (publish), ssp-cp (load), ssp-ui (render) | versioned `bundle.json.layout` |
| `RunInput` / `result.json` | ssp-doc §33 | ssp-cp (reconciler), ssp-workers (worker, runner) | shared Go types in `ssp-cp/pkg/ssp` |
| Policy input documents | ssp-doc §14 | ssp-cp, runner, module policies | additive only |
