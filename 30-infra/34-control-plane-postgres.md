# 34 — Control-Plane Postgres (Cloud SQL)

Holds Requested and Approved plus pointers and audit (D-03). Never Terraform state, never secrets.

## 1. Instances

| Env | Instance | Tier | HA | Databases |
|---|---|---|---|---|
| sandbox | `ssp-sandbox` | db-custom-2-7680 | zonal | `ssp`, `temporal`, `temporal_visibility` (shared to save cost) |
| nonprod | `ssp-nonprod`, `ssp-temporal-nonprod` | db-custom-2-7680 | regional | split as named |
| prod | `ssp-prod`, `ssp-temporal-prod` | db-custom-4-16384 | regional | split as named |

```bash
gcloud sql instances create ssp-sandbox --project=<CP_PROJECT> --database-version=POSTGRES_16 --region=<REGION> \
  --tier=db-custom-2-7680 --network=projects/<CP_PROJECT>/global/networks/<VPC> --no-assign-ip \
  --enable-google-private-path --database-flags=cloudsql.iam_authentication=on,max_connections=400 \
  --backup-start-time=03:00 --enable-point-in-time-recovery --retained-backups-count=7 --deletion-protection
gcloud sql databases create ssp --instance=ssp-sandbox
gcloud sql users create ssp-cp-api@<CP_PROJECT>.iam --instance=ssp-sandbox --type=cloud_iam_service_account
gcloud sql users create ssp-control-worker@<CP_PROJECT>.iam --instance=ssp-sandbox --type=cloud_iam_service_account
gcloud sql users create temporal --instance=ssp-sandbox --password="$(gcloud secrets versions access latest --secret=temporal-db-password)"
```

## 2. Access model

- SSP-DB-001 `ssp-cp` connects with **IAM database authentication** through the Cloud SQL Go connector (`cloud.google.com/go/cloudsqlconn`, `WithIAMAuthN()`), using the pod's Workload Identity; no password, no proxy sidecar.
- SSP-DB-002 Temporal uses the `temporal` role with a password (Temporal does not support IAM auth); the password lives in Secret Manager and rotates quarterly (rotation runbook updates the K8s secret and restarts Temporal pods).
- SSP-DB-003 Private IP only; `authorized networks` empty; Cloud SQL Auth Proxy used by humans from the bastion for break-glass access, audited.
- SSP-DB-004 Roles inside `ssp`: `ssp_app` (DML on `ssp.*`), `ssp_migrate` (DDL, used only by the migration Job), `ssp_readonly` (control room analytics, auditors). The API runs as `ssp-cp-api@…iam` granted `ssp_app`.

## 3. Migrations

- `ssp-cp/db/migrations/*.sql` applied by `goose` from a Kubernetes Job (`ssp-cp/cmd/migrate`) in the release pipeline before the API rollout; forward-only; every migration has a rollback migration file.
- Partitioning: `order_event` and `audit_event` partitioned monthly (`pg_partman` or native with a monthly creation job).

## 4. Operations

| Topic | Setting |
|---|---|
| Backups | Automated daily + PITR 7 days; monthly restore test into `ssp-restore-test` |
| Monitoring | Cloud SQL insights on; alerts on CPU > 80 % 10 min, connections > 80 % max, replication lag (prod), disk > 80 % |
| Maintenance | Window Sunday 03:00 local; deny period during release freezes |
| Connection limits | API pool max 20 per replica; control worker 10; `max_connections` sized for 3× peak |
| Data retention | `order_event` 2 years, `audit_event` 7 years (export to BigQuery monthly for long tail) |
