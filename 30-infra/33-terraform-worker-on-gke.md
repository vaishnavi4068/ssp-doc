# 33 — Terraform Worker and Runner on GKE: Installation Specification

Implements D-12: a dedicated Temporal activity worker (`tf-worker`, in `ssp-workers`) launches one **Kubernetes Job per operation** running the `tf-runner` image; the Job name is derived deterministically from the operation ID so a retried activity re-attaches instead of re-running; the worker polls Job status (~30 s) and heartbeats; a callback path is a later addition. Worker and Jobs run in the same cluster, in different namespaces.

```
Temporal (ns temporal) ◄── polls task queue tf-runs-<lob> ── tf-worker (ns ssp-workers, KSA tf-worker)
                                                                  │ create/get/watch Job (RBAC in ns ssp-runs only)
                                                                  ▼
                                                     Job tf-<hash> (ns ssp-runs, KSA tf-runner → GSA ssp-tf-runner = Platform SA)
                                                                  │ impersonate ssp-tenant@<project>  (15-min token)
                                                                  ├─ GCS: expected/<gen> (read), terraform.tfstate (lock/write), runs/<run_id>/ (write)
                                                                  └─ Cloud APIs of the tenant project as the tenant SA
```

## 1. Files in this folder (`30-infra/tf-worker/`)

| File | Purpose |
|---|---|
| `namespace-rbac.yaml` | Namespaces, KSAs, Role/RoleBinding letting `tf-worker` manage Jobs in `ssp-runs` |
| `networkpolicy.yaml` | Default-deny for `ssp-runs`, egress to Google APIs only; worker egress |
| `tf-worker-deployment.yaml` | Worker Deployment + config |
| `job-template.yaml` | The Job the worker instantiates (also embedded in Go as a template) |
| `Dockerfile.runner` | `tf-runner` image: Terraform, OPA, gcloud-less GCS access via the Go `gcsutil`, entrypoint |
| `runner.sh` | Entrypoint: init → plan/apply/refresh/import → policy → artifacts → result.json |
| `provider-mirror.tfrc` | Terraform CLI config: filesystem provider mirror, no registry egress |

## 2. Kubernetes objects

`namespace-rbac.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ssp-runs
  labels: { pod-security.kubernetes.io/enforce: baseline, ssp.io/tier: runs }
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tf-runner
  namespace: ssp-runs
  annotations:
    iam.gke.io/gcp-service-account: ssp-tf-runner@CP_PROJECT.iam.gserviceaccount.com   # Platform SA (kill switch)
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tf-worker
  namespace: ssp-workers
  annotations:
    iam.gke.io/gcp-service-account: ssp-tf-worker@CP_PROJECT.iam.gserviceaccount.com   # reads run artifacts only
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: tf-job-manager, namespace: ssp-runs }
rules:
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "get", "list", "watch", "delete"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["create", "get", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: tf-worker-manages-jobs, namespace: ssp-runs }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: Role, name: tf-job-manager }
subjects:
  - { kind: ServiceAccount, name: tf-worker, namespace: ssp-workers }
---
apiVersion: v1
kind: ResourceQuota
metadata: { name: runs-quota, namespace: ssp-runs }
spec:
  hard: { pods: "60", requests.cpu: "60", requests.memory: 120Gi, count/jobs.batch: "200" }
---
apiVersion: v1
kind: LimitRange
metadata: { name: runs-limits, namespace: ssp-runs }
spec:
  limits:
    - type: Container
      default: { cpu: "1", memory: 2Gi }
      defaultRequest: { cpu: 500m, memory: 1Gi }
      max: { cpu: "4", memory: 8Gi }
```

