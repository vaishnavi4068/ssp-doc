# 32 — Temporal on GKE: Installation Specification

Self-hosted Temporal (D-11) on the existing GKE cluster, namespace `temporal`, persistence on Cloud SQL for PostgreSQL. Uses the official Helm chart from `https://go.temporal.io/helm-charts` (chart `temporal`; server image `temporalio/server` 1.31.x, web UI 2.52.x at the time of writing — pin the versions you install).

## 1. Prerequisites

| Item | Value |
|---|---|
| Kubernetes | GKE ≥ 1.29, Workload Identity enabled, Dataplane V2 (network policy) |
| Helm | ≥ 3.12 |
| Database | Cloud SQL for PostgreSQL **16**, private IP in the cluster VPC, instance `ssp-temporal-<env>` (separate from the SSP control-plane DB in nonprod/prod; shared instance acceptable in sandbox). See `34-control-plane-postgres.md`. |
| Databases | `temporal` and `temporal_visibility`, owner role `temporal` |
| Secret | Secret Manager `temporal-db-password` → K8s Secret `temporal-db` key `password` in namespace `temporal` |
| DNS/Ingress | internal hostname `temporal.<env>.<domain>` → `temporal-web` 8080 behind SSO (operators only) |

Create the databases (from a bastion or a one-off pod with `psql` and the Cloud SQL private IP):

```sql
create role temporal login password '<from Secret Manager>';
create database temporal owner temporal;
create database temporal_visibility owner temporal;
```

## 2. Namespace, secret, network policy

```bash
kubectl create namespace temporal
kubectl label namespace temporal pod-security.kubernetes.io/enforce=restricted
kubectl -n temporal create secret generic temporal-db \
  --from-literal=password="$(gcloud secrets versions access latest --secret=temporal-db-password --project=<CP_PROJECT>)"
kubectl apply -f 30-infra/temporal/networkpolicy.yaml
```

## 3. Install

```bash
helm upgrade --install temporal temporal \
  --repo https://go.temporal.io/helm-charts \
  --version <CHART_VERSION> \
  --namespace temporal \
  -f 30-infra/temporal/values.yaml \
  --set server.config.persistence.datastores.default.sql.connectAddr=<CLOUDSQL_PRIVATE_IP>:5432 \
  --set server.config.persistence.datastores.visibility.sql.connectAddr=<CLOUDSQL_PRIVATE_IP>:5432 \
  --timeout 900s --wait
```

The chart runs schema create/update Jobs as Helm hooks (`schema.useHelmHooks: true`) because `manageSchema: true` is set on both datastores. `createDatabase: false` because the databases were created above with the right owner.

`30-infra/temporal/values.yaml` (committed; placeholders only for host):

```yaml
# Temporal Helm values for SSP — sandbox sizing; see "Sizing" for nonprod/prod
server:
  image:
    repository: temporalio/server
    tag: 1.31.2            # pin; upgrade deliberately
  replicaCount: 1          # per service unless overridden below
  config:
    logLevel: info
    numHistoryShards: 512  # cannot be changed after first deploy; 512 sandbox/nonprod, 2048 prod (new instance)
    persistence:
      defaultStore: default
      visibilityStore: visibility
      datastores:
        default:
          driver: sql
          sql:
            driverName: postgres12
            pluginName: postgres12
            databaseName: temporal
            connectAddr: "CLOUDSQL_PRIVATE_IP:5432"   # overridden by --set
            connectProtocol: tcp
            user: temporal
            existingSecret: temporal-db
            secretKey: password
            maxConns: 20
            maxIdleConns: 20
            maxConnLifetime: "1h"
            createDatabase: false
            manageSchema: true
            tls:
              enabled: false      # sandbox: private IP only. nonprod/prod: true + caFile (see §6)
        visibility:
          driver: sql
          sql:
            driverName: postgres12
            pluginName: postgres12
            databaseName: temporal_visibility
            connectAddr: "CLOUDSQL_PRIVATE_IP:5432"
            connectProtocol: tcp
            user: temporal
            existingSecret: temporal-db
            secretKey: password
            maxConns: 10
            maxIdleConns: 10
            maxConnLifetime: "1h"
            createDatabase: false
            manageSchema: true
            tls:
              enabled: false
    namespaces:
      create: true
      namespace:
        - name: ssp
          retention: 30d
        - name: ssp-sandbox
          retention: 7d
  frontend:
    replicaCount: 2
    service:
      type: ClusterIP
      port: 7233
    resources: { requests: { cpu: 200m, memory: 512Mi }, limits: { cpu: "1", memory: 1Gi } }
  history:
    replicaCount: 2
    resources: { requests: { cpu: 500m, memory: 1Gi }, limits: { cpu: "2", memory: 2Gi } }
  matching:
    replicaCount: 2
    resources: { requests: { cpu: 200m, memory: 512Mi }, limits: { cpu: "1", memory: 1Gi } }
  worker:
    replicaCount: 1
    resources: { requests: { cpu: 200m, memory: 512Mi }, limits: { cpu: "1", memory: 1Gi } }
  metrics:
    serviceMonitor:
      enabled: false        # true when Prometheus Operator / managed collection is present
  additionalEnv:
    - name: TEMPORAL_ENVIRONMENT
      value: ssp-sandbox
  podSecurityContext: { runAsNonRoot: true, runAsUser: 1000, fsGroup: 1000, seccompProfile: { type: RuntimeDefault } }
  securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: [ALL] }, readOnlyRootFilesystem: true }

schema:
  useHelmHooks: true
  backoffLimit: 10
  ttlSecondsAfterFinished: 86400
  resources: { requests: { cpu: 100m, memory: 256Mi }, limits: { cpu: 500m, memory: 512Mi } }

admintools:
  enabled: true
  resources: { requests: { cpu: 50m, memory: 128Mi }, limits: { cpu: 200m, memory: 256Mi } }

web:
  enabled: true
  image:
    tag: 2.52.0
  replicaCount: 1
  service:
    type: ClusterIP
    port: 8080
  additionalEnv:
    - name: TEMPORAL_UI_PUBLIC_PATH
      value: ""
  resources: { requests: { cpu: 50m, memory: 128Mi }, limits: { cpu: 500m, memory: 512Mi } }

serviceAccount:
  create: true
  name: temporal
```

