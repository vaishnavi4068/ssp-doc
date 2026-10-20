# 43 — `ssp-workers` Repository Structure

Temporal activity workers that touch the outside world: Terraform runs (via Kubernetes Jobs), post-build integrations, drift inventory; plus the runner image and the twins used for testing. Implements `30-infra/33-terraform-worker-on-gke.md`, `13-workflows-spec.md` §4–5 (activities), `14-policy-spec.md` (plan stage execution).

```
ssp-workers/
├── AGENTS.md  .cursor/rules/  CODEOWNERS  Makefile  go.mod  (imports github.com/vaishnavi4068/ssp-cp/pkg/ssp)
├── cmd/
│   ├── tf-worker/main.go           task queue tf-runs-<lob>; activity RunTerraform; metrics on :9090
│   ├── postbuild-worker/main.go    task queue post-build; activities cmdb.register, backup.enroll, monitoring.onboard, notify.team, dns.register, firewall.request, escalate
│   ├── drift-worker/main.go        task queue drift; activities ClassifyDrift, InventoryAssets (Cloud Asset Inventory)
│   ├── gcsutil/main.go             tiny gcs cp/ls binary for the runner image (Workload Identity, no gcloud)
│   └── run-callback/main.go        (later) async activity completion endpoint, in-cluster only
├── internal/
│   ├── tfrun/                      activity.go (RunTerraform), jobname.go (deterministic), template.go (Job render), result.go (read result.json), redact.go
│   ├── k8s/                        clientset wiring, informer-based job watcher (replaces polling without changing the activity contract)
│   ├── postbuild/                  one package per integration with Client interface + twin impl; receipts
│   ├── drift/                      classify.go (allowlists from ServiceSpec), inventory.go
│   └── metrics/
├── runner/
│   ├── Dockerfile                  = 30-infra/tf-worker/Dockerfile.runner
│   ├── runner.sh                   = 30-infra/tf-worker/runner.sh
│   ├── provider-mirror.tfrc
│   └── providers.lock.hcl          provider set + versions mirrored at image build (google, google-beta, random, null, time; aws/azurerm later)
├── twins/                          HTTP fakes used by integration tests and sandbox: servicenow (CR create/approve, incident), cmdb (CI CRUD), infoblox (record CRUD); each with a /__admin API to seed and inject failures
├── deploy/chart/                   tf-worker, postbuild-worker, drift-worker Deployments; ServiceAccounts; NetworkPolicies; RBAC for ssp-runs
├── deploy/runs-namespace/          = 30-infra/tf-worker/namespace-rbac.yaml, networkpolicy.yaml
└── test/
    ├── unit/                       job name determinism, template rendering, result parsing, redaction
    ├── integration/                kind cluster + Temporal dev server: RunTerraform re-attach test (kill worker mid-run → same Job), lock-error retry, cancellation deletes Job
    └── e2e/                        sandbox GKE: refresh run on an empty tenant
```

## Binding notes

- SSP-WK-001 `JobName(runID, attempt) = "tf-" + hex(sha256(runID + ":" + attempt))[:20]`; lowercase, ≤ 63 chars, RFC 1123.
- SSP-WK-002 The activity's source of truth for outcome is `result.json` in the run artifacts, not Pod exit codes or logs; if the Job finished and `result.json` is missing, the activity returns a retryable error so the reconciler can decide.
- SSP-WK-003 `redact.go` holds the regex set shared with `ssp-cp` (import from `pkg/ssp/redact`); tests include a known-secret corpus that must never appear in output.
- SSP-WK-004 Post-build activities are idempotent by key (`<step>:<resource_instance_id>`), persist receipts via the control-plane API (`internal` endpoint, Workload Identity auth), and never write to Postgres directly.
- SSP-WK-005 Twins are production-quality fakes: schema-validated requests, realistic latencies, failure injection; they are what the Scenario Evaluator runs against.
- SSP-WK-006 Runner image is rebuilt weekly (base image and provider CVEs) by a scheduled workflow; promotion to prod requires the blast-radius corpus plan to be unchanged.