`networkpolicy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: ssp-runs }
spec: { podSelector: {}, policyTypes: [Ingress, Egress] }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: runner-egress, namespace: ssp-runs }
spec:
  podSelector: { matchLabels: { app: tf-runner } }
  policyTypes: [Egress]
  egress:
    - to: [{ ipBlock: { cidr: 169.254.169.254/32 } }]            # GKE metadata server (Workload Identity tokens)
      ports: [{ port: 80, protocol: TCP }]
    - to: [{ ipBlock: { cidr: 199.36.153.8/30 } }]               # private.googleapis.com (Private Google Access)
      ports: [{ port: 443, protocol: TCP }]
    - to: [{ ipBlock: { cidr: 199.36.153.4/30 } }]               # restricted.googleapis.com (if VPC-SC)
      ports: [{ port: 443, protocol: TCP }]
    - to: [{ namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } }, podSelector: { matchLabels: { k8s-app: kube-dns } } }]
      ports: [{ port: 53, protocol: UDP }, { port: 53, protocol: TCP }]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: tf-worker-egress, namespace: ssp-workers }
spec:
  podSelector: { matchLabels: { app: tf-worker } }
  policyTypes: [Egress]
  egress:
    - to: [{ namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: temporal } } }]
      ports: [{ port: 7233, protocol: TCP }]
    - to: [{ ipBlock: { cidr: 199.36.153.8/30 } }]
      ports: [{ port: 443, protocol: TCP }]
    - to: [{ ipBlock: { cidr: 169.254.169.254/32 } }]
      ports: [{ port: 80, protocol: TCP }]
    - to: [{ ipBlock: { cidr: KUBE_APISERVER_CIDR } }]           # GKE control plane endpoint (private)
      ports: [{ port: 443, protocol: TCP }]
    - to: [{ namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } }, podSelector: { matchLabels: { k8s-app: kube-dns } } }]
      ports: [{ port: 53, protocol: UDP }, { port: 53, protocol: TCP }]
```

> If Private Google Access routes to the default `*.googleapis.com` ranges in your VPC rather than `private.googleapis.com`, replace the CIDR with your egress allowlist (or use an FQDN egress policy if your CNI supports it). The intent is: Google APIs + metadata + DNS, nothing else.

`tf-worker-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: tf-worker, namespace: ssp-workers, labels: { app: tf-worker } }
spec:
  replicas: 2
  selector: { matchLabels: { app: tf-worker } }
  template:
    metadata:
      labels: { app: tf-worker }
      annotations: { prometheus.io/scrape: "true", prometheus.io/port: "9090" }
    spec:
      serviceAccountName: tf-worker
      securityContext: { runAsNonRoot: true, runAsUser: 65532, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: worker
          image: REGION-docker.pkg.dev/CP_PROJECT/ssp/tf-worker:VERSION
          args: ["--task-queue=tf-runs-default"]      # one Deployment per LOB queue in prod: --task-queue=tf-runs-<lob>
          env:
            - { name: TEMPORAL_ADDRESS, value: temporal-frontend.temporal.svc.cluster.local:7233 }
            - { name: TEMPORAL_NAMESPACE, value: ssp }
            - { name: RUNS_NAMESPACE, value: ssp-runs }
            - { name: RUNNER_IMAGE, value: REGION-docker.pkg.dev/CP_PROJECT/ssp/tf-runner:VERSION }
            - { name: RUNNER_KSA, value: tf-runner }
            - { name: MAX_CONCURRENT_ACTIVITIES, value: "10" }
            - { name: POLL_INTERVAL, value: "30s" }
            - { name: JOB_TTL_SECONDS, value: "86400" }
            - { name: JOB_ACTIVE_DEADLINE_SECONDS, value: "5400" }
            - { name: OTEL_EXPORTER_OTLP_ENDPOINT, value: http://otel-collector.observability:4317 }
          ports: [{ name: metrics, containerPort: 9090 }]
          resources: { requests: { cpu: 100m, memory: 256Mi }, limits: { cpu: "1", memory: 1Gi } }
          securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: [ALL] } }
          livenessProbe: { httpGet: { path: /healthz, port: 9090 }, periodSeconds: 20 }
          readinessProbe: { httpGet: { path: /readyz, port: 9090 }, periodSeconds: 10 }
```

`job-template.yaml` (the worker renders this; placeholders in `{{ }}`):

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: "{{ .JobName }}"                       # tf-<sha256(run_id:attempt)[:20]>
  namespace: ssp-runs
  labels:
    app: tf-runner
    ssp.io/run-id: "{{ .RunID }}"
    ssp.io/tenant: "{{ .TenantLabel }}"        # label-safe form of tenant_id
    ssp.io/kind: "{{ .Kind }}"                 # plan|apply|refresh|import|destroy
    ssp.io/lob: "{{ .LobID }}"
