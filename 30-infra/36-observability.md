# 36 — Observability

## 1. Pipeline

- OpenTelemetry SDKs in every Go service and worker (traces, metrics, logs via `slog` handler); OTel Collector (DaemonSet, namespace `observability`) exports traces to Cloud Trace, metrics to Google Cloud Managed Service for Prometheus (or the enterprise Prometheus), logs to Cloud Logging with a sink to the SIEM.
- Temporal server metrics scraped (ServiceMonitor or managed collection), Temporal Web for workflow inspection, Grafana dashboards: *SSP Fleet*, *Reconciler queues*, *Runs*, *Temporal health*, *API*.
- Correlation: every log line and span carries `order_id`, `run_id`, `tenant_id`, `workflow_id` when known; the API returns `X-Request-Id` and the UI shows it on error toasts.

## 2. Metrics (names are binding)

| Metric | Type | Labels | Source |
|---|---|---|---|
| `ssp_orders_total` | counter | `kind,state,service_id,lob` | ssp-cp |
| `ssp_order_state_duration_seconds` | histogram | `from,to,service_id` | ssp-cp (events) |
| `ssp_preflight_duration_seconds` | histogram | `service_id,result` | ssp-cp |
| `ssp_policy_decisions_total` | counter | `stage,result,rule_id` | ssp-cp, runner (via result.json) |
| `ssp_reconciler_queue_depth` / `_oldest_seconds` | gauge | `tenant_id,lob` | control worker (workflow query exporter) |
| `ssp_tf_runs_total` | counter | `kind,state,lob` | tf-worker |
| `ssp_tf_run_duration_seconds` | histogram | `kind,run_class` | tf-worker |
| `ssp_tf_jobs_active` | gauge | `lob` | tf-worker |
| `ssp_drift_findings_open` | gauge | `class,lob` | drift worker |
| `ssp_postbuild_steps_total` | counter | `step,state` | postbuild worker |
| `ssp_controls_paused` | gauge | `scope` | ssp-cp |
| `ssp_platform_sa_enabled` | gauge | — | ssp-cp (IAM poll every 60 s) |
| `ssp_assistant_turns_total` | counter | `surface,intent,outcome` | ssp-cp |

## 3. SLOs and alerts

| SLO | Target | Alert |
|---|---|---|
| Order → Approved (no gate) | p95 < 60 s over 7 d | burn rate > 2 for 1 h |
| Approved → Observed, Phase 1 services | p95 < 20 min | burn rate > 2 for 1 h |
| API availability | 99.9 % | 5xx ratio > 0.5 % for 10 min |
| Run success rate (excluding policy denies) | > 97 % | < 95 % over 1 h |
| Reconciler queue age | p95 < 5 min | any tenant > 30 min |
| Drift scan freshness | every tenant scanned < 12 h | tenant unscanned > 24 h |
| Platform SA | enabled unless incident | flips to disabled → page |

## 4. Logs and redaction

- SSP-OBS-001 Structured JSON only; no `fmt.Println`. Levels: debug off in prod.
- SSP-OBS-002 Redaction set (regexes for tokens, keys, passwords, connection strings) applied in the runner before upload and in the API before serving logs; a unit test asserts each pattern.
- SSP-OBS-003 Audit events are written to Postgres **and** emitted as logs with `audit=true` for the SIEM sink; retention 7 years in the archive.

## 5. Dashboards delivered with the platform

`ssp-cp/deploy/dashboards/*.json` (Grafana) and `30-infra/observability/alerts.yaml` (PrometheusRule) are part of the release; the control room links to them by URL.
