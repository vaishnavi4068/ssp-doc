# 16 — Storefront UI Specification (`ssp-ui`)

Visual and interaction reference: prototype **Gemini 4 Argon / shadcn-stack / #17 "Shopify Polaris Infrastructure Storefront"** in the TAXI prototype gallery (Next.js + Tailwind + shadcn). This spec turns that prototype into a template-driven product: every service screen is rendered from the catalog bundle, never hand-coded (D-17, SSP-PRIN-007).

## 1. Stack (binding)

| Concern | Choice |
|---|---|
| Framework | Next.js 15 (App Router), TypeScript strict, React 19 |
| Styling | Tailwind CSS v4 + shadcn/ui (Radix primitives); CSS variables for tokens; dark mode via `class` |
| Data | TanStack Query for REST; native `EventSource` for SSE; no global state library |
| Forms | Schema renderer (own package `@ssp/form-renderer`) driven by `request.schema.json` + `ui.yaml`; validation with Ajv 2020 in the browser, authoritative validation server-side (preflight) |
| Auth | Auth.js (OIDC) → session holds the API JWT; API calls go through a Next route handler proxy that attaches the token (browser never sees the raw token) |
| Icons / font | lucide-react; Inter (UI) + JetBrains Mono (ids, prices, code) |
| Tests | Vitest + Testing Library; Playwright e2e against the twin-backed sandbox API; Storybook for the renderer |
| Build | Standalone output in a distroless image; deployed to GKE namespace `ssp-ui` behind the internal gateway |

## 2. Design tokens (derived from the prototype)

```css
:root {
  --background: 220 20% 97%;        /* page: soft gray (#f5f6f9) */
  --card: 0 0% 100%;                /* white cards */
  --border: 220 14% 90%;            /* #e3e6eb hairlines */
  --foreground: 222 20% 12%;        /* #1a1d23 text */
  --muted-foreground: 220 9% 46%;
  --primary: 161 62% 28%;           /* storefront green #1b7a5a (buttons, active nav, section labels) */
  --primary-foreground: 0 0% 100%;
  --accent: 161 50% 94%;            /* pale green chips / selected radio card */
  --warning: 38 92% 50%;
  --destructive: 0 72% 51%;
  --ring: 161 62% 28%;
  --radius: 0.75rem;                /* 12px cards, 8px inputs, 999px pills */
}
.dark { --background: 222 18% 9%; --card: 222 16% 12%; --border: 222 12% 20%; --foreground: 220 20% 95%; --primary: 161 55% 45%; --accent: 161 30% 18%; }
```

Typography: Inter 14 px base, 24–28 px page titles (semibold), 11 px uppercase tracking-wide section labels in `--primary` ("DELIVERY DESTINATIONS", "ITEMIZED MONTHLY CHARGES"), JetBrains Mono for identifiers, field keys, prices and code. Spacing on an 8 px grid; card padding 20–24 px; max content width 1280 px.

## 3. Application shell

```
┌ top bar (56px) ───────────────────────────────────────────────────────────────────────────┐
│ [menu]  SSP Cloud Store   [ Delivery destination ▾ ]   [Search SKUs, destinations, orders ⌘K ]   [Sidekick]  [Orders (n)]  [theme]  [sign out] │
├ left nav (240px, collapsible) ─────────┬────────────────────────────────────────────────────┤
│ STOREFRONT DEPARTMENTS                 │                                                    │
│ ▸ Storefront Home                      │   main content (cards on soft-gray page)           │
│   All Cloud SKUs (n)                   │                                                    │
│   Fulfilled Orders                     │                                                    │
│   Saved Drafts                         │                                                    │
│   Recently Viewed                      │                                                    │
│   Buyer Settings                       │                                                    │
│ DIRECT SKU CHECKOUT                    │                                                    │
│   Spanner instance            GCP      │                                                    │
│   Cloud Storage bucket        GCP      │                                                    │
│   S3 bucket                   AWS      │                                                    │
│   …(frequent SKUs for this buyer)      │                                                    │
│ ┌ user card: name · persona ┐          │                                                    │
└────────────────────────────────────────┴────────────────────────────────────────────────────┘
                              ┌ Sidekick slide-over (420px, right) ─ opens from top-bar button or bottom composer ┐
```

