# 31 — GKE Platform Layout (existing GCP project and cluster)

Assumptions: one GCP project `<CP_PROJECT>` already exists with a GKE cluster `<CLUSTER>` in region `<REGION>`; Workload Identity is enabled on the cluster (`--workload-pool=<CP_PROJECT>.svc.id.goog`); the VPC has Private Google Access and Private Service Access configured for Cloud SQL. Replace placeholders in angle brackets everywhere.

## 1. Namespaces

| Namespace | Workloads | KSA → GSA (Workload Identity) | Network policy |
|---|---|---|---|
| `temporal` | Temporal server (frontend, history, matching, worker), web UI, admintools, schema jobs | `temporal` → none (DB password via secret) | Ingress 7233 from `ssp-cp`, `ssp-workers`; 8080 from gateway only |
| `ssp-cp` | `ssp-api` Deployment, `ssp-control-worker` Deployment | `ssp-cp-api` → `ssp-cp-api@<CP_PROJECT>` ; `ssp-control-worker` → `ssp-control-worker@<CP_PROJECT>` | Ingress 8080 from gateway and apps; egress to Cloud SQL, GCS, Secret Manager, Temporal, ServiceNow/CMDB endpoints |
| `ssp-workers` | `tf-worker`, `postbuild-worker`, `drift-worker` Deployments | `tf-worker` → `ssp-tf-worker@<CP_PROJECT>` (GCS artifacts read, K8s only); `postbuild-worker` → `ssp-postbuild@<CP_PROJECT>` | Egress to Temporal, GCS, integrations; API server |
| `ssp-runs` | Terraform Jobs only | `tf-runner` → `ssp-tf-runner@<CP_PROJECT>` (**Platform SA**, kill switch) | No ingress; egress to Google APIs (Private Google Access), module/catalog buckets, Secret Manager; **no** egress to Temporal or Postgres |
| `ssp-ui` | Storefront | `ssp-ui` → none | Ingress from gateway |
| `ssp-control-room` | Operator console | none | Ingress from gateway (operator group) |
| `ssp-migrate` | Migration app | none | Ingress from gateway (operator group) |
| `observability` | OTel collector, Prometheus (or managed collection), Grafana | per vendor | — |

SSP-INF-001 Each namespace has a default-deny `NetworkPolicy` for ingress and egress with explicit allows as above (GKE Dataplane V2 or Calico required). SSP-INF-002 Pod Security Standards `restricted` on all namespaces except `ssp-runs`, which uses `baseline` (Terraform needs a writable work dir; still non-root, no privilege escalation).

## 2. Node pools

| Pool | Machine | Autoscaling | Taint / label | Used by |
|---|---|---|---|---|
| existing default | as is | as is | — | Temporal, ssp-cp, ssp-workers, UIs |
| `ssp-runs` | e2-standard-4 (4 vCPU / 16 GiB) | 0 → 20 | taint `ssp.io/runs=true:NoSchedule`, label `ssp.io/pool=runs` | Terraform Jobs only (toleration + nodeSelector in the Job template) |

```bash
gcloud container node-pools create ssp-runs \
  --cluster=<CLUSTER> --region=<REGION> --project=<CP_PROJECT> \
  --machine-type=e2-standard-4 --enable-autoscaling --min-nodes=0 --max-nodes=20 \
  --node-taints=ssp.io/runs=true:NoSchedule --node-labels=ssp.io/pool=runs \
  --workload-metadata=GKE_METADATA --shielded-secure-boot --shielded-integrity-monitoring
```

## 3. Service accounts and IAM

