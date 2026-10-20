# 54 — CI Gates per Repository

Gates are GitHub Actions required checks. Names are binding (branch rulesets reference them). An agent cannot edit `.github/` (protected path).

## Common (every repo)

| Check | Tool | Fails when |
|---|---|---|
| `gate/secrets` | gitleaks | any finding |
| `gate/tier-label` | script | PR lacks exactly one `tier:T*` label or label lower than path rules require |
| `gate/task-link` | script | PR title lacks `[T-nnnn]` or body lacks `Spec:` ids |
| `gate/traceability` | script | a MUST id listed in the task has no test/policy/scenario citing it (greps `SSP-\w+-\d+` in tests) |
| `gate/specs-sync` | script | `docs/specs` copy differs from `ssp-doc@main` |

## `ssp-cp`

| Check | Tool | Fails when |
|---|---|---|
| `gate/go-lint` | golangci-lint, govulncheck | any error / known vuln |
| `gate/generate-diff` | `make generate` + git diff | generated code stale |
| `gate/unit` | `go test ./...` with race | failure; coverage of changed packages drops |
| `gate/replay` | Temporal replayer over `testdata/histories` | non-deterministic change without `GetVersion` |
| `gate/openapi` | spectral lint + oasdiff vs `main` | breaking change without version bump |
| `gate/schema-compat` | script | `service-spec.schema.json` or request schema change not additive |
| `gate/policy` | `opa test`, regal, coverage ≥ 90 % | failure |
| `gate/policy-impact` | `policyctl impact-replay` vs corpus | newly-allowed inputs without `tier:T3` |
| `gate/itest` | testcontainers | failure |
| `gate/image` | trivy image, cosign sign | critical CVE |

## `ssp-workers`

| Check | Tool | Fails when |
|---|---|---|
| `gate/go-lint`, `gate/unit`, `gate/image` | as above | |
| `gate/runner-image` | hadolint, trivy, `terraform version`/`opa version` pin check, non-root check | drift from `30-infra/tf-worker/Dockerfile.runner` |
| `gate/reattach` | kind + Temporal dev server integration test | second Job created on retry, or orphan Job after cancel |
| `gate/redaction` | known-secret corpus | any secret survives |
| `gate/manifests` | kubeconform + conftest (RBAC verbs allowlist, NetworkPolicy present) | deviation from `30-infra/tf-worker/*.yaml` |

## `ssp-ui`, `ssp-control-room`, `ssp-migrate`

| Check | Tool | Fails when |
|---|---|---|
| `gate/ts` | eslint, tsc --noEmit | errors |
| `gate/unit` | vitest | failure |
| `gate/unknown-service` | renderer test with `fixtures/catalog/unknown-service` | render error |
| `gate/e2e` | Playwright vs twin-backed sandbox API | failure |
| `gate/a11y` | Lighthouse CI (Home, Checkout, Order, Sidekick) | a11y < 95 or perf < 85 |
| `gate/visual` | Playwright snapshots | unexpected pixel diff |
| `gate/tokens` | script | any color/radius literal outside `@ssp/ui` |

## `ssp-module-<service>`

| Check | Tool | Fails when |
|---|---|---|
| `gate/tf-static` | fmt, validate, tflint, trivy config | any |
| `gate/tf-test` | `terraform test` (unit) | failure; MUST guardrail without assertion |
| `gate/catalog` | `catalogctl validate` | ServiceSpec/schema/ui/pricing inconsistent; variables mismatch |
| `gate/policy` | opa test + regal + coverage | failure |
| `gate/blast-radius` | plan new version against `ssp-corpus` sanitized states | any destroy/replace not declared in CHANGELOG; declared ones force `tier:T3` |
| `gate/import-mapping` | script | resources/variables changed without `import/mapping.yaml` update |
| `gate/apply-nightly` | `terraform test` apply in sandbox project (schedule) | failure opens an issue |

## `ssp-doc`

| Check | Tool | Fails when |
|---|---|---|
| `gate/md-lint`, `gate/links` | markdownlint, lychee | broken links |
| `gate/ids` | script | duplicate or malformed `SSP-*`/`REQ-*` ids; requirement without Verify-by |
| `gate/decisions-locked` | script | change under `00-constitution/02-decisions-register.md` without `tier:T3` and a superseding ADR link |
| `gate/spec-critic` | Claude Code GitHub Action with `cursor-rules/review-prompt.md` (spec mode) | advisory |

## Evaluator (T1+; status `gate/evaluator`)

Runs from `ssp-acceptance` on a private runner against the sandbox deployment of the PR (ephemeral namespace): holdout end-to-end and conversational scenarios. Thresholds: T1 ≥ 0.9 satisfaction and 0 red-team successes; T2 ≥ 0.95; failures are posted as symptoms only.
