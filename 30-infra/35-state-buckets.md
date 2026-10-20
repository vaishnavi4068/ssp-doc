# 35 — State, Catalog and Artifact Buckets

Expected and Observed live in object storage, one bucket per LOB (D-06, D-07), one state prefix per tenant boundary (D-08). This is also where the blast-radius decision (G-0008) is implemented.

## 1. Buckets

| Bucket | Project | Purpose | Access |
|---|---|---|---|
| `ssp-state-<lob>` | LOB host project (sandbox: `<CP_PROJECT>`) | `<tenant>/terraform.tfstate`, `expected/`, `runs/` | Tenant SA: objectAdmin **on its own prefix** (IAM condition). Control worker: objectCreator on `expected/*` and objectViewer on `runs/*` for all prefixes. Nobody else. |
| `ssp-catalog-<env>` | `<CP_PROJECT>` | Catalog bundles, `index.json`, policy bundles | ssp-cp-api, control worker, tf-runner (Platform SA), UI via API: objectViewer. Publisher (module CI): objectCreator |
| `ssp-modules-<env>` | `<CP_PROJECT>` | `module.zip` mirror per `ssp-module-<service>` version | Platform SA objectViewer (runners fetch modules through impersonated tenant SA? No: modules are platform artifacts; grant objectViewer to **tenant SAs via the LOB group**) |
| `ssp-corpus-<env>` | `<CP_PROJECT>` | Sanitized tenant states, historical request inputs and plan JSONs for gates | CI service account only |
| `ssp-temporal-archive-<env>` | `<CP_PROJECT>` | Temporal history archival | Temporal SA |

```bash
LOB=pbm; P=<LOB_HOST_PROJECT>; KEY=projects/$P/locations/<REGION>/keyRings/ssp-$LOB/cryptoKeys/state
gcloud kms keyrings create ssp-$LOB --location=<REGION> --project=$P
gcloud kms keys create state --keyring=ssp-$LOB --location=<REGION> --purpose=encryption --project=$P --rotation-period=90d --next-rotation-time=+90d
gcloud storage buckets create gs://ssp-state-$LOB --project=$P --location=<REGION> \
  --uniform-bucket-level-access --default-encryption-key=$KEY --public-access-prevention --soft-delete-duration=30d
gcloud storage buckets update gs://ssp-state-$LOB --versioning
gcloud storage buckets update gs://ssp-state-$LOB --lifecycle-file=35-state-lifecycle.json   # keep 50 noncurrent versions, delete runs/ older than 180 d
# Allow the bucket's service agent to use the key
gcloud kms keys add-iam-policy-binding state --keyring=ssp-$LOB --location=<REGION> --project=$P \
  --member=serviceAccount:$(gcloud storage service-agent --project=$P) --role=roles/cloudkms.cryptoKeyEncrypterDecrypter
```

Per-tenant grant (IAM condition on the object prefix), run by the onboarding workflow:

```bash
T=<tenant project>; LOB=pbm
gcloud storage buckets add-iam-policy-binding gs://ssp-state-$LOB \
  --member=serviceAccount:ssp-tenant@$T.iam.gserviceaccount.com --role=roles/storage.objectAdmin \
  --condition="expression=resource.name.startsWith(\"projects/_/buckets/ssp-state-$LOB/objects/$T/\"),title=tenant-$T-prefix"
# The tenant SA must also be able to list within its prefix for the backend's lock handling
gcloud storage buckets add-iam-policy-binding gs://ssp-state-$LOB \
  --member=serviceAccount:ssp-tenant@$T.iam.gserviceaccount.com --role=roles/storage.legacyBucketReader \
  --condition="expression=resource.name.startsWith(\"projects/_/buckets/ssp-state-$LOB/objects/$T/\"),title=tenant-$T-list"
```

## 2. Blast-radius model (resolves the session's open contradiction)

| Threat | Control |
|---|---|
| Compromise of one tenant SA | Reaches only its own prefix (IAM condition) and its own project roles |
| Compromise of the Platform SA | Can mint tokens for tenant SAs (that is its job) but holds no bucket or project roles itself; disabling it is one command; every impersonation is logged (`iam.googleapis.com` GenerateAccessToken audit logs) with the run id in the token's justification |
| Compromise of the LOB bucket | Objects are CMEK-encrypted with the LOB key in the LOB project; secrets are kept out of state (SSP-PRIN-004), so a state file leak exposes configuration, not credentials |
| Operator mistake | Versioning + soft delete; `terraform state` surgery only via a runbook with a recorded run |
| Cross-LOB access | Nothing has roles on more than one LOB bucket except the control worker's narrow `expected/` writer role, which is per-bucket and reviewed quarterly |

SSP-BKT-001 No principal other than the control worker has a role on a whole state bucket. SSP-BKT-002 The lifecycle rule never deletes current versions of `terraform.tfstate`. SSP-BKT-003 Bucket IAM is itself Terraform-managed from `ssp-foundation`-style code in `ssp-cp/deploy/foundation/` (T3), not by hand after sandbox.

## 3. AWS and Azure equivalents (for later)

| | AWS | Azure |
|---|---|---|
| Bucket | `s3://ssp-state-<ou>` in the per-OU host account, SSE-KMS with the OU key, versioning, Object Lock off, `use_lockfile = true` in the backend (Terraform ≥ 1.10; no DynamoDB) | Storage account `sspstate<mg>` with blob versioning, CMK, lease-based locking native to the `azurerm` backend |
| Tenant identity | IAM role `ssp-tenant` in each account, trust policy allowing the platform role (via Workload Identity Federation from GKE) to assume with an external id per run | Managed identity per subscription; federated credential trusting the GKE OIDC issuer |
| Prefix isolation | Bucket policy conditions on `s3:prefix` / object key prefix per account role | Container per subscription with RBAC at container scope |