- SSP-UI-001 Search is top-center, always visible, opens a command palette (⌘K / Ctrl-K) that searches SKUs, destinations, orders, resources and docs; results grouped; Enter opens, ⌘Enter opens Configure & Buy for a SKU (D-17 "search top-center").
- SSP-UI-002 Sidekick is reachable two ways: the top-bar button, and a **docked composer bar at the bottom of the main content** ("Ask Sidekick to configure a SKU…") that expands into the right slide-over on focus. This satisfies "chat at the bottom" and keeps the prototype's slide-over.
- SSP-UI-003 The left nav's "Direct SKU checkout" list is the catalog of frequent items: top 8 SKUs by the buyer's own order history, then LOB popularity, with cloud tag at right.
- SSP-UI-004 The delivery-destination selector in the top bar scopes the whole UI (home, orders, resources) to one tenant boundary or "All destinations".
- SSP-UI-005 Dark mode toggle persists per user; all tokens defined for both themes; contrast AA.

## 4. Screens

### 4.1 Storefront Home (`/`)
- Hero card: pill "Platform Authorized Storefront", title "Self-Service Cloud Infrastructure Store", one line of copy, buttons **Ask Sidekick Concierge** (outline) and **Shop All SKUs** (primary).
- "Delivery destinations" card: tabs per cloud with counts (AWS (6) · GCP (6) · Azure (4)); grid of destination cards: cloud tag, region, name, boundary id (mono), buyer role, **Select →**.
- SKU grid: cards with tag pill (cloud · category), wishlist star, name, one-line description, "Starting from $X/mo" (mono, primary), **Configure & Buy**.
- Two-column footer row: "Recently viewed items" (name, cloud, timestamp) and "Saved drafts" chips.
- SSP-UI-010 Everything on Home comes from `/catalog/services?sort=frequent`, `/destinations`, and local recently-viewed; no service-specific code.

### 4.2 All Cloud SKUs (`/skus`)
Filter rail (cloud, category, tags, data-class compatible), sort, grid/list toggle, same SKU card. SKU detail (`/skus/[service_id]`): docs from the bundle, guardrails preview ("what the platform enforces for your destination"), pricing table, frequent presets, **Configure & Buy**, "View module source" (version + ADR link).

### 4.3 Configure & Checkout (`/checkout/[service_id]?dest=<tenant_id>`)
Two-column: left the stepper and step cards; right the sticky **Infrastructure Order Summary** receipt.
- Header: back, SKU pill (`SKU: GCP-SPANNER · gcp`), title "Configure & Checkout: Cloud Spanner instance", **Delivery destination** select.
- Stepper from `ui.yaml.steps` (numbered chips; completed = filled). Step card header "CHECKOUT STEP n OF m" (section label style), title, description.
- Fields numbered `n.k` with the schema key shown in mono at right (as in the prototype: `1.1 Subscription  subscription`). Widgets by schema type and `x-ssp-widget`: text, select, radio-cards (enum with descriptions), number with unit, toggle, table (array of objects), key-value (labels), read-only derived field with reason link.
- Derived/injected fields render read-only with a small "Set by REQ-E-SPAN-0001-02 · Tier 1 / PHI" caption (SSP-PROD-031).
- Receipt: SKU, destination, "In stock"/"Needs CR"/"Needs owner sign-off" pill; ITEMIZED MONTHLY CHARGES from `estimate.lines`; Estimated Monthly Total (large, mono); "Billed to cost center CC-…"; guardrails applied (count, expandable); policy warnings; tabs **Summary | Code** where Code shows the Terraform module block and CLI (SSP-PROD-042, D-17).
- Primary action **Place order** (disabled until preflight valid); secondary **Save draft**, **Ask Sidekick about this**.
- SSP-UI-020 Every change debounces 400 ms then calls `POST /orders/preflight`; the receipt shows a subtle "updating" state and never displays client-computed money.
- SSP-UI-021 `Place order` sends `preview_hash`; on 409 the UI refreshes the receipt and asks the buyer to confirm again.
- SSP-UI-022 Unknown-service fixture: the checkout must render a never-seen ServiceSpec from the sandbox catalog with zero code changes (CI test).