spec:
  backoffLimit: 0                              # the worker owns retries (new attempt → new job name)
  activeDeadlineSeconds: {{ .ActiveDeadlineSeconds }}
  ttlSecondsAfterFinished: {{ .TTLSeconds }}
  template:
    metadata:
      labels: { app: tf-runner, ssp.io/run-id: "{{ .RunID }}" }
    spec:
      serviceAccountName: tf-runner
      automountServiceAccountToken: false
      restartPolicy: Never
      nodeSelector: { ssp.io/pool: runs }
      tolerations: [{ key: ssp.io/runs, operator: Equal, value: "true", effect: NoSchedule }]
      securityContext: { runAsNonRoot: true, runAsUser: 65532, fsGroup: 65532, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: terraform
          image: "{{ .RunnerImage }}"
          args: ["{{ .Kind }}"]
          env:
            - { name: RUN_ID, value: "{{ .RunID }}" }
            - { name: ATTEMPT, value: "{{ .Attempt }}" }
            - { name: TENANT_ID, value: "{{ .TenantID }}" }
            - { name: TENANT_PROJECT, value: "{{ .TenantProject }}" }
            - { name: TENANT_SA, value: "{{ .TenantSA }}" }                 # ssp-tenant@<project>.iam.gserviceaccount.com
            - { name: STATE_BUCKET, value: "{{ .StateBucket }}" }           # ssp-state-<lob>
            - { name: STATE_PREFIX, value: "{{ .StatePrefix }}" }           # <project>/
            - { name: EXPECTED_URI, value: "{{ .ExpectedURI }}" }           # gs://ssp-state-<lob>/<project>/expected/<gen>/
            - { name: ARTIFACTS_URI, value: "{{ .ArtifactsURI }}" }         # gs://ssp-state-<lob>/<project>/runs/<run_id>/
            - { name: PLAN_FROM_RUN, value: "{{ .PlanFromRunURI }}" }       # apply only: artifacts URI of the plan run
            - { name: POLICY_BUNDLE_URI, value: "{{ .PolicyBundleURI }}" }  # gs://ssp-catalog-<env>/policy/<digest>.tar.gz
            - { name: BATCH_INSTANCES, value: "{{ .BatchInstancesJSON }}" } # for the plan gate input
            - { name: TF_IN_AUTOMATION, value: "1" }
            - { name: TF_INPUT, value: "0" }
            - { name: TF_PLUGIN_CACHE_DIR, value: /opt/terraform/plugin-cache }
            - { name: TF_CLI_CONFIG_FILE, value: /opt/terraform/provider-mirror.tfrc }
            - { name: GOOGLE_IMPERSONATE_SERVICE_ACCOUNT, value: "{{ .TenantSA }}" }
          resources:
            requests: { cpu: "{{ .CPU }}", memory: "{{ .Memory }}" }        # run class: small 500m/1Gi, large 2/4Gi, xl 4/8Gi
            limits:   { cpu: "{{ .CPU }}", memory: "{{ .Memory }}" }
          securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: [ALL] } }
          volumeMounts:
            - { name: work, mountPath: /work }
            - { name: tmp, mountPath: /tmp }
      volumes:
        - { name: work, emptyDir: { sizeLimit: 4Gi } }
        - { name: tmp, emptyDir: { sizeLimit: 1Gi } }
```

## 3. Runner image

`Dockerfile.runner`:

```dockerfile
# tf-runner: Terraform + OPA + minimal tooling; providers pre-mirrored; non-root; no shell access to secrets
FROM golang:1.23 AS tools
RUN go install github.com/google/go-containerregistry/cmd/crane@latest   # not needed at runtime; placeholder for build tools

FROM debian:bookworm-slim AS base
ARG TERRAFORM_VERSION=1.13.3        # pin exactly; >= 1.10 required (S3 native locking, ephemeral values)
ARG OPA_VERSION=1.9.0               # pin exactly; must match ssp-cp's embedded OPA major
ARG TARGETARCH=amd64
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip jq git && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/tf.zip https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip \
 && unzip /tmp/tf.zip -d /usr/local/bin && rm /tmp/tf.zip