```bash
P=<CP_PROJECT>; POOL="$P.svc.id.goog"
for sa in ssp-cp-api ssp-control-worker ssp-tf-worker ssp-tf-runner ssp-postbuild ssp-inventory; do
  gcloud iam service-accounts create $sa --project=$P --display-name="SSP $sa"; done

# Workload Identity bindings (KSA namespace/name → GSA)
bind(){ gcloud iam service-accounts add-iam-policy-binding "$1@$P.iam.gserviceaccount.com" \
  --role=roles/iam.workloadIdentityUser --member="serviceAccount:$POOL[$2]"; }
bind ssp-cp-api          ssp-cp/ssp-cp-api
bind ssp-control-worker  ssp-cp/ssp-control-worker
bind ssp-tf-worker       ssp-workers/tf-worker
bind ssp-postbuild       ssp-workers/postbuild-worker
bind ssp-tf-runner       ssp-runs/tf-runner

# Project-level roles (control plane project)
gcloud projects add-iam-policy-binding $P --member=serviceAccount:ssp-cp-api@$P.iam.gserviceaccount.com --role=roles/cloudsql.client
gcloud projects add-iam-policy-binding $P --member=serviceAccount:ssp-cp-api@$P.iam.gserviceaccount.com --role=roles/cloudsql.instanceUser
gcloud projects add-iam-policy-binding $P --member=serviceAccount:ssp-cp-api@$P.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor
gcloud projects add-iam-policy-binding $P --member=serviceAccount:ssp-control-worker@$P.iam.gserviceaccount.com --role=roles/cloudsql.client
gcloud projects add-iam-policy-binding $P --member=serviceAccount:ssp-control-worker@$P.iam.gserviceaccount.com --role=roles/pubsub.publisher
# Buckets (see 35-state-buckets.md): catalog read for api/control-worker/runner; artifacts read for tf-worker; expected/runs write for control-worker and runner
```

Tenant onboarding (per tenant project `<T>`; automated by the migration/onboarding workflow, manual for POC):

```bash
gcloud iam service-accounts create ssp-tenant --project=<T>
# Platform SA may mint tokens for the tenant SA (impersonation) — this edge is the kill switch
gcloud iam service-accounts add-iam-policy-binding ssp-tenant@<T>.iam.gserviceaccount.com \
  --member=serviceAccount:ssp-tf-runner@$P.iam.gserviceaccount.com --role=roles/iam.serviceAccountTokenCreator
# Tenant SA gets the roles the catalog services need in its own project (least privilege per service; Spanner example)
gcloud projects add-iam-policy-binding <T> --member=serviceAccount:ssp-tenant@<T>.iam.gserviceaccount.com --role=roles/spanner.admin
gcloud projects add-iam-policy-binding <T> --member=serviceAccount:ssp-tenant@<T>.iam.gserviceaccount.com --role=roles/serviceusage.serviceUsageConsumer
# State prefix access in the LOB bucket is granted with an IAM condition (35-state-buckets.md)
```

SSP-INF-010 The Platform SA (`ssp-tf-runner`) holds **no** project roles anywhere; its only power is `serviceAccountTokenCreator` on tenant SAs plus read on the module/catalog/policy buckets. Disabling it (`gcloud iam service-accounts disable`) stops every run within one token lifetime (≤ 1 h; runs request 15-minute tokens). SSP-INF-011 No service account keys are ever created (org policy `iam.disableServiceAccountKeyCreation` enforced).

## 4. Secrets

- SSP-INF-020 Source of truth is Secret Manager in `<CP_PROJECT>`. Kubernetes Secrets are materialised by the **External Secrets Operator** (`ClusterSecretStore` using Workload Identity) or, for POC, created once with `kubectl create secret`. Nothing is committed.
- Secrets list: `temporal-db-password`, `ssp-db-password` (only if not using IAM DB auth), `servicenow-oauth`, `cmdb-api`, `github-modules-ro` (POC only; prod uses the GCS module mirror), `llm-gateway` (assistant), `oidc-client`.

## 5. Images and deploy

- Artifact Registry: `<REGION>-docker.pkg.dev/<CP_PROJECT>/ssp/{ssp-api,ssp-control-worker,tf-worker,tf-runner,postbuild-worker,drift-worker,ssp-ui,ssp-control-room,ssp-migrate}`; images signed (cosign) and admitted by Binary Authorization in prod.
- Each code repo ships a Helm chart under `deploy/chart/` and env values under `deploy/envs/{sandbox,nonprod,prod}.yaml`. POC: `helm upgrade --install` from CI; next: Argo CD application per repo.
- SSP-INF-030 Ingress: one internal HTTPS load balancer (GKE Gateway API, internal) with hostnames `ssp.<env>.<domain>`, `ssp-cp.<env>.<domain>`, `ops.<env>.<domain>`, `migrate.<env>.<domain>`, `temporal.<env>.<domain>`; corporate SSO (IAP or the enterprise gateway) in front; API Forge / Apigee exposure of `ssp-cp` is a later step (D-19 open item).

## 6. Bootstrap order (see `80-runbooks/81-bootstrap.md`)

1. APIs, node pool, namespaces, network policies. 2. Service accounts and WI bindings. 3. Cloud SQL (34). 4. Buckets (35). 5. Temporal (32). 6. `ssp-cp` migrations + API + control worker. 7. Workers (33). 8. Catalog publish of the first service. 9. UI. 10. First order in sandbox.
