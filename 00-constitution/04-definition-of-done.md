# 04 — Definition of Done

A change is done when all of the following are true. Gates in `50-factory/54-gates.md` automate every line that can be automated.

## For any PR

- [ ] Task in `90-tasks/` referenced; every cited `SSP-*` requirement is implemented or explicitly deferred in the PR description.
- [ ] Tests cite the requirement IDs they cover; coverage of changed packages does not fall.
- [ ] Lint, format, vulnerability scan (gitleaks, govulncheck / npm audit / trivy) pass.
- [ ] No secrets, no credentials, no real tenant identifiers in fixtures.
- [ ] Docs updated where behaviour changed (OpenAPI, ServiceSpec, runbook).
- [ ] Autonomy tier labelled (`tier:T0`…`tier:T3`) and the merge rule for that tier satisfied.

## For `ssp-cp` (Go API, workflows)

- [ ] OpenAPI regenerated and `oasdiff` shows no breaking change, or the API version was bumped.
- [ ] Temporal workflow changes pass the replay test against recorded histories, or are versioned with `workflow.GetVersion`.
- [ ] sqlc regenerated; migration is forward-only and reversible by a new migration.
- [ ] Structured logs and OpenTelemetry spans on every new handler and activity.

## For `ssp-workers`

- [ ] Activities are idempotent; retries re-attach to existing Jobs by deterministic name.
- [ ] Heartbeats emitted at least every 30 s on long activities; timeouts set explicitly.

## For `ssp-module-<service>`

- [ ] `terraform fmt`, `validate`, `tflint`, `trivy config` clean.
- [ ] `terraform test` passes; at least one test per MUST guardrail in the ServiceSpec.
- [ ] Blast-radius gate: planning the new version against the sanitized state corpus produces no undeclared destroy/replace; refactors use `moved` blocks.
- [ ] ServiceSpec validates against `service-spec.schema.json`; request schema, UI template and pricing are consistent (generated check).
- [ ] Rego tests pass with ≥ 90 % coverage; policy-impact replay reviewed.
- [ ] CHANGELOG entry; semantic version tag; catalog bundle published to the catalog bucket.

## For `ssp-ui`, `ssp-control-room`, `ssp-migrate`

- [ ] Renders from the catalog bundle with no code change for a new service (verified by the "unknown service" fixture).
- [ ] Keyboard navigation, focus order and contrast meet WCAG 2.1 AA on changed screens.
- [ ] Visual regression snapshots updated intentionally, not blindly.
- [ ] Matches the design tokens in `10-product/16-ui-spec.md`.

## For infrastructure (`30-infra/`)

- [ ] Applied in sandbox first; verification steps in the runbook executed and recorded.
- [ ] Two human approvals including security for anything in tier T3.