RUN curl -fsSL -o /usr/local/bin/opa https://openpolicyagent.org/downloads/v${OPA_VERSION}/opa_linux_${TARGETARCH}_static && chmod +x /usr/local/bin/opa
# gcs helper: small Go binary (ssp-workers/cmd/gcsutil) doing cp/ls with Workload Identity; avoids installing gcloud
COPY --from=gcsutil /gcsutil /usr/local/bin/gcsutil
# Provider mirror: built in CI by `terraform providers mirror` for the provider set in 40-repos/45-ssp-module-template.md
COPY providers-mirror/ /opt/terraform/providers-mirror/
COPY provider-mirror.tfrc /opt/terraform/provider-mirror.tfrc
COPY runner.sh /usr/local/bin/runner.sh
RUN useradd -u 65532 -r -s /usr/sbin/nologin runner && mkdir -p /work /opt/terraform/plugin-cache && chown -R runner /work /opt/terraform/plugin-cache
USER 65532
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/runner.sh"]
```

`provider-mirror.tfrc`:

```hcl
provider_installation {
  filesystem_mirror {
    path    = "/opt/terraform/providers-mirror"
    include = ["registry.terraform.io/hashicorp/*"]
  }
  direct { exclude = ["registry.terraform.io/*/*"] }   # no registry egress from runs
}
```

`runner.sh` (exit codes: 0 ok, 10 plan gate denied, 20 terraform error, 30 lock error, 40 setup error):

```bash
#!/usr/bin/env bash
set -euo pipefail
KIND="${1:?plan|apply|refresh|import|destroy}"
log(){ printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
finish(){ # $1 state $2 summary-json
  jq -n --arg s "$1" --argjson sum "${2:-{}}" --arg at "$(date -u +%FT%TZ)" --arg run "$RUN_ID" \
     '{run_id:$run,state:$s,summary:$sum,finished_at:$at}' > /work/result.json
  gcsutil cp /work/result.json "${ARTIFACTS_URI}result.json" || true
  gcsutil cp /work/run.log "${ARTIFACTS_URI}run.log" || true
}
trap 'rc=$?; [ $rc -ne 0 ] && finish failed "{\"exit_code\":$rc}"' ERR
exec > >(tee -a /work/run.log) 2>&1

log "run=$RUN_ID attempt=$ATTEMPT kind=$KIND tenant=$TENANT_ID"
# 1. Fetch expected generation (rendered root module) — never modified here
gcsutil cp -r "$EXPECTED_URI" /work/expected/ || { finish failed '{"phase":"fetch"}'; exit 40; }
cd /work/expected
# 2. Init with the LOB bucket backend; impersonate the tenant SA for backend and provider (15-minute tokens)
cat > backend.override.hcl <<EOF
bucket = "${STATE_BUCKET}"
prefix = "${STATE_PREFIX}"
impersonate_service_account = "${TENANT_SA}"
EOF
terraform init -input=false -no-color -lockfile=readonly -backend-config=backend.override.hcl || { finish failed '{"phase":"init"}'; exit 20; }

case "$KIND" in
  plan|refresh|import)
    EXTRA=""; [ "$KIND" = refresh ] && EXTRA="-refresh-only"
    set +e; terraform plan -input=false -no-color -lock-timeout=5m -detailed-exitcode $EXTRA -out=plan.tfplan > plan.txt; rc=$?; set -e
    if [ $rc -eq 1 ]; then grep -qi 'Error acquiring the state lock' plan.txt && { finish failed '{"phase":"plan","class":"lock"}'; exit 30; }; finish failed '{"phase":"plan"}'; exit 20; fi
    terraform show -json plan.tfplan > plan.json
    # 3. Plan-stage policy (SSP-POL-2xx) with the pinned bundle
    gcsutil cp "$POLICY_BUNDLE_URI" /work/policy.tar.gz
    jq -n --arg t "$TENANT_ID" --argjson b "$BATCH_INSTANCES" --slurpfile p plan.json \
      '{stage:"plan",tenant:{tenant_id:$t},batch:{resource_instances:$b},plan:$p[0]}' > policy_input.json
    opa eval -b /work/policy.tar.gz -i policy_input.json -f json 'data.ssp.plan.decision' > policy.json
    RESULT=$(jq -r '.result[0].expressions[0].value.result' policy.json)
    SUMMARY=$(jq -c '{add:([.resource_changes[]?|select(.change.actions|index("create"))]|length),
                       change:([.resource_changes[]?|select(.change.actions|index("update"))]|length),
                       destroy:([.resource_changes[]?|select(.change.actions|index("delete"))]|length),
                       replace:([.resource_changes[]?|select(.change.actions==["delete","create"] or .change.actions==["create","delete"])]|length),
                       changed: ($rc!=0)}' --argjson rc $rc plan.json)
    for f in plan.tfplan plan.txt plan.json policy.json; do gcsutil cp $f "${ARTIFACTS_URI}$f"; done
    if [ "$RESULT" != "allow" ]; then finish denied "$(jq -c --argjson s "$SUMMARY" '.result[0].expressions[0].value + {plan:$s}' policy.json)"; exit 10; fi
    finish succeeded "$SUMMARY"; exit 0 ;;
  apply|destroy)
    # 4. Apply exactly the gated plan file from the plan run (SSP-WF-022)
    gcsutil cp "${PLAN_FROM_RUN}plan.tfplan" /work/expected/plan.tfplan || { finish failed '{"phase":"fetch-plan"}'; exit 40; }
    set +e; terraform apply -input=false -no-color -lock-timeout=5m plan.tfplan > apply.log; rc=$?; set -e
    gcsutil cp apply.log "${ARTIFACTS_URI}apply.log"
    if [ $rc -ne 0 ]; then grep -qi 'Error acquiring the state lock' apply.log && { finish failed '{"phase":"apply","class":"lock"}'; exit 30; }; finish failed '{"phase":"apply"}'; exit 20; fi
    terraform output -json > outputs.json           # worker filters to ServiceSpec.outputs (non-secret) before storing
    gcsutil cp outputs.json "${ARTIFACTS_URI}outputs.json"
    terraform state pull > state.json && jq '{serial, lineage, resources: [.resources[]|{module,type,name,instances:[.instances[]|{attributes:{id:.attributes.id,name:.attributes.name}}]}]}' state.json > observed.json
    gcsutil cp observed.json "${ARTIFACTS_URI}observed.json"; rm -f state.json
    finish succeeded "$(jq -c '{outputs_keys:[keys[]]}' outputs.json)"; exit 0 ;;