> If the chart version you install does not support `server.config.namespaces`, create the namespaces with the CLI in §4 instead; keep the rest unchanged.

## 4. Post-install: namespaces, search attributes, verification

```bash
# Health
kubectl -n temporal get pods
kubectl -n temporal exec deploy/temporal-admintools -- temporal operator cluster health --address temporal-frontend:7233

# Namespaces (if not created by values)
kubectl -n temporal exec deploy/temporal-admintools -- temporal operator namespace create --namespace ssp --retention 720h --address temporal-frontend:7233
kubectl -n temporal exec deploy/temporal-admintools -- temporal operator namespace create --namespace ssp-sandbox --retention 168h --address temporal-frontend:7233

# Custom search attributes used by SSP (13-workflows-spec.md SSP-WF-001)
for a in TenantId LobId OrderId RunKind State; do
  kubectl -n temporal exec deploy/temporal-admintools -- \
    temporal operator search-attribute create --namespace ssp --name $a --type Keyword --address temporal-frontend:7233
done

# UI (sandbox): port-forward; nonprod/prod: internal ingress + SSO
kubectl -n temporal port-forward svc/temporal-web 8080:8080
```

Verification checklist (record in the runbook):
- [ ] All `temporal-*` pods Ready; schema hook Jobs `Completed`.
- [ ] `temporal operator cluster health` returns SERVING.
- [ ] Namespace `ssp` listed with retention 30 d; search attributes present (`temporal operator search-attribute list --namespace ssp`).
- [ ] A hello-world workflow from `ssp-cp/cmd/worker --selftest` completes and is visible in the UI.
- [ ] Postgres: tables exist in both databases; connection count < `maxConns` under idle.

## 5. Connection from SSP services

- Address `temporal-frontend.temporal.svc.cluster.local:7233`, namespace `ssp`. Go SDK `client.Dial(client.Options{HostPort: ..., Namespace: "ssp"})`.
- NetworkPolicy in `temporal` allows ingress on 7233 only from namespaces `ssp-cp` and `ssp-workers` (label `kubernetes.io/metadata.name`). `ssp-runs` is **not** allowed (Terraform jobs never talk to Temporal).

`30-infra/temporal/networkpolicy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: temporal-frontend-ingress, namespace: temporal }
spec:
  podSelector: { matchLabels: { app.kubernetes.io/component: frontend } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: ssp-cp } }
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: ssp-workers } }
        - podSelector: {}   # intra-namespace (admintools, web)
      ports: [{ port: 7233, protocol: TCP }]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: temporal-web-ingress, namespace: temporal }
spec:
  podSelector: { matchLabels: { app.kubernetes.io/component: web } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: gke-gateway } }  # or your ingress namespace
      ports: [{ port: 8080, protocol: TCP }]
```

## 6. Hardening for nonprod/prod

| Area | Setting |
|---|---|
| DB TLS | Cloud SQL "require SSL"; mount the server CA (`additionalVolumes`/`additionalVolumeMounts` on `server`) and set `sql.tls.enabled: true`, `sql.tls.caFile: /etc/temporal/certs/server-ca.pem`, `sql.tls.enableHostVerification: false` (Cloud SQL private IP has no hostname) |
| Frontend auth | Enable Temporal authorization with a JWT claim mapper against the corporate IdP for UI/CLI users; internal services keep mTLS-less in-cluster access restricted by NetworkPolicy in Phase 1, mTLS (`server.config.tls`) in Phase 2 |
| Sizing | prod: `numHistoryShards: 2048`, frontend 3, history 3–4, matching 3, worker 2; Cloud SQL 4 vCPU/16 GB HA; `maxConns` 50/20 |
| Archival | Enable history archival to a GCS bucket for the `ssp` namespace (audit); retention stays 30 d in DB |
| Backups | Cloud SQL automated backups + PITR 7 d; quarterly restore test |
| Upgrades | Follow Temporal's one-minor-at-a-time rule; schema update hooks run first; test in sandbox |
| Alerts | `temporal_service_errors_total`, persistence latency p99 > 500 ms, history shard controller lag, task queue backlog per SSP queue |

## 7. Day-2 commands

```bash
# Describe a workflow (order)
temporal workflow describe --namespace ssp --workflow-id order:ord_01J... --address temporal-frontend:7233
# List stuck reconcilers
temporal workflow list --namespace ssp --query 'WorkflowType="TenantReconciler" AND ExecutionStatus="Running"' --address temporal-frontend:7233
# Reset a workflow to last workflow task (incident use only; record in audit)
temporal workflow reset --namespace ssp --workflow-id tenant:gcp:pay-prod-7a1c --type LastWorkflowTask --reason "INC..." --address temporal-frontend:7233
```
