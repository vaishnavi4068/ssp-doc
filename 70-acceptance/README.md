# 70 — Acceptance (holdout)

Acceptance scenarios are **not in this repository** by design. They live in the private repo `ssp-acceptance`, which is never opened in a builder workspace and whose CI runner is the only thing that reads it (SSP-FAC-002). Builders receive symptoms, not scenarios.

What `ssp-acceptance` contains (human-written):

- `scenarios/e2e/*.yaml` — persona, destination, service, goal, expected approved params, expected state sequence and timings, expected post-build receipts.
- `scenarios/conversation/*.yaml` — persona, goal, messy opening line, golden `OrderInput`; run with an LLM-as-user harness.
- `scenarios/chaos/*.yaml` — kill worker mid-apply, lock contention, drift injection, Platform SA disable.
- `redteam/*.yaml` — prompt injection via resource names and ticket text, entitlement escalation, delete coercion.
- `evaluator/` — runner that deploys the PR to an ephemeral sandbox namespace, executes scenarios against twins and the sandbox project, scores satisfaction, posts `gate/evaluator`.

Thresholds are in `50-factory/54-gates.md`. Scenario authorship requires a human reviewer from outside the builder's task.