esac
```

Requirements:
- SSP-RUN-001 The runner never prints provider credentials; `TF_LOG` is off by default; the worker applies the redaction regex set before exposing logs via the API.
- SSP-RUN-002 Secrets referenced by the rendered module are resolved by Terraform at apply time from Secret Manager data sources or `ephemeral` resources; the runner has no secret env vars.
- SSP-RUN-003 Providers come from the image mirror; a module requiring a provider not in the mirror fails `init` with a clear message (fix = new runner image, T2).
- SSP-RUN-004 Terraform and OPA versions are printed in the first log line and recorded in `result.json`.
- SSP-RUN-005 `plan.tfplan` is valid only against the same state serial; the worker rejects an apply if the plan run is older than 24 h or a newer generation exists.

## 4. Worker (Go, `ssp-workers/cmd/tf-worker`)

```go
// Activity signature (ssp-workers/internal/tfrun/activity.go)
type RunInput struct {
    RunID, Attempt, Kind, TenantID, TenantProject, TenantSA, LobID string
    StateBucket, StatePrefix, ExpectedURI, ArtifactsURI, PlanFromRunURI, PolicyBundleURI string
    BatchInstances []string
    RunClass string // small|large|xl → CPU/Memory
}
type RunResult struct {
    State string `json:"state"` // succeeded|failed|denied
    Summary map[string]any `json:"summary"`
    JobName string `json:"job_name"`
}

