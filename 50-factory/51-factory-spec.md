# 51 — Software Dark Factory Specification

How the platform, the apps, future services and migrations get built: humans write the specs in this repo and the holdout scenarios in `ssp-acceptance`; agents (Cursor agents in the IDE and in CI, Claude Code GitHub Actions for review) write the code; gates decide merges; humans approve by tier (D-18, SSP-PRIN-009).

## 1. Flow of one change

```
Spec change (ssp-doc PR, human) ─► Task (90-tasks/, human or Spec Scribe) ─► Builder (Cursor agent on agent/<task> branch)
   ─► PR ─► Gates (CI) ─► Reviewer (fresh-context agent review) ─► Evaluator (holdout scenarios, T1+) ─► merge rule by tier ─► Release
```

- SSP-FAC-001 No code change without a task; no task without spec IDs; no spec ID without a verification method.
- SSP-FAC-002 Builders see `ssp-doc` and the target repo only. They never see `ssp-acceptance`. Evaluator failures come back as symptoms ("order for Tier 1 Spanner ended regional, expected multi-region"), never as scenario text.
- SSP-FAC-003 Agents work on `agent/<task-id>-<slug>` branches with the role's GitHub App identity; commits carry `Task: <id>` and `Spec: <ids>` trailers.
- SSP-FAC-004 Retry budget: a builder may push up to 3 fix iterations after gate failures; then the PR goes to draft with a failure summary and the task is flagged for a human.
- SSP-FAC-005 Tokens per merged change and gate first-pass rate are recorded per task (Factory Steward dashboard).

## 2. Roles

| Role | Where it runs | Reads | Writes | Credentials |
|---|---|---|---|---|
| **Spec Scribe** | Cursor (human-driven) or scheduled | Transcripts, stakeholder docs, this repo | Draft ADRs and tasks as PRs to `ssp-doc` | none |
| **Spec Critic** | Claude Code GitHub Action on `ssp-doc` PRs | `ssp-doc` | Review comments: contradictions with the decisions register, untestable requirements, missing owners/IDs | none |
| **Planner** | Cursor, first step of a task | task + cited specs | Context pack in the PR description: files to touch, interfaces, tests to write first | none |
| **Test Author** | Cursor (same session, before implementation) | specs | Tests citing requirement IDs; replay histories; Rego tests | none |
| **Builder** | Cursor agent (IDE or background) | context pack, target repo | Code, generated artifacts | sandbox only (twins, sandbox project via CI) |
| **Reviewer** | Claude Code GitHub Action on PRs (fresh context, different model where possible) | PR diff + cited specs | Advisory review: least privilege, secrets, idempotency, determinism, spec deviations | none |
| **Scenario Evaluator** | CI job from `ssp-acceptance` (private runner) | holdout scenarios, sandbox environment | Status check + symptom report | ephemeral sandbox |
| **Chaos / Red Team** | Nightly in sandbox | — | Issues: killed pods mid-apply, lock contention, injected drift, prompt injection in resource names | sandbox |
| **Release** | CI on tag | bundles, CHANGELOG | Evidence pack, CR draft, wave plan | publish to catalog bucket |
| **Ops Sentinel** | Scheduled (Phase 3) | fleet metrics, failures | Tickets, spec-change proposals | read-only |
| **Factory Steward** | Weekly | all PR/gate data | PRs to `50-factory/` rules and tasks templates | none |

## 3. Cursor setup (what to put in each repo)

- `AGENTS.md` at the repo root (templates in `cursor-rules/`), read by Cursor agents and by Claude Code.
- `.cursor/rules/00-ssp-common.mdc` (always applied) + repo-specific `.mdc` files scoped by glob (e.g. `internal/workflows/**` → Temporal determinism rules).
- A `docs/specs` git submodule or a CI-synced copy of `ssp-doc` inside each repo so agents can read specs offline (`make sync-specs`).
- Task files are pasted or linked as the first message; the agent must begin by restating the spec IDs and the acceptance criteria (Planner step).
- Cursor **Background Agents** (or the IDE agent) may run `make generate lint test`; they must not run `terraform apply`, `kubectl apply` or `helm upgrade` against anything but kind/twins. CI owns real environments.
- PR review automation: install the Claude Code GitHub Action with the Reviewer and Spec Critic prompts (`cursor-rules/review-prompt.md`); Cursor's own PR review bot may run in addition.

## 4. Gates (summary; full list in `54-gates.md`)

Deterministic first: format/lint/vuln/secret scans; generated-code diff; unit and replay tests; OpenAPI no-break; schema compatibility; `catalogctl validate`; Rego tests and policy-impact; blast-radius plan against the corpus; traceability (every MUST ID in the task has a test); a11y and visual regression for UIs; then Reviewer; then Evaluator for T1+.

## 5. Holdout acceptance (`ssp-acceptance`, human-owned)

- End-to-end scenarios in YAML: persona, destination, service, goal, expected approved params, expected states and timings, expected post-build receipts.
- Conversational scenarios (SSP-CHAT §5) with golden `OrderInput`.
- Chaos scenarios: kill `tf-worker` during apply → same Job re-attached and order still reaches Observed; two orders for one tenant → serialized, both Observed; policy relaxation PR → gate T3.
- Scoring is probabilistic for conversational and timing-sensitive scenarios: `satisfaction = passing trajectories / total`; thresholds per tier in `54-gates.md`.

## 6. Factory for *future builds and migrations*

The same loop builds new services and migrations:
- **New service**: human writes `E-<SVC>-0001` ADR + task "create ssp-module-<svc>"; builder generates the repo from `45-ssp-module-template.md`; gates + T1 evaluator; release publishes the bundle; the storefront shows it without a deploy.
- **Migration of an app**: operator runs `ssp-migrate`; where mapping needs a new `import/mapping.yaml` entry or a new service, a task is created and built by the loop; the migration itself is executed by the platform, never by an agent with cloud credentials.
- **Platform change**: spec PR → tasks across `ssp-cp`/`ssp-workers`/`ssp-ui` with cross-repo contract checks (41-repo-map.md).

## 7. Decide before scaling the factory

- Approved models for CVS content (builder, reviewer, evaluator, assistant) and the token budget per merged change.
- Human review remains at T2/T3; the evidence pack (gates, reviewer notes, scenario scores, policy impact) is generated for every merge for audit.
- Corpus hygiene: the sanitizer that produces `ssp-corpus` is itself T3 and reviewed by security.
