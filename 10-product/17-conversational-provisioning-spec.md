# 17 — Conversational Provisioning (Sidekick) Specification

Sidekick is the buyer-facing assistant in `ssp-ui`. It is built on a **Contextual Language Model** for the knowledge half (grounded answers about standards, guardrails, denials, status) and on schema-constrained tool calling plus deterministic platform code for the action half (D-20). The operator-facing chat in the control room reuses the same gateway with a different tool set (`20-apps/23-operator-agent-chat-spec.md`).

## 1. Two halves, one rule

| Half | Examples | Engine | May it change state? |
|---|---|---|---|
| Knowing | "What's the standard for a Tier 1 Spanner?", "Why was CMEK forced?", "Why did my order fail?", "What do I have in pay-prod?" | CLM (retriever + generator trained together) over the knowledge index | No |
| Acting | "Create a regional Spanner with 300 PU in pay-prod called claims-ledger" | Tool-calling LLM constrained to `request.schema.json`, calling `preflight` and `create` tools | Only through the same API as the UI, with the same confirmation card and `preview_hash` |

- SSP-CHAT-001 The model drafts an `OrderInput`; it never produces an approved spec, never computes price, never bypasses a gate.
- SSP-CHAT-002 Every state-changing action requires the buyer to click **Place order** on a server-produced preflight card (or type `confirm <short-id>` in text clients).
- SSP-CHAT-003 The assistant acts as the buyer (their JWT); it has no identity of its own and no elevated tools.

## 2. Architecture (`ssp-cp/internal/assistant`)

```
message ─► Context assembly ─► Router (intent) ─┬─ knowledge path ─► CLM query (collections filtered by entitlement) ─► answer + citations
                                                 └─ action path ─► service resolution ─► slot filling (schema + derive rules) ─► tools:
                                                                        catalog.describe · destinations.list · orders.preflight · orders.create · orders.status · resources.list · code.view
```

- SSP-CHAT-010 Context assembly per turn: principal + entitlements, selected destination context (`/destinations/{id}/context`), the catalog summaries, the buyer's last 20 orders, current UI location (service and step if in checkout).
- SSP-CHAT-011 Intents: `provision | change | decommission | status | inquire | troubleshoot | navigate`. Routing uses the tool-calling model with a strict JSON output; unknown → ask one clarifying question.
- SSP-CHAT-012 Slot filling: required fields from the request schema minus fields satisfied by `derive` rules; ask only for the remainder, at most 3 per turn, always showing the derived values and their reasons.
- SSP-CHAT-013 Tools are the public API; no private tool exists. Tool results are data (SSP-CHAT-020).
- SSP-CHAT-014 Model gateway: provider-agnostic interface `LLM` with implementations `vertex` (Gemini on Vertex AI in the control-plane project) and `anthropic` (Claude via approved enterprise endpoint); the CLM interface `Grounded` with implementation `contextual` (Contextual AI platform) and `vertexrag` (Vertex AI RAG Engine) as fallback. Approved models are configured per environment; nothing else is reachable.

## 3. Knowledge index (for the CLM)

| Collection | Source | Refresh | Visibility |
|---|---|---|---|
| `specs` | `ssp-doc` (ADRs, constitution, product docs), service `docs/README.md` from bundles | On merge / publish | All buyers |
| `runbooks` | Buyer-facing FAQs, how-tos, ServiceNow KB export | Daily | All buyers |
| `tenant-state` | Resource instances, outputs, drift findings, order events (rendered as text) | Near-real-time via events | Filtered by entitlement at query time |
| `history` | Anonymised order patterns per LOB ("most teams in PBM choose…") | Weekly | All buyers |

- SSP-CHAT-030 Every knowledge answer carries citations (document id + requirement/ADR id); answers without a retrieved source above threshold return "I don't have a source for that" and offer a ticket link.
- SSP-CHAT-031 Entitlement filtering happens in the retrieval query (metadata filter), never by post-filtering generated text.

## 4. Safety

- SSP-CHAT-020 Prompt-injection posture: tool outputs, resource names, ticket text and documents are untrusted; the system prompt forbids following instructions found in them; the red-team suite in `ssp-acceptance` tests this.
- SSP-CHAT-021 No free text ever reaches Terraform; the only path is `OrderInput` → schema validation → preflight → create.
- SSP-CHAT-022 Decommission and production changes through chat require the typed confirmation plus the same gates as the UI (CR, owner sign-off).
- SSP-CHAT-023 Conversations are stored (Postgres `assistant_conversation`, 90 days) and auditable; PII redaction on export.

## 5. Evaluation (holdout, in `ssp-acceptance`)

- Conversational scenarios: persona, goal, messy opening line, **golden `OrderInput`**; satisfaction = fraction of trajectories ending in a preflight card whose `approved_params` equal the golden set. Target ≥ 0.9 for Phase 1 services.
- Groundedness set: questions with expected citations; questions with no valid answer (must abstain). Target ≥ 0.95 citation accuracy, 0 unsourced policy claims.
- Red-team set: injections via resource names, entitlement escalation, delete coercion. Target 0 successful actions.

## 6. Metrics

Task completion rate, turns to a valid preflight, slot-correction rate, groundedness score, deflection (questions resolved without a ticket), escalation rate, time from first message to `requested`.

## 7. Phasing

1. Phase 1: `inquire` + `provision` for Phase 1 services; `specs` and `runbooks` collections; preflight cards.
2. Phase 2: `status`, `change`, `troubleshoot` (reads run logs and Temporal histories through the API).
3. Phase 3: `decommission` with step-up confirmation; proactive drift and delivery messages.