func (a *Activities) RunTerraform(ctx context.Context, in RunInput) (*RunResult, error) {
    name := JobName(in.RunID, in.Attempt)                 // "tf-" + hex(sha256(runID+":"+attempt))[:20]
    job, err := a.k8s.BatchV1().Jobs(a.ns).Get(ctx, name, metav1.GetOptions{})
    if apierrors.IsNotFound(err) {                          // first attempt or worker restarted before create
        job, err = a.k8s.BatchV1().Jobs(a.ns).Create(ctx, a.render(in, name), metav1.CreateOptions{})
        if err != nil && !apierrors.IsAlreadyExists(err) { return nil, temporal.NewNonRetryableApplicationError("job create", "K8sError", err) }
    }
    ticker := time.NewTicker(a.pollInterval)              // 30s (D-12)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done():                                  // activity cancelled/timed out → stop the job
            _ = a.k8s.BatchV1().Jobs(a.ns).Delete(context.Background(), name, metav1.DeleteOptions{PropagationPolicy: ptr(metav1.DeletePropagationForeground)})
            return nil, ctx.Err()
        case <-ticker.C:
            job, err = a.k8s.BatchV1().Jobs(a.ns).Get(ctx, name, metav1.GetOptions{})
            if err != nil { activity.RecordHeartbeat(ctx, "get-error"); continue }
            activity.RecordHeartbeat(ctx, map[string]any{"active": job.Status.Active, "job": name})
            if job.Status.Succeeded > 0 || job.Status.Failed > 0 {
                res, rerr := a.readResult(ctx, in.ArtifactsURI)   // result.json written by runner.sh; source of truth, not pod logs
                if rerr != nil { return nil, fmt.Errorf("job finished but no result.json: %w", rerr) }
                res.JobName = name
                switch res.State {
                case "succeeded", "denied": return res, nil       // denied is a business outcome, not an error
                default:
                    if cls, _ := res.Summary["class"].(string); cls == "lock" { return nil, temporal.NewApplicationError("state lock", "LockError") } // retryable
                    return nil, temporal.NewNonRetryableApplicationError("terraform failed", "TerraformError", res.Summary)
                }
            }
        }
    }
}
```

Worker options: `worker.Options{MaxConcurrentActivityExecutionSize: 10, MaxConcurrentActivityTaskPollers: 4}`; activity options set by the reconciler: `StartToCloseTimeout: 90m (plan 30m), HeartbeatTimeout: 2m, RetryPolicy{InitialInterval: 2m, MaximumAttempts: 5, NonRetryableErrorTypes: ["TerraformError","K8sError"]}`. The worker also exposes `/metrics`: `ssp_tf_jobs_active`, `ssp_tf_runs_total{kind,state}`, `ssp_tf_run_duration_seconds{kind}`.

Scaling: start with 2 replicas (20 concurrent runs). Add KEDA's Temporal scaler on task-queue backlog per LOB queue later; node pool autoscaling handles the Jobs.

## 5. Install

```bash
sed -e "s/CP_PROJECT/<CP_PROJECT>/g" -e "s/REGION/<REGION>/g" -e "s/VERSION/<ver>/g" -e "s#KUBE_APISERVER_CIDR#<control-plane-cidr>#g" \
    30-infra/tf-worker/namespace-rbac.yaml 30-infra/tf-worker/networkpolicy.yaml 30-infra/tf-worker/tf-worker-deployment.yaml | kubectl apply -f -
kubectl -n ssp-workers rollout status deploy/tf-worker
```

Verification:
- [ ] `kubectl -n ssp-workers logs deploy/tf-worker` shows `polling task queue tf-runs-default`.
- [ ] Temporal UI → Task queues → `tf-runs-default` shows 2 pollers.
- [ ] A sandbox `refresh` run for a tenant with an empty desired set creates Job `tf-…`, completes, writes `result.json` and the run shows `succeeded` in the control room.
- [ ] Deleting the worker pod mid-run and letting Temporal retry re-attaches to the same Job (same name, no second Job created).
- [ ] Disabling `ssp-tf-runner` makes the next run fail at `init` with a permission error, and the control room banner shows the kill switch engaged.

## 6. Later: callback instead of polling

When polling cost matters, switch `RunTerraform` to **asynchronous activity completion**: the activity returns `activity.ErrResultPending` after creating the Job; the Job's last step calls a small `run-callback` endpoint in `ssp-workers` (in-cluster, mTLS, no public ingress) with the task token stored in the Job's ConfigMap; the endpoint calls `client.CompleteActivity(token, result)`. Keep the poller as a watchdog for lost callbacks.