### 4.4 Order tracking (`/orders/[order_id]`)
Timeline of the four states with timestamps; current gate (CR number with link, sign-off requester); run panel (plan summary +N ~M −K, live redacted log tail via SSE, link to run); post-build checklist with receipts; ETA from `eta_seconds_p50`; actions: Cancel (when allowed), View code, Open resource.

### 4.5 Fulfilled Orders (`/orders`) and Resources (`/resources`)
Data tables (shadcn `DataTable`): filter by destination, service, state; row click → detail. Resource detail: observed attributes (from outputs), drift findings with class badges, history of orders, actions **Change**, **Decommission**, **Re-run post-build**, **View code**.

### 4.6 Saved Drafts, Recently Viewed, Buyer Settings
Drafts = serialized `OrderInput` stored server-side per user (`/v1/drafts`, Phase 1.1; local storage until then). Settings: notification channels, default destination, theme.

### 4.7 Sidekick slide-over
Header "Sidekick Cloud Concierge — Instant SKU configuration & order prefill", reset and close. "Express SKU bundles" chips (frequent presets). Message list; assistant messages may carry cards: **Preflight card** (mini receipt + "Open in checkout" + "Place order"), **Status card**, **Citation chips** (ADR / requirement id → docs). Composer at bottom with send. See `17-conversational-provisioning-spec.md` for behaviour; SSP-UI-030 the slide-over never shows a "Place order" button unless the card came from a server preflight with a `preview_hash`.

## 5. Template-driven micro-frontend

- SSP-UI-040 `@ssp/form-renderer` takes `{requestSchema, uiTemplate, context, value}` and renders steps, fields and receipt bindings; it has no knowledge of any service.
- SSP-UI-041 Templates are fetched from the API (which reads the catalog bundle) at request time and cached by `(service_id, version)`; a new catalog publish is visible without a deploy.
- SSP-UI-042 Service-specific visuals (icons, hero images) are referenced by URL inside `ui.yaml`, served from the catalog bucket through the API.
- SSP-UI-043 Renderer contract is versioned (`ui.yaml` → `rendererVersion: 1`); unknown widgets fall back to a generic JSON field with a warning badge, never a crash.

## 6. Accessibility and quality

- SSP-UI-050 All interactive elements keyboard reachable; focus visible; radio-cards are real radios; tables have headers; color never the only signal (drift badges carry text).
- SSP-UI-051 Lighthouse a11y ≥ 95 and performance ≥ 85 on Home and Checkout in CI.
- SSP-UI-052 Visual regression (Playwright screenshots) for Home, SKU, Checkout steps, Receipt, Sidekick, in light and dark.

## 7. Repo structure (`ssp-ui`)

```
app/(shell)/layout.tsx            top bar, left nav, bottom composer, Sidekick slide-over
app/page.tsx                      Storefront Home
app/skus/page.tsx, app/skus/[serviceId]/page.tsx
app/checkout/[serviceId]/page.tsx
app/orders/page.tsx, app/orders/[orderId]/page.tsx
app/resources/page.tsx, app/resources/[id]/page.tsx
app/api/ssp/[...path]/route.ts    token-attaching proxy to ssp-cp
packages/form-renderer/           schema → steps/fields/receipt (published as @ssp/form-renderer)
packages/ui/                      shadcn components + tokens
lib/api/                          generated TS client from 12-openapi.yaml (openapi-typescript)
lib/sse.ts, lib/auth.ts
tests/e2e/, tests/fixtures/catalog/unknown-service/
```
