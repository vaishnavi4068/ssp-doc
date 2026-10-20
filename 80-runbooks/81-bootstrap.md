# 81 — Bootstrap Runbook: from an existing GCP project and GKE cluster to the first order

Target: a sandbox where one buyer orders a `gcp.gcs-bucket` or `gcp.spanner-instance` through the storefront and it reaches Observed. Every step names the spec it implements and the check that proves it.

| # | Step | Spec | Command / action | Check |
|---|---|---|---|---|
| 1 | Enable APIs | 31 | `gcloud services enable container.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com cloudkms.googleapis.com cloudasset.googleapis.com artifactregistry.googleapis.com iamcredentials.googleapis.com pubsub.googleapis.com storage.googleapis.com --project=<CP_PROJECT>` | all listed as enabled |
| 2 | Node pool `ssp-runs` | 31 §2 | command in 31 §2 | pool exists, 0 nodes idle |
| 3 | Namespaces + network policies | 31 §1, 32 §2, 33 §2 | `kubectl apply -f 30-infra/tf-worker/namespace-rbac.yaml`; create `temporal`, `ssp-cp`, `ssp-workers`, `ssp-ui` namespaces; apply network policies | `kubectl get netpol -A` shows default-deny in `ssp-runs` |
| 4 | Service accounts + Workload Identity | 31 §3 | script in 31 §3 | `gcloud iam service-accounts list` shows 6 SAs; WI bindings present |
| 5 | Secret Manager secrets | 31 §4 | create `temporal-db-password`, `oidc-client`, (POC) `github-modules-ro` | versions exist |
| 6 | Cloud SQL | 34 | commands in 34 §1; create DBs `ssp`, `temporal`, `temporal_visibility` | `gcloud sql instances describe` → RUNNABLE, private IP |
| 7 | Buckets + KMS (sandbox LOB `sbx` in CP project) | 35 | commands in 35 §1 for `ssp-state-sbx`, plus `ssp-catalog-sandbox`, `ssp-modules-sandbox`, `ssp-corpus-sandbox` | buckets exist with CMEK, versioning, PAP |
| 8 | Temporal | 32 | `helm upgrade --install …` from 32 §3; post-install from §4 | cluster health SERVING; namespace `ssp`; search attributes listed |
| 9 | Artifact Registry + first images | 31 §5 | `gcloud artifacts repositories create ssp --repository-format=docker --location=<REGION>`; build and push `ssp-api`, `ssp-control-worker`, `tf-worker`, `tf-runner`, `ssp-ui` | images listed |
| 10 | `ssp-cp` migrate + deploy | 42, 34 §3 | `helm upgrade --install ssp-cp deploy/chart -f deploy/envs/sandbox.yaml -n ssp-cp` (pre-upgrade hook runs migrations) | `/readyz` 200; tables exist |
| 11 | Workers | 33 §5 | apply `tf-worker-deployment.yaml` (and later post-build/drift) | Temporal UI shows pollers on `tf-runs-default` |
| 12 | First tenant (sandbox project) | 31 §3 tenant onboarding, 35 §1 per-tenant grant | create `ssp-tenant@<T>`; token-creator for Platform SA; prefix IAM on `ssp-state-sbx`; insert `lob` and `tenant` rows (`catalogctl tenant add` or SQL) | `GET /v1/destinations` lists it for a test principal |
| 13 | Entitlements + test principal | 10 §1 | `entitlements.yaml` with the test user → APM | `GET /v1/destinations` as that user returns the tenant |
| 14 | First module bundle | 45, 15 | tag `ssp-module-gcs-bucket v0.1.0` (or spanner); release workflow publishes to `ssp-catalog-sandbox`; `POST /v1/admin/catalog/reload` | `GET /v1/catalog/services` shows it |
| 15 | Policy baseline bundle | 14, 42 | `make bundle-policy` in ssp-cp | digest visible in `GET /v1/ops/policy/impact` |
| 16 | UI | 44 | `helm upgrade --install ssp-ui …`; OIDC client configured | Home renders SKUs and destination |
| 17 | Empty refresh run | 33 §5 verification | `POST /v1/ops/tenants/<t>/drift-scan` | Job `tf-…` completes; `result.json` present |
| 18 | **First order** | 10 §5 | In the storefront: Configure & Buy → Place order | Order reaches `observed`; resource visible in `GET /v1/tenants/<t>/resources`; state object in bucket |
| 19 | Re-attach test | 33 §5 | delete `tf-worker` pod during an apply | same Job name, order still observed |
| 20 | Kill-switch test | 31 §3 SSP-INF-010 | `gcloud iam service-accounts disable ssp-tf-runner@…`; place an order | run fails at init with permission error; control room banner; re-enable |

Record the date, operator and output of each check in `80-runbooks/bootstrap-log-<env>.md` (that file is the evidence that sandbox exists as specified).

## Order of code work that unblocks the runbook

1. `ssp-cp`: migrations, catalog loader, `/catalog`, `/destinations`, `preflight`, `orders`, `OrderWorkflow` + `TenantReconciler` + render + `CreateRun/CaptureObserved` activities (tasks T-0002…T-0010).
2. `ssp-workers`: `tf-worker` + runner image + `gcsutil` (T-0011…T-0013).
3. `ssp-module-gcs-bucket` or `ssp-module-spanner`: module + catalog + release workflow (T-0014).
4. `ssp-ui`: shell, Home, Checkout with renderer, Order page (T-0015…T-0018).
5. Control room fleet page and kill switch (T-0019); Sidekick inquire/provision (T-0021).
