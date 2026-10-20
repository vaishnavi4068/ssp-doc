# 23 — Operator Agent Chat Specification (control room)

Humans give instructions in plain language; the agent turns them into **confirmed, audited platform actions** or grounded answers about the fleet. Same gateway as Sidekick (`ssp-cp/internal/assistant`), surface `control_room`, operator tool set.

## 1. What it can do

| Intent | Example instruction | Tools used | Confirmation |
|---|---|---|---|
| Fleet question | "What's stuck right now?" "How many runs failed in PBM today?" | `ops.fleet`, `ops.tenants`, `runs.list`, `orders.list` | none (read) |
| Explain | "Why did run_… fail?" "Why is tenant X paused?" | `runs.get`, `runs.logs`, `orders.get`, knowledge (`specs`, `runbooks`) | none |
| Scoped control | "Pause all applies in PBM for the next hour because of the Spanner incident" | `ops.pause` (+ `ops.resume` scheduled) | **Blast-radius card** + typed `confirm` |
| Retry | "Retry the failed generation for gcp:pay-prod-7a1c" | `runs.retry` / `ops.reconcile` | confirm |
| Drift triage | "Mark the label drift in claims-ledger as accepted" | `drift.resolve` | confirm |
| Release | "Start the canary wave for spanner 1.3.0 with pay-sandbox and claims-dev" | `releases.createWaves`, `releases.advance` | confirm; `halt` is one word, no confirm |
| Break-glass | "Open break-glass on tenant X until 02:00 for INC0012345" | `ops.breakGlass` | confirm |
| Kill switch | "Disable the platform service account" | `ops.killswitch` | two-person: the agent records the first approval and tells the operator who must confirm |
| Spec change | "The Spanner PU minimum should be 200 for prod" | opens a draft spec-change PR in `ssp-doc` (via GitHub tool) | PR review by humans; nothing changes live |

## 2. Rules

- SSP-OPC-001 The agent acts as the signed-in operator; no action is possible that the operator could not perform in the UI.
- SSP-OPC-002 Every state-changing tool call is preceded by a **Blast-radius card**: scope, tenants affected, runs in flight, orders that will wait, reversal command. The operator types `confirm` (or clicks) within 2 minutes; otherwise the action is dropped.
- SSP-OPC-003 Halt-type actions (`releases.halt`, `ops.pause tenant:<id>` for a single tenant) execute on a single explicit word to keep incident response fast; widening scope (LOB, global) always needs the card.
- SSP-OPC-004 Ambiguous scope ("pause everything") is never resolved by assumption; the agent asks and lists the options.
- SSP-OPC-005 The agent never edits Terraform state, never touches cloud resources directly, never calls `kubectl`; it only calls `ssp-cp` tools.
- SSP-OPC-006 Transcripts are retained 1 year and linked from the audit events they caused.
- SSP-OPC-007 Knowledge answers cite runbooks and requirement ids; "I don't know" with a link to the runbook index is the correct answer when retrieval is empty.
- SSP-OPC-008 Red-team coverage in `ssp-acceptance`: injected instructions in run logs and resource names must never produce an action.

## 3. Shape of a turn (SSE events)

`token` (text), `card` (`blast_radius | fleet_summary | run_explainer | citation`), `tool_call` (name, args summary), `tool_result` (summary), `confirm_required` (action id, expires_at), `done`.

## 4. Scheduled and proactive messages (Phase 3)

The agent may post into the control room feed (not act): SLO breach summaries, stuck-order digests every 30 min during business hours, release wave progress. Each message carries the query it ran so it can be re-run.
