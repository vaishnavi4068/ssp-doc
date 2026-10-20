# 05 — Autonomy tiers

Every PR is labelled with exactly one tier. The tier decides who, or what, may merge. Labels are applied by a CI job from the paths touched; a human may raise a tier, never lower it.

| Tier | What it covers | Merge rule | Typical repos / paths |
|---|---|---|---|
| **T0** | Docs, tests, twins (fakes of external systems), fixtures, UI copy | Auto-merge on green gates | `ssp-doc` non-constitution, `**/tests/**`, `ssp-workers/twins/**` |
| **T1** | New catalog entry or module version **not yet used by any tenant**; new UI template for such a service | Green gates + scenario evaluator pass → auto-merge | `ssp-module-*` first release, `ssp-ui/templates/**` |
| **T2** | Modules, policies, workflows, API or UI **already in use** by tenants | Green gates + evaluator + **1 human** from the platform team | `ssp-cp/**`, `ssp-workers/**`, `ssp-ui/app/**`, `ssp-module-*` ≥ v1 with tenants |
| **T3** | Identity and impersonation, state backend, network, policy relaxations, gate definitions, the factory itself, platform foundation, anything under `00-constitution/` | Agents draft only. **2 humans including security**, applied in sandbox first | `30-infra/**`, `50-factory/**`, `.github/**`, IAM/WIF Terraform, `policies/**` where a rule is loosened |

## Rules

- SSP-TIER-001: A PR touching paths in two tiers takes the higher tier.
- SSP-TIER-002: Any Rego change that reduces the set of denied inputs on the policy-impact replay is T3 regardless of path.
- SSP-TIER-003: Any module change whose blast-radius gate shows a destroy or replace is T3 even when declared.
- SSP-TIER-004: Changes to `ssp-acceptance` are human-only and are never visible to builder agents.
- SSP-TIER-005: An agent may not approve a PR. Agent review comments are advisory; the merge decision is the gate plus the humans the tier requires.
